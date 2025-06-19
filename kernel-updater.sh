#!/bin/bash

# kernel-updater.sh - Kernel Update Automation
# Version: 1.1
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script automates kernel updates for various Linux distributions.
#              It checks for new kernels, performs the update, manages GRUB,
#              handles old kernel removal, and provides notifications.
#              It includes an 'unattended mode' for automated execution, but
#              this mode should be used with extreme caution due to the critical
#              nature of kernel updates and reboots.
#              CRITICAL: Always backup your system before major updates.

# --- Configuration ---
LOG_FILE="/var/log/kernel-updater.log"    # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Set to "true" for fully automated execution (DANGEROUS without proper testing!)
# When true, prompts for confirmation and reboots are skipped/automated.
UNATTENDED_MODE="false"

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send success/failure alerts
SENDER_EMAIL="kernel-updater@yourdomain.com" # Sender email for alerts

# GRUB Backup Settings
GRUB_BACKUP_DIR="/var/backups/grub" # Directory to store GRUB configuration backups
GRUB_CONFIG_FILE_APT="/boot/grub/grub.cfg"
GRUB_CONFIG_FILE_DNF_YUM="/boot/grub2/grub.cfg" # Or /boot/efi/EFI/<distro>/grub.cfg for EFI
GRUB_DEFAULT_CONF="/etc/default/grub"

# Old Kernel Retention
# IMPORTANT: Keep at least 2-3 kernels to ensure you can boot into a stable one if needed.
KERNELS_TO_KEEP=2 # Number of most recent kernels to keep

# --- Colors for better readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Global Variables for Detected Package Manager & Kernel Commands ---
PKG_MANAGER=""          # e.g., "apt", "dnf", "yum", "pacman", "zypper"
KERNEL_UPDATE_CMD=""    # Command to install/upgrade new kernel
KERNEL_LIST_CMD=""      # Command to list installed kernels
KERNEL_REMOVE_CMD_PREFIX="" # Prefix for removing specific kernel (e.g., "sudo apt remove --purge")
GRUB_UPDATE_CMD=""      # Command to update GRUB configuration

# --- Helper Functions ---

log_message() {
    local type="$1" # INFO, WARN, ERROR, SUCCESS
    local message="$2"
    echo -e "$(date "$DATE_FORMAT") [${type}] ${message}" | tee -a "$LOG_FILE"
}

send_email_alert() {
    local subject="$1"
    local body="$2"
    if [ -z "$NOTIFICATION_EMAIL" ] || [ "$NOTIFICATION_EMAIL" == "your_email@example.com" ]; then
        log_message "WARN" "Notification email not configured. Skipping email alert for: $subject"
        echo -e "${YELLOW}WARNING: Notification email not configured. Set NOTIFICATION_EMAIL in script.${NC}"
        return 1
    fi

    echo "$body" | mail -s "$subject" -r "$SENDER_EMAIL" "$NOTIFICATION_EMAIL"
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Email alert sent: '$subject'"
    else
        log_message "ERROR" "Failed to send email alert: '$subject'. Check mail configuration (e.g., 'mailutils' package)."
        echo -e "${RED}ERROR: Failed to send email alert. Check 'mail' command setup.${NC}"
    fi
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
        echo -e "${RED}ERROR: This script must be run as root to perform kernel updates and GRUB operations.${NC}"
        log_message "ERROR" "Attempted to run script as non-root user."
        exit 1
    fi
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

confirm_action() {
    local prompt="$1"
    if [ "$UNATTENDED_MODE" == "true" ]; then
        echo -e "${YELLOW}UNATTENDED MODE: Automatically confirming '$prompt'.${NC}"
        log_message "INFO" "UNATTENDED MODE: Automatically confirming '$prompt'."
        return 0 # Auto-confirm
    fi
    echo -n "${YELLOW}$prompt (yes/no): ${NC}"
    read -r response
    if [[ "$response" =~ ^[yY][eE][sS]$ ]]; then
        return 0 # True
    else
        echo -e "${YELLOW}Action cancelled.${NC}"
        return 1 # False
    fi
}

# --- Package Manager & Kernel Command Detection ---

detect_package_manager() {
    log_message "INFO" "Detecting package manager and kernel update commands..."
    if check_command "apt"; then
        PKG_MANAGER="apt"
        KERNEL_UPDATE_CMD="sudo apt update && sudo apt upgrade -y" # apt upgrade includes kernel
        KERNEL_LIST_CMD="dpkg -l | grep -E '^ii  linux-image|^ii  linux-headers' | awk '{print \$2}' | sort -V"
        KERNEL_REMOVE_CMD_PREFIX="sudo apt remove --purge -y"
        GRUB_UPDATE_CMD="sudo update-grub"
        echo -e "${GREEN}Detected: APT (Debian/Ubuntu based system)${NC}"
    elif check_command "dnf"; then
        PKG_MANAGER="dnf"
        KERNEL_UPDATE_CMD="sudo dnf upgrade -y"
        # dnf repoquery --installonly filters out older kernels installed as alternatives
        KERNEL_LIST_CMD="sudo dnf repoquery --installonly --latest-limit=-1 -q kernel | awk -F'.' '{print \$1\"-\"\$2}' | sort -V"
        KERNEL_REMOVE_CMD_PREFIX="sudo dnf remove -y"
        GRUB_UPDATE_CMD="sudo grub2-mkconfig -o $(find /boot/efi -name grub.cfg 2>/dev/null || echo /boot/grub2/grub.cfg)" # Adaptive for EFI/BIOS
        echo -e "${GREEN}Detected: DNF (Fedora/RHEL 8+ based system)${NC}"
    elif check_command "yum"; then
        PKG_MANAGER="yum"
        KERNEL_UPDATE_CMD="sudo yum update -y"
        KERNEL_LIST_CMD="rpm -q kernel | sort -V"
        KERNEL_REMOVE_CMD_PREFIX="sudo yum remove -y"
        GRUB_UPDATE_CMD="sudo grub2-mkconfig -o $(find /boot/efi -name grub.cfg 2>/dev/null || echo /boot/grub2/grub.cfg)"
        echo -e "${GREEN}Detected: YUM (Older CentOS/RHEL 7- based system)${NC}"
    elif check_command "pacman"; then
        PKG_MANAGER="pacman"
        KERNEL_UPDATE_CMD="sudo pacman -Syu --noconfirm"
        KERNEL_LIST_CMD="pacman -Qq | grep '^linux$' || pacman -Qq | grep '^linux-lts$' || pacman -Qq | grep '^linux-zen$' || pacman -Qq | grep '^linux-hardened$'" # List installed kernel packages
        KERNEL_REMOVE_CMD_PREFIX="sudo pacman -Rns --noconfirm"
        GRUB_UPDATE_CMD="sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo -e "${GREEN}Detected: Pacman (Arch Linux based system)${NC}"
    elif check_command "zypper"; then
        PKG_MANAGER="zypper"
        KERNEL_UPDATE_CMD="sudo zypper update -y"
        KERNEL_LIST_CMD="rpm -qa | grep kernel | sort -V"
        KERNEL_REMOVE_CMD_PREFIX="sudo zypper remove -y"
        GRUB_UPDATE_CMD="sudo grub2-mkconfig -o $(find /boot/efi -name grub.cfg 2>/dev/null || echo /boot/grub2/grub.cfg)"
        echo -e "${GREEN}Detected: Zypper (openSUSE/SLES based system)${NC}"
    else
        echo -e "${RED}ERROR: No supported package manager (apt, dnf, yum, pacman, zypper) detected.${NC}"
        log_message "ERROR" "No supported package manager detected for kernel updates."
        exit 1
    fi
    log_message "INFO" "Package manager '$PKG_MANAGER' detected with kernel commands."
}

# --- Kernel Management Functions ---

backup_grub_config() {
    print_subsection "Backing up GRUB Configuration"
    mkdir -p "$GRUB_BACKUP_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to create GRUB backup directory '$GRUB_BACKUP_DIR'.${NC}"
        log_message "ERROR" "GRUB backup failed: directory creation."
        send_email_alert "Kernel Update Warning: GRUB Backup Failed" "Failed to create GRUB backup directory $GRUB_BACKUP_DIR on $(hostname)."
        return 1
    fi

    local backup_tag="grub_$(uname -r)_$(date "$DATE_FORMAT")"
    local grub_cfg_target=""

    # Determine GRUB config path based on detected manager
    case "$PKG_MANAGER" in
        "apt") grub_cfg_target="$GRUB_CONFIG_FILE_APT" ;;
        "dnf"|"yum"|"zypper") grub_cfg_target="$GRUB_CONFIG_FILE_DNF_YUM" ;;
        "pacman") grub_cfg_target="$GRUB_CONFIG_FILE_APT" ;; # Arch usually uses /boot/grub/grub.cfg
        *) log_message "WARN" "Unknown GRUB config path for $PKG_MANAGER.";;
    esac

    echo -e "${CYAN}Backing up '$GRUB_DEFAULT_CONF' to '$GRUB_BACKUP_DIR/$backup_tag-default.conf'...${NC}"
    cp -p "$GRUB_DEFAULT_CONF" "$GRUB_BACKUP_DIR/$backup_tag-default.conf"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to backup $GRUB_DEFAULT_CONF.${NC}"
        log_message "ERROR" "Failed to backup $GRUB_DEFAULT_CONF."
        send_email_alert "Kernel Update Warning: GRUB Backup Failed" "Failed to backup $GRUB_DEFAULT_CONF on $(hostname)."
    else
        echo -e "${GREEN}Successfully backed up $GRUB_DEFAULT_CONF.${NC}"
        log_message "SUCCESS" "Backed up $GRUB_DEFAULT_CONF."
    fi

    if [ -f "$grub_cfg_target" ]; then
        echo -e "${CYAN}Backing up '$grub_cfg_target' to '$GRUB_BACKUP_DIR/$backup_tag-grub.cfg'...${NC}"
        cp -p "$grub_cfg_target" "$GRUB_BACKUP_DIR/$backup_tag-grub.cfg"
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to backup $grub_cfg_target.${NC}"
            log_message "ERROR" "Failed to backup $grub_cfg_target."
            send_email_alert "Kernel Update Warning: GRUB Backup Failed" "Failed to backup $grub_cfg_target on $(hostname)."
        else
            echo -e "${GREEN}Successfully backed up $grub_cfg_target.${NC}"
            log_message "SUCCESS" "Backed up $grub_cfg_target."
        fi
    else
        echo -e "${YELLOW}WARNING: GRUB config file '$grub_cfg_target' not found or is not a regular file. Skipping backup.${NC}"
        log_message "WARN" "GRUB config file '$grub_cfg_target' not found."
    fi
    pause_script
}

check_for_kernel_updates() {
    print_subsection "Checking for New Kernel Updates"
    echo -e "${CYAN}Running $PKG_MANAGER update/check for new kernels...${NC}"
    log_message "INFO" "Checking for kernel updates using '$KERNEL_UPDATE_CMD'."

    local kernel_update_available=1 # Default to not available

    case "$PKG_MANAGER" in
        "apt")
            sudo apt update > /dev/null 2>&1
            if apt list --upgradable 2>/dev/null | grep -qE "linux-image|linux-headers"; then
                echo -e "${YELLOW}New kernel updates are available!${NC}"
                log_message "INFO" "New kernel updates available."
                kernel_update_available=0
            else
                echo -e "${GREEN}No new kernel updates found.${NC}"
                log_message "INFO" "No new kernel updates."
            fi
            ;;
        "dnf"|"yum")
            sudo "${PKG_MANAGER}" check-update > /dev/null 2>&1
            if sudo "${PKG_MANAGER}" list updates kernel\* 2>/dev/null | grep -q "kernel"; then
                echo -e "${YELLOW}New kernel updates are available!${NC}"
                log_message "INFO" "New kernel updates available."
                kernel_update_available=0
            else
                echo -e "${GREEN}No new kernel updates found.${NC}"
                log_message "INFO" "No new kernel updates."
            fi
            ;;
        "pacman")
            sudo pacman -Sy > /dev/null 2>&1
            if pacman -Qu 2>/dev/null | grep -q "^linux\|^linux-lts\|^linux-zen\|^linux-hardened"; then
                echo -e "${YELLOW}New kernel updates are available!${NC}"
                log_message "INFO" "New kernel updates available."
                kernel_update_available=0
            else
                echo -e "${GREEN}No new kernel updates found.${NC}"
                log_message "INFO" "No new kernel updates."
            fi
            ;;
        "zypper")
            sudo zypper refresh > /dev/null 2>&1
            if zypper list-patches | grep -qE "kernel-default|kernel-source|kernel-devel"; then # Checks for kernel patches
                echo -e "${YELLOW}New kernel updates/patches are available!${NC}"
                log_message "INFO" "New kernel updates available."
                kernel_update_available=0
            else
                echo -e "${GREEN}No new kernel updates/patches found.${NC}"
                log_message "INFO" "No new kernel updates."
            fi
            ;;
        *)
            echo -e "${RED}ERROR: Cannot check for updates for unknown package manager: $PKG_MANAGER.${NC}"
            log_message "ERROR" "Cannot check for updates for unknown PM: $PKG_MANAGER."
            kernel_update_available=1
            ;;
    esac
    pause_script
    return $kernel_update_available
}

perform_kernel_update() {
    print_subsection "Performing Kernel Update"
    echo -e "${YELLOW}WARNING: Updating the kernel is a critical operation.${NC}"
    echo -e "${YELLOW}Ensure you have backups before proceeding. A reboot will be required.${NC}"
    if ! confirm_action "Do you want to proceed with the kernel update?"; then
        return 1
    fi

    backup_grub_config # Always back up GRUB before an update

    echo -e "${CYAN}Running '$KERNEL_UPDATE_CMD' to update kernel...${NC}"
    log_message "INFO" "Starting kernel update via '$KERNEL_UPDATE_CMD'."
    eval "$KERNEL_UPDATE_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Kernel update command executed successfully.${NC}"
        log_message "SUCCESS" "Kernel update command successful."
        update_grub # Ensure GRUB is updated after new kernel
    else
        echo -e "${RED}ERROR: Kernel update command FAILED.${NC}"
        log_message "ERROR" "Kernel update command FAILED."
        send_email_alert "Kernel Update FAILED" "Kernel update command '$KERNEL_UPDATE_CMD' failed on $(hostname). Please investigate."
    fi
    pause_script
}

update_grub() {
    print_subsection "Updating GRUB Bootloader Configuration"
    if [ -z "$GRUB_UPDATE_CMD" ]; then
        echo -e "${YELLOW}WARNING: No GRUB update command configured for $PKG_MANAGER. Manual update may be required.${NC}"
        log_message "WARN" "No GRUB update command configured for $PKG_MANAGER."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Running '$GRUB_UPDATE_CMD' to update GRUB...${NC}"
    log_message "INFO" "Updating GRUB using '$GRUB_UPDATE_CMD'."
    eval "$GRUB_UPDATE_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}GRUB configuration updated successfully.${NC}"
        log_message "SUCCESS" "GRUB configuration updated."
        send_email_alert "Kernel Update Info: GRUB Updated" "GRUB configuration updated successfully after kernel operation on $(hostname)."
    else
        echo -e "${RED}ERROR: Failed to update GRUB configuration. System may not boot into new kernel!${NC}"
        log_message "ERROR" "Failed to update GRUB configuration."
        send_email_alert "Kernel Update CRITICAL: GRUB Update Failed" "GRUB update command '$GRUB_UPDATE_CMD' FAILED on $(hostname). System may not boot correctly."
    fi
    pause_script
}

manage_old_kernels() {
    print_subsection "Managing Old Kernels"
    echo -e "${YELLOW}Current running kernel: $(uname -r)${NC}"
    echo -e "${CYAN}Listing all installed kernel packages...${NC}"
    
    local installed_kernels
    installed_kernels=$(eval "$KERNEL_LIST_CMD" 2>/dev/null)
    if [ -z "$installed_kernels" ]; then
        echo -e "${RED}ERROR: Could not list installed kernels. Check command: '$KERNEL_LIST_CMD'.${NC}"
        log_message "ERROR" "Failed to list installed kernels."
        pause_script
        return 1
    fi

    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    echo "$installed_kernels"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    local old_kernels_to_remove=""
    # Filter out the running kernel and the N most recent kernels
    local sorted_kernels_array=($(echo "$installed_kernels" | sort -rV)) # Sort descending
    local current_kernel_full=$(uname -r) # e.g., 5.15.0-101-generic
    local current_kernel_base=$(echo "$current_kernel_full" | sed 's/\(.*\)-\(.*\)/\1/') # e.g., 5.15.0-101

    local kernels_to_keep_final=()
    local kernels_for_removal_final=()
    local kept_count=0

    for kernel_pkg_name in "${sorted_kernels_array[@]}"; do
        # Check if it's the currently running kernel's package
        # APT specific: check if it contains the full running kernel string
        # RPM specific: check if it's the exact RPM package name for the running kernel
        if [[ "$kernel_pkg_name" == *"$current_kernel_full"* ]]; then
             if [[ ! " ${kernels_to_keep_final[*]} " =~ " ${kernel_pkg_name} " ]]; then
                kernels_to_keep_final+=("$kernel_pkg_name")
             fi
             continue
        fi

        # Logic to keep the N most recent *different* kernels
        if [ "$kept_count" -lt "$KERNELS_TO_KEEP" ]; then
            # Add to keep list if not already there
            if [[ ! " ${kernels_to_keep_final[*]} " =~ " ${kernel_pkg_name} " ]]; then
                kernels_to_keep_final+=("$kernel_pkg_name")
                kept_count=$((kept_count + 1))
            fi
        else
            # Add to removal list
            if [[ ! " ${kernels_for_removal_final[*]} " =~ " ${kernel_pkg_name} " ]]; then
                kernels_for_removal_final+=("$kernel_pkg_name")
            fi
        fi
    done

    echo -e "${YELLOW}Kernels to KEEP (current: $current_kernel_full + $KERNELS_TO_KEEP most recent):${NC}"
    if [ ${#kernels_to_keep_final[@]} -eq 0 ]; then
        echo "  (None identified based on policy. This might be incorrect for single kernel systems.)"
    else
        for k in "${kernels_to_keep_final[@]}"; do echo "  - $k"; done
    fi


    echo -e "${RED}Kernels proposed for REMOVAL:${NC}"
    if [ ${#kernels_for_removal_final[@]} -eq 0 ]; then
        echo "  No old kernels to remove based on retention policy."
        log_message "INFO" "No old kernels to remove."
        pause_script
        return 0
    fi

    for k in "${kernels_for_removal_final[@]}"; do echo "  - $k"; done

    if confirm_action "Do you want to remove these old kernels?"; then
        for kernel_pkg_to_remove in "${kernels_for_removal_final[@]}"; do
            echo -e "${CYAN}Removing '$kernel_pkg_to_remove' using $PKG_MANAGER...${NC}"
            log_message "INFO" "Removing old kernel: $kernel_pkg_to_remove"
            eval "$KERNEL_REMOVE_CMD_PREFIX $kernel_pkg_to_remove"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Successfully removed '$kernel_pkg_to_remove'.${NC}"
                log_message "SUCCESS" "Removed kernel: $kernel_pkg_to_remove"
            else
                echo -e "${RED}ERROR: Failed to remove '$kernel_pkg_to_remove'.${NC}"
                log_message "ERROR" "Failed to remove kernel: $kernel_pkg_to_remove"
            fi
        done
        update_grub # Update GRUB after removing old kernels
    else
        log_message "INFO" "Old kernel removal cancelled."
    fi
    pause_script
}

prompt_reboot() {
    print_subsection "Reboot Required"
    echo -e "${YELLOW}A kernel update has been performed. For changes to take effect, a system reboot is REQUIRED.${NC}"
    if [ "$UNATTENDED_MODE" == "true" ]; then
        echo -e "${CYAN}UNATTENDED MODE: Initiating automatic system reboot in 10 seconds... Goodbye!${NC}"
        log_message "INFO" "UNATTENDED MODE: Automatic system reboot initiated after kernel update."
        sleep 10 # Give a brief window to cancel if needed
        sudo reboot
    else
        if confirm_action "Do you want to reboot now?"; then
            echo -e "${CYAN}Initiating system reboot... Goodbye!${NC}"
            log_message "INFO" "System reboot initiated after kernel update."
            sudo reboot
        else
            echo -e "${YELLOW}Reboot deferred. Please remember to reboot your system soon.${NC}"
            log_message "WARN" "Reboot deferred after kernel update."
        fi
    fi
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Kernel Update Automation (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}Detected Manager: ${PKG_MANAGER^}${NC}" # Capitalize first letter
    if [ "$UNATTENDED_MODE" == "true" ]; then
        echo -e "${RED}UNATTENDED MODE IS ACTIVE - USE WITH EXTREME CAUTION!${NC}"
    fi
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Check for New Kernel Updates${NC}"
    echo -e "${GREEN}2. Perform Kernel Update${NC}"
    echo -e "${GREEN}3. Update GRUB Configuration${NC}"
    echo -e "${GREEN}4. Manage Old Kernels (Remove older versions)${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    # Ensure log directory and GRUB backup directory exist
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_message "INFO" "Kernel updater script started. UNATTENDED_MODE is set to: $UNATTENDED_MODE."
    check_root # This script *requires* root for full functionality.
    detect_package_manager

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) check_for_kernel_updates ;;
            2) perform_kernel_update; [ $? -eq 0 ] && prompt_reboot ;; # Prompt reboot only if update was successful
            3) update_grub ;;
            4) manage_old_kernels ;;
            0)
                echo -e "${CYAN}Exiting Kernel Update Automation. Goodbye!${NC}"
                log_message "INFO" "Kernel updater script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 4.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
