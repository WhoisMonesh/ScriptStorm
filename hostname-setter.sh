#!/bin/bash
# hostname-setter.sh - Changes system hostname
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides an interactive way to change the system hostname.
#              It updates both transient and static hostnames, and optionally updates
#              the /etc/hosts file for proper resolution.

# --- Configuration ---
LOG_FILE="/var/log/hostname-setter.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

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
        echo -e "${RED}Please run with 'sudo ./hostname-setter.sh'.${NC}"
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

# --- Hostname Management Functions ---
display_current_hostname() {
    print_subsection "Current System Hostname"
    if check_command "hostnamectl"; then
        echo -e "${MAGENTA}Using hostnamectl:${NC}"
        hostnamectl status | grep -E 'Static hostname|Transient hostname|Icon name'
        log_message "INFO" "Displayed hostnamectl status."
    else
        echo -e "${MAGENTA}Using hostname command:${NC}"
        hostname
        log_message "INFO" "Displayed hostname command output."
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Current hostname display completed."
}

set_new_hostname() {
    print_subsection "Set New System Hostname"
    local current_static_hostname
    if check_command "hostnamectl"; then
        current_static_hostname=$(hostnamectl status | grep "Static hostname" | awk -F': ' '{print $2}')
    else
        current_static_hostname=$(hostname)
    fi

    echo -e "${YELLOW}A valid hostname should contain only letters, numbers, hyphens, and dots.${NC}"
    echo -e "${YELLOW}It should not start or end with a hyphen, and dots are used for domain names.${NC}"
    local new_hostname=$(read_user_input "Enter the new desired hostname" "$current_static_hostname")

    if [ -z "$new_hostname" ]; then
        echo -e "${RED}ERROR: Hostname cannot be empty. Aborting.${NC}"
        log_message "WARN" "New hostname input was empty. Aborted setting hostname."
        return 1
    fi

    # Basic validation (can be more robust)
    if ! [[ "$new_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        echo -e "${RED}ERROR: Invalid hostname format. Please use letters, numbers, hyphens, and dots.${NC}"
        log_message "ERROR" "Invalid hostname format entered: '$new_hostname'."
        return 1
    fi

    echo -e "${CYAN}Setting system hostname to: ${new_hostname}${NC}"
    log_message "INFO" "Attempting to set hostname to '$new_hostname'."

    local hostname_set_success=false

    if check_command "hostnamectl"; then
        sudo hostnamectl set-hostname "$new_hostname"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Hostname set successfully using 'hostnamectl'!${NC}"
            hostname_set_success=true
            log_message "SUCCESS" "Hostname successfully set to '$new_hostname' using hostnamectl."
        else
            echo -e "${RED}ERROR: Failed to set hostname using 'hostnamectl'. Check systemd-hostnamed service.${NC}"
            log_message "ERROR" "Failed to set hostname '$new_hostname' using hostnamectl."
        fi
    else
        # Fallback for systems without hostnamectl (e.g., older init systems)
        sudo hostname "$new_hostname" # Sets transient hostname
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Transient hostname set successfully!${NC}"
            log_message "SUCCESS" "Transient hostname set to '$new_hostname'."
            
            echo -e "${CYAN}Updating /etc/hostname for persistence...${NC}"
            echo "$new_hostname" | sudo tee /etc/hostname >/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Static hostname updated in /etc/hostname.${NC}"
                hostname_set_success=true
                log_message "SUCCESS" "Static hostname updated in /etc/hostname."
            else
                echo -e "${RED}ERROR: Failed to update /etc/hostname. Manual update required for persistence.${NC}"
                log_message "ERROR" "Failed to update /etc/hostname."
            fi
        else
            echo -e "${RED}ERROR: Failed to set transient hostname with 'hostname' command.${NC}"
            log_message "ERROR" "Failed to set transient hostname with 'hostname'."
        fi
    fi

    if [ "$hostname_set_success" = true ]; then
        read -r -p "Do you want to update /etc/hosts file? (Y/n): " update_hosts
        if [[ ! "$update_hosts" =~ ^[Nn]$ ]]; then
            update_etc_hosts "$new_hostname" "$current_static_hostname"
        else
            echo -e "${CYAN}Skipping /etc/hosts update.${NC}"
            log_message "INFO" "Skipped /etc/hosts update (user choice)."
        fi
        echo -e "${YELLOW}NOTE: Some applications or services might require a reboot or restart to fully recognize the new hostname.${NC}"
        log_message "INFO" "Advised user about potential reboot/service restart."
        display_current_hostname # Show new current hostname settings
    else
        echo -e "${RED}Hostname setting process failed. Please review error messages and logs.${NC}"
        log_message "ERROR" "Hostname setting process failed."
    fi
    return 0
}

update_etc_hosts() {
    local new_hostname="$1"
    local old_hostname="$2"
    print_subsection "Updating /etc/hosts"

    local local_ip="127.0.0.1"
    local local_line="$local_ip localhost"

    # Remove old hostname entries if they exist for 127.0.0.1
    # This sed command carefully replaces 'localhost' line to ensure it contains new hostname
    # without duplicating the hostname or removing other aliases.
    # It first removes lines containing old_hostname or new_hostname if they are not the 'localhost' line itself
    # Then it replaces the line starting with 127.0.0.1 and containing 'localhost'
    
    # Ensure a backup of /etc/hosts
    sudo cp /etc/hosts /etc/hosts.bak_$(date "$DATE_FORMAT")
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to create backup of /etc/hosts. Aborting hosts update.${NC}"
        log_message "ERROR" "Failed to backup /etc/hosts."
        return 1
    fi
    echo -e "${GREEN}Backed up /etc/hosts to /etc/hosts.bak_$(date "$DATE_FORMAT").${NC}"
    log_message "INFO" "Backed up /etc/hosts."

    # Remove lines containing old_hostname (if it's not localhost)
    if [ -n "$old_hostname" ] && [ "$old_hostname" != "localhost" ] && grep -q "$old_hostname" /etc/hosts; then
        sudo sed -i "/[[:space:]]\b$old_hostname\b/d" /etc/hosts
        echo -e "${GREEN}Removed old hostname '$old_hostname' from /etc/hosts.${NC}"
        log_message "SUCCESS" "Removed old hostname '$old_hostname' from /etc/hosts."
    fi

    # Check if the new hostname is already on the localhost line
    if ! grep -q "^${local_ip}.*\\b${new_hostname}\\b" /etc/hosts; then
        # Replace or append new hostname to the 127.0.0.1 localhost line
        # This regex looks for 127.0.0.1 followed by whitespace and then 'localhost'
        if grep -q "^${local_ip}[[:space:]]\+localhost" /etc/hosts; then
            sudo sed -i "s/^\\(${local_ip}[[:space:]]\\+localhost\\)\\b.*/\\1 ${new_hostname}/" /etc/hosts
            echo -e "${GREEN}Updated 127.0.0.1 entry in /etc/hosts with new hostname '${new_hostname}'.${NC}"
            log_message "SUCCESS" "Updated 127.0.0.1 entry in /etc/hosts with '$new_hostname'."
        else
            echo -e "${YELLOW}Warning: '127.0.0.1 localhost' entry not found. Appending new line.${NC}"
            echo "$local_ip $new_hostname localhost" | sudo tee -a /etc/hosts >/dev/null
            echo -e "${GREEN}Added new entry for '${new_hostname}' to /etc/hosts.${NC}"
            log_message "SUCCESS" "Added new entry for '$new_hostname' to /etc/hosts."
        fi
    else
        echo -e "${YELLOW}New hostname '${new_hostname}' already present on 127.0.0.1 line in /etc/hosts. No change needed.${NC}"
        log_message "INFO" "New hostname already present in /etc/hosts. No change."
    fi
    
    echo -e "${CYAN}Current /etc/hosts content (first 10 lines):${NC}"
    sudo head -n 10 /etc/hosts
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "/etc/hosts update process completed."
    return 0
}

explain_hostname() {
    print_subsection "About System Hostname"
    echo -e "${CYAN}What is a Hostname?${NC}"
    echo "  - A hostname is a label that is assigned to a device connected to a computer network"
    echo "    and that is used to identify the device in various forms of electronic communication,"
    echo "    such as the World Wide Web."
    echo "  - It's essentially your computer's name on the network."
    echo ""
    echo -e "${CYAN}Types of Hostnames:${NC}"
    echo "  - ${MAGENTA}Static hostname:${NC} The traditional hostname. Stored in /etc/hostname."
    echo "    This is the primary hostname and is persistent across reboots."
    echo "  - ${MAGENTA}Transient hostname:${NC} A dynamic hostname, which is typically derived"
    echo "    from network configuration (e.g., DHCP or mDNS). It defaults to the static hostname"
    echo "    if no other source is configured. It is not persistent across reboots."
    echo "  - ${MAGENTA}Pretty hostname:${NC} A free-form UTF-8 hostname for presentation to the user."
    echo "    (e.g., 'My Awesome Laptop'). Not used for network communication."
    echo ""
    echo -e "${CYAN}Why configure Hostname?${NC}"
    echo "  - ${GREEN}Network Identification:${NC} Essential for other devices on the network"
    echo "    to identify and communicate with your system."
    echo "  - ${YELLOW}Application Functionality:${NC} Many server applications and services"
    echo "    rely on the correct hostname for configuration and operation."
    echo "  - ${RED}Security:${NC} A clear and consistent hostname helps in logging and auditing."
    echo ""
    echo -e "${CYAN}Important Considerations:${NC}"
    echo "  - After changing the hostname, some running applications or services (e.g., SSH, web servers)"
    echo "    might need to be restarted or even the system rebooted to fully recognize the new name."
    echo "  - Updating the '/etc/hosts' file is good practice to ensure local resolution"
    echo "    of your hostname to 127.0.0.1 (localhost loopback address)."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Hostname explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Hostname Setter (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Display Current Hostname${NC}"
    echo -e "${GREEN}2. Set New System Hostname${NC}"
    echo -e "${GREEN}3. About Hostname & Best Practices${NC}"
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

    log_message "INFO" "Hostname setter script started."

    # Check for hostnamectl, prefer it but fallback to hostname command
    if ! check_command "hostnamectl" && ! check_command "hostname"; then
        echo -e "${RED}ERROR: Neither 'hostnamectl' nor 'hostname' command found. Exiting.${NC}"
        log_message "ERROR" "Neither 'hostnamectl' nor 'hostname' command found. Exiting."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_current_hostname; pause_script ;;
            2) set_new_hostname; pause_script ;;
            3) explain_hostname; pause_script ;;
            0)
                echo -e "${CYAN}Exiting System Hostname Setter. Goodbye!${NC}"
                log_message "INFO" "Hostname setter script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 3.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
