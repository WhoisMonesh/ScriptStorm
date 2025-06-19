#!/bin/bash
# grub-backup.sh - Backs up GRUB configuration
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script creates a backup of the GRUB bootloader configuration
#              files and directories. It's essential for disaster recovery in
#              case of GRUB corruption or misconfiguration.

# --- Configuration ---
BACKUP_DIR="/var/backups/grub" # Directory where backups will be stored
GRUB_CONF_DIR="/etc/default"    # Directory containing grub configuration files
GRUB_D_DIR="/etc/grub.d"        # Directory containing GRUB scripts
BOOT_GRUB_DIR="/boot/grub"      # Directory containing GRUB modules and stage files
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
        echo -e "${RED}Please run with 'sudo ./grub-backup.sh'.${NC}"
        log_message "ERROR" "Script not run as root."
        exit 1
    fi
    log_message "INFO" "Script is running as root."
}

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

# --- Backup Functions ---
check_grub_files() {
    print_subsection "Checking GRUB Configuration Files"
    local all_found=true

    if [ ! -d "$GRUB_CONF_DIR" ]; then
        echo -e "${RED}Error: GRUB configuration directory '$GRUB_CONF_DIR' not found.${NC}"
        log_message "ERROR" "GRUB_CONF_DIR '$GRUB_CONF_DIR' not found."
        all_found=false
    else
        echo -e "${GREEN}GRUB configuration directory '$GRUB_CONF_DIR' found.${NC}"
    fi

    if [ ! -d "$GRUB_D_DIR" ]; then
        echo -e "${RED}Error: GRUB scripts directory '$GRUB_D_DIR' not found.${NC}"
        log_message "ERROR" "GRUB_D_DIR '$GRUB_D_DIR' not found."
        all_found=false
    else
        echo -e "${GREEN}GRUB scripts directory '$GRUB_D_DIR' found.${NC}"
    fi

    if [ ! -d "$BOOT_GRUB_DIR" ]; then
        echo -e "${RED}Error: GRUB boot directory '$BOOT_GRUB_DIR' not found.${NC}"
        echo -e "${RED}This directory is crucial for GRUB operation. Is GRUB installed?${NC}"
        log_message "ERROR" "BOOT_GRUB_DIR '$BOOT_GRUB_DIR' not found. GRUB might not be installed correctly."
        all_found=false
    else
        echo -e "${GREEN}GRUB boot directory '$BOOT_GRUB_DIR' found.${NC}"
    fi

    if [ "$all_found" = false ]; then
        echo -e "${RED}Cannot proceed with GRUB backup. One or more critical GRUB paths are missing.${NC}"
        log_message "ERROR" "Missing critical GRUB paths. Aborting backup."
        return 1
    fi
    log_message "INFO" "All critical GRUB paths found."
    return 0
}

create_grub_backup() {
    print_subsection "Creating GRUB Configuration Backup"
    if ! check_grub_files; then
        return 1
    fi

    mkdir -p "$BACKUP_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create backup directory '$BACKUP_DIR'. Check permissions.${NC}"
        log_message "ERROR" "Could not create backup directory '$BACKUP_DIR'."
        return 1
    fi

    local backup_filename="grub_backup_$(date "$DATE_FORMAT").tar.gz"
    local full_backup_path="${BACKUP_DIR}/${backup_filename}"

    echo -e "${CYAN}Backing up GRUB configuration files to:${NC} ${full_backup_path}"
    log_message "INFO" "Starting GRUB backup to '$full_backup_path'."

    # Use tar to archive the relevant directories and files
    # The -C / ensures that the paths in the archive are absolute from root
    sudo tar -czvf "$full_backup_path" \
        -C / "${GRUB_CONF_DIR#/}/grub" \
        -C / "${GRUB_D_DIR#/}" \
        -C / "${BOOT_GRUB_DIR#/}" \
        --absolute-names \
        --ignore-failed-read \
        &>/dev/null # Suppress verbose output, only show errors

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}GRUB backup created successfully!${NC}"
        echo -e "${GREEN}Backup file: ${full_backup_path}${NC}"
        log_message "SUCCESS" "GRUB backup successful: '$full_backup_path'."
        echo -e "\n${YELLOW}NOTE: This backup includes configuration files and modules.${NC}"
        echo -e "${YELLOW}To restore GRUB fully, you might also need to reinstall GRUB to the MBR/GPT.${NC}"
        echo -e "${YELLOW}e.g., 'sudo grub-install /dev/sdX' and 'sudo update-grub'.${NC}"
    else
        echo -e "${RED}ERROR: GRUB backup failed! Check logs for details.${NC}"
        log_message "ERROR" "GRUB backup failed. Check tar command output."
        return 1
    fi
    return 0
}

list_grub_backups() {
    print_subsection "Existing GRUB Backups"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}Backup directory '$BACKUP_DIR' does not exist.${NC}"
        echo -e "${YELLOW}No GRUB backups found.${NC}"
        log_message "INFO" "Backup directory '$BACKUP_DIR' not found for listing."
        return 1
    fi

    local backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "grub_backup_*.tar.gz" | sort -r)
    if [ -z "$backups" ]; then
        echo -e "${YELLOW}No GRUB backup files found in '$BACKUP_DIR'.${NC}"
        log_message "INFO" "No GRUB backup files found in '$BACKUP_DIR'."
        return 1
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${MAGENTA}Available GRUB Backups:${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo "$backups" | while read -r backup_file; do
        echo "$(basename "$backup_file")"
    done
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Listed existing GRUB backups."
    return 0
}

explain_grub_backup() {
    print_subsection "About GRUB Backup"
    echo -e "${CYAN}What is GRUB?${NC}"
    echo "  - GRUB (Grand Unified Bootloader) is the default bootloader for most"
    echo "    Linux distributions. It's responsible for loading the operating system"
    echo "    kernel into memory after the system's firmware (BIOS/UEFI) hands off control."
    echo ""
    echo -e "${CYAN}Why backup GRUB?${NC}"
    echo "  - ${RED}Critical Component:${NC} A corrupted or misconfigured GRUB can render"
    echo "    your system unbootable, even if your operating system files are intact."
    echo "  - ${YELLOW}Common Scenarios for Corruption:${NC}"
    echo "    - Dual-booting issues (e.g., Windows overwriting GRUB)."
    echo "    - Incorrectly running 'update-grub' or 'grub-install'."
    echo "    - Disk issues."
    echo "  - A backup allows you to restore critical GRUB configuration files,"
    echo "    potentially avoiding a lengthy reinstallation or manual repair process."
    echo ""
    echo -e "${CYAN}What's included in this backup?${NC}"
    echo "  - ${GRUB_CONF_DIR}/grub: The main GRUB configuration file ('grub' or 'grub.conf')"
    echo "    which defines default settings (e.g., timeout, default kernel)."
    echo "  - ${GRUB_D_DIR}: Scripts that 'update-grub' uses to build 'grub.cfg' (e.g., 10_linux, 30_os-prober)."
    echo "  - ${BOOT_GRUB_DIR}: Contains compiled GRUB modules, fonts, themes, and the"
    echo "    generated 'grub.cfg' file which is the actual boot menu."
    echo ""
    echo -e "${CYAN}Important Note on Restoration:${NC}"
    echo "  - Restoring these files is only one part of a full GRUB repair."
    echo "  - You might also need to reinstall GRUB to the Master Boot Record (MBR)"
    echo "    or GUID Partition Table (GPT) using 'sudo grub-install /dev/sdX'"
    echo "    and then run 'sudo update-grub' to regenerate the boot menu."
    echo "  - This script only backs up files; it does not backup the MBR/GPT itself."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "GRUB backup explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> GRUB Configuration Backup (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Create New GRUB Backup${NC}"
    echo -e "${GREEN}2. List Existing GRUB Backups${NC}"
    echo -e "${GREEN}3. About GRUB Backup & Restoration Tips${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    check_root

    # Ensure log directory exists
    LOG_FILE="/var/log/grub-backup.log" # Define LOG_FILE here if not defined globally
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_message "INFO" "GRUB backup script started."

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) create_grub_backup; pause_script ;;
            2) list_grub_backups; pause_script ;;
            3) explain_grub_backup; pause_script ;;
            0)
                echo -e "${CYAN}Exiting GRUB Configuration Backup script. Goodbye!${NC}"
                log_message "INFO" "GRUB backup script exited."
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
