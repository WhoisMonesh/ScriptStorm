#!/bin/bash
# selinux-toggle.sh - SELinux status manager
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script allows users to check the status of SELinux,
#              and set it to enforcing, permissive, or disabled mode.
#              It handles necessary reboots for changes to take effect.

# --- Configuration ---
LOG_FILE="/var/log/selinux-toggle.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

SELINUX_CONFIG_FILE="/etc/selinux/config" # Main SELinux configuration file

# --- Colors for better readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_message() {
    local type="$1" # INFO, WARN, ERROR, SUCCESS, ALERT
    local message="$2"
    echo -e "$(date "$DATE_FORMAT") [${type}] ${message}" | tee -a "$LOG_FILE"
}

print_header() {
    local title="$1"
    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${BLUE}>>> ${title}${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_subsection() {
    local title="$1"
    echo -e "\n${GREEN}--- ${title} ---${NC}"
}

check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
    return $?
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root.${NC}"
        echo -e "${RED}Please run with 'sudo ./selinux-toggle.sh'.${NC}"
        log_message "ERROR" "Script not run as root."
        exit 1
    fi
    log_message "INFO" "Script is running as root."
}

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

read_user_input() {
    local prompt="$1"
    local default_value="$2"
    local input=""

    if [ -n "$default_value" ]; then
        echo -n "$prompt [$default_value]: "
    else
        echo -n "$prompt: "
    fi
    read -r input

    if [ -z "$input" ] && [ -n "$default_value" ]; then
        echo "$default_value"
    else
        echo "$input"
    fi
}

# --- SELinux Functions ---
check_selinux_installed() {
    if [ ! -f "$SELINUX_CONFIG_FILE" ]; then
        echo -e "${YELLOW}WARNING: SELinux configuration file '$SELINUX_CONFIG_FILE' not found.${NC}"
        echo -e "${YELLOW}SELinux might not be installed or enabled on this system.${NC}"
        log_message "WARN" "SELinux config file '$SELINUX_CONFIG_FILE' not found."
        return 1
    fi
    if ! check_command "sestatus" && ! check_command "setenforce" && ! check_command "getenforce"; then
        echo -e "${RED}ERROR: SELinux utilities (sestatus, setenforce, getenforce) not found.${NC}"
        echo -e "${RED}Please ensure 'policycoreutils' or similar package is installed.${NC}"
        log_message "ERROR" "SELinux utilities not found."
        return 1
    fi
    log_message "INFO" "SELinux appears to be installed."
    return 0
}

display_selinux_status() {
    print_subsection "Current SELinux Status"
    if ! check_selinux_installed; then
        echo -e "${RED}Cannot display SELinux status. Prerequisites not met.${NC}"
        return 1
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    if check_command "sestatus"; then
        sestatus
        log_message "INFO" "Displayed sestatus output."
    elif check_command "getenforce"; then
        local current_enforce=$(getenforce)
        local config_status=$(grep '^SELINUX=' "$SELINUX_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
        echo -e "${MAGENTA}Current mode (runtime):${NC} ${current_enforce}"
        echo -e "${MAGENTA}Configured mode (/etc/selinux/config):${NC} ${config_status:-Not Found}"
        log_message "INFO" "Displayed getenforce and config file status."
    else
        echo -e "${RED}No SELinux status command found (sestatus, getenforce).${NC}"
        log_message "ERROR" "No SELinux status command found."
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "SELinux status display completed."
}

set_selinux_mode() {
    local target_mode="$1" # enforcing, permissive, disabled

    print_subsection "Setting SELinux to ${target_mode^^} Mode"
    if ! check_selinux_installed; then
        return 1
    fi

    echo -e "${YELLOW}WARNING: Changing SELinux mode can affect system security and application behavior.${NC}"

    case "$target_mode" in
        enforcing)
            echo -e "${RED}ENFORCING mode strictly enforces security policies. Misconfiguration can prevent your system from booting or applications from running.${NC}"
            ;;
        permissive)
            echo -e "${YELLOW}PERMISSIVE mode logs violations but does not enforce them. Useful for troubleshooting but provides no security enforcement.${NC}"
            ;;
        disabled)
            echo -e "${RED}DISABLED mode turns off SELinux completely. This significantly reduces your system's security posture.${NC}"
            echo -e "${RED}A reboot is REQUIRED for SELinux to be truly disabled.${NC}"
            ;;
    esac

    read -r -p "Are you sure you want to set SELinux to ${target_mode^^} mode? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Aborting SELinux mode change.${NC}"
        log_message "INFO" "Aborted SELinux mode change to '$target_mode' (user choice)."
        return 1
    fi

    log_message "INFO" "Attempting to set SELinux to '$target_mode'."

    # 1. Update /etc/selinux/config
    local old_config_mode=$(grep '^SELINUX=' "$SELINUX_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$old_config_mode" ]; then
        sudo sed -i "s/^SELINUX=.*/SELINUX=$target_mode/" "$SELINUX_CONFIG_FILE"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Updated '$SELINUX_CONFIG_FILE' from '$old_config_mode' to '$target_mode'.${NC}"
            log_message "SUCCESS" "Updated $SELINUX_CONFIG_FILE to SELINUX=$target_mode."
        else
            echo -e "${RED}ERROR: Failed to update '$SELINUX_CONFIG_FILE'. Check permissions.${NC}"
            log_message "ERROR" "Failed to update $SELINUX_CONFIG_FILE."
            return 1
        fi
    else
        echo -e "${YELLOW}Warning: 'SELINUX=' entry not found in '$SELINUX_CONFIG_FILE'. Appending new entry.${NC}"
        echo "SELINUX=$target_mode" | sudo tee -a "$SELINUX_CONFIG_FILE" >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Added 'SELINUX=$target_mode' to '$SELINUX_CONFIG_FILE'.${NC}"
            log_message "SUCCESS" "Added SELINUX=$target_mode to $SELINUX_CONFIG_FILE."
        else
            echo -e "${RED}ERROR: Failed to add 'SELINUX=$target_mode' to '$SELINUX_CONFIG_FILE'.${NC}"
            log_message "ERROR" "Failed to add SELINUX=$target_mode to $SELINUX_CONFIG_FILE."
            return 1
        fi
    fi

    # 2. Apply runtime change (if applicable)
    if [ "$target_mode" != "disabled" ]; then
        if check_command "setenforce"; then
            echo -e "${CYAN}Attempting to set runtime SELinux mode...${NC}"
            sudo setenforce "${target_mode^}" # setenforce expects Enforcing or Permissive
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Runtime SELinux mode set to ${target_mode^^}!${NC}"
                log_message "SUCCESS" "Runtime SELinux set to '$target_mode'."
            else
                echo -e "${RED}ERROR: Failed to set runtime SELinux mode with 'setenforce'.${NC}"
                echo -e "${RED}This might happen if transitioning from 'disabled' without reboot.${NC}"
                log_message "ERROR" "Failed to set runtime SELinux with setenforce."
                # Don't exit, still allow reboot prompt
            fi
        else
            echo -e "${YELLOW}Warning: 'setenforce' command not found. Runtime change not applied.${NC}"
            log_message "WARN" "'setenforce' command not found. Runtime change skipped."
        fi
    fi

    if [ "$target_mode" = "disabled" ] || [ "$old_config_mode" = "disabled" ]; then
        echo -e "${RED}A system reboot is REQUIRED for SELinux mode change to '${target_mode^^}' to take full effect.${NC}"
        read -r -p "Reboot now? (y/N): " confirm_reboot
        if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
            log_message "INFO" "User opted to reboot for SELinux change to '$target_mode'."
            echo -e "${CYAN}Rebooting system... Goodbye!${NC}"
            sudo reboot
        else
            echo -e "${YELLOW}Please remember to reboot your system manually for the changes to apply.${NC}"
            log_message "INFO" "User chose not to reboot. Advised manual reboot."
        fi
    else
        echo -e "${GREEN}SELinux mode configuration updated. Runtime change applied if possible.${NC}"
        echo -e "${YELLOW}Consider a reboot for the policy to be fully reloaded, especially from permissive to enforcing.${NC}"
        log_message "INFO" "SELinux config updated. Reboot recommended for full effect."
    fi
    display_selinux_status # Show new status
    return 0
}

explain_selinux() {
    print_subsection "About SELinux"
    echo -e "${CYAN}What is SELinux?${NC}"
    echo "  - SELinux (Security-Enhanced Linux) is a Linux kernel security module that"
    echo "    provides a mechanism for supporting access control security policies,"
    echo "    including mandatory access controls (MAC)."
    echo "  - It works alongside traditional Linux permissions (DAC - Discretionary Access Control)."
    echo "    Even if a user or process has DAC permissions, SELinux can still deny access."
    echo ""
    echo -e "${CYAN}SELinux Modes:${NC}"
    echo "  - ${GREEN}Enforcing:${NC} SELinux security policy is enforced. Denials are logged"
    echo "    and actions are prevented. This is the most secure mode."
    echo "  - ${YELLOW}Permissive:${NC} SELinux security policy is not enforced. Denials are"
    echo "    logged but actions are permitted. This mode is useful for troubleshooting"
    echo "    and debugging policy issues without breaking applications."
    echo "  - ${RED}Disabled:${NC} SELinux is completely turned off. No policies are loaded"
    echo "    or enforced. This significantly reduces the system's security posture."
    echo ""
    echo -e "${CYAN}Important Considerations:${NC}"
    echo "  - Changing from 'disabled' to 'enforcing' or 'permissive' REQUIRES a reboot"
    echo "    to relabel the entire filesystem, which can take time."
    echo "  - Incorrectly configured SELinux in 'enforcing' mode can break applications"
    echo "    or even prevent the system from booting. Always test changes carefully."
    echo "  - Check logs for SELinux denials (e.g., /var/log/audit/audit.log or journalctl -t AVC)."
    echo "    Use 'audit2allow' to generate policy rules for specific denials."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "SELinux explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> SELinux Status Manager (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Display Current SELinux Status${NC}"
    echo -e "${GREEN}2. Set SELinux to Enforcing Mode${NC}"
    echo -e "${GREEN}3. Set SELinux to Permissive Mode${NC}"
    echo -e "${GREEN}4. Set SELinux to Disabled Mode${NC}"
    echo -e "${GREEN}5. About SELinux & Modes${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    check_root

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_message "INFO" "SELinux toggle script started."

    # Pre-check SELinux installation, but allow to proceed if config file exists
    if ! check_selinux_installed; then
        echo -e "${YELLOW}SELinux might not be fully configured or installed. Some options may not work.${NC}"
        log_message "WARN" "SELinux initial check failed. User warned."
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_selinux_status; pause_script ;;
            2) set_selinux_mode "enforcing"; pause_script ;;
            3) set_selinux_mode "permissive"; pause_script ;;
            4) set_selinux_mode "disabled"; pause_script ;;
            5) explain_selinux; pause_script ;;
            0)
                echo -e "${CYAN}Exiting SELinux Status Manager. Goodbye!${NC}"
                log_message "INFO" "SELinux toggle script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 5.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
