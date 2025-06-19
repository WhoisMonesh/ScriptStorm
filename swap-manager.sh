#!/bin/bash
# swap-manager.sh - Manages swap space
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides utilities to manage system swap space.
#              It can display current swap usage, create and remove swap files,
#              adjust swappiness, and enable/disable swap.

# --- Configuration ---
LOG_FILE="/var/log/swap-manager.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

DEFAULT_SWAP_FILE_PATH="/swapfile" # Default path for new swap files
DEFAULT_SWAP_FILE_SIZE="2G"        # Default size for new swap files (e.g., 1G, 2G, 512M)

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
        echo -e "${RED}Please run with 'sudo ./swap-manager.sh'.${NC}"
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

# --- Swap Management Functions ---
display_swap_status() {
    print_subsection "Current Swap Status"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${MAGENTA}Free (Memory + Swap):${NC}"
    free -h
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${MAGENTA}Swap Summary (swapon --show):${NC}"
    if check_command "swapon"; then
        if ! swapon --show &>/dev/null; then
            echo -e "${YELLOW}No active swap devices found.${NC}"
            log_message "INFO" "No active swap devices."
        else
            swapon --show
            log_message "INFO" "Displayed active swap devices."
        fi
    else
        echo -e "${RED}ERROR: 'swapon' command not found.${NC}"
        log_message "ERROR" "'swapon' command not found."
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${MAGENTA}Current Swappiness Value:${NC}"
    local swappiness=$(sysctl vm.swappiness | awk '{print $3}')
    if [ -n "$swappiness" ]; then
        echo -e "vm.swappiness = ${swappiness}"
        log_message "INFO" "Current swappiness: $swappiness."
    else
        echo -e "${YELLOW}Could not determine current swappiness.${NC}"
        log_message "WARN" "Could not determine swappiness."
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Displayed current swap status."
}

create_swap_file() {
    print_subsection "Create New Swap File"
    local swap_file_path=$(read_user_input "Enter full path for new swap file" "$DEFAULT_SWAP_FILE_PATH")
    local swap_file_size=$(read_user_input "Enter desired swap file size (e.g., 512M, 1G, 2G)" "$DEFAULT_SWAP_FILE_SIZE")

    if [ -z "$swap_file_path" ] || [ -z "$swap_file_size" ]; then
        echo -e "${RED}ERROR: Swap file path or size cannot be empty. Aborting.${NC}"
        log_message "ERROR" "Swap file path or size empty during creation attempt."
        return 1
    fi

    if [ -f "$swap_file_path" ]; then
        echo -e "${YELLOW}WARNING: Swap file '$swap_file_path' already exists.${NC}"
        read -r -p "Overwrite it? (y/N): " confirm_overwrite
        if [[ ! "$confirm_overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Aborting swap file creation.${NC}"
            log_message "INFO" "Aborted swap file creation (user chose not to overwrite)."
            return 1
        fi
        log_message "WARN" "Overwriting existing swap file '$swap_file_path'."
        sudo swapoff "$swap_file_path" &>/dev/null
        sudo rm -f "$swap_file_path"
    fi

    echo -e "${CYAN}Creating swap file '${swap_file_path}' of size ${swap_file_size}...${NC}"
    log_message "INFO" "Creating swap file '$swap_file_path' of size '$swap_file_size'."

    # Determine command based on size unit
    local count_multiplier=1
    local bs_value="M" # Default block size to Megabytes
    local num_blocks

    if [[ "$swap_file_size" =~ ([0-9]+)([GgMm]) ]]; then
        num_blocks=${BASH_REMATCH[1]}
        size_unit=${BASH_REMATCH[2]}
        case "$size_unit" in
            [Gg]) bs_value="G";;
            [Mm]) bs_value="M";;
        esac
    else
        echo -e "${RED}ERROR: Invalid size format. Use '512M', '1G', etc.${NC}"
        log_message "ERROR" "Invalid swap file size format: '$swap_file_size'."
        return 1
    fi

    sudo dd if=/dev/zero of="$swap_file_path" bs=1"$bs_value" count="$num_blocks" status=none
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to create swap file with 'dd'. Check disk space/permissions.${NC}"
        log_message "ERROR" "Failed to create swap file with 'dd'."
        return 1
    fi

    echo -e "${CYAN}Setting correct permissions for swap file...${NC}"
    sudo chmod 600 "$swap_file_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to set permissions for swap file.${NC}"
        log_message "ERROR" "Failed to set permissions for swap file '$swap_file_path'."
        return 1
    fi

    echo -e "${CYAN}Setting up Linux swap area...${NC}"
    sudo mkswap "$swap_file_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to initialize swap area with 'mkswap'.${NC}"
        log_message "ERROR" "Failed to initialize swap area on '$swap_file_path'."
        return 1
    fi

    echo -e "${CYAN}Activating swap file...${NC}"
    sudo swapon "$swap_file_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to activate swap file with 'swapon'.${NC}"
        log_message "ERROR" "Failed to activate swap file '$swap_file_path'."
        return 1
    fi

    echo -e "${GREEN}Swap file created and activated successfully!${NC}"
    log_message "SUCCESS" "Swap file '$swap_file_path' created and activated."

    read -r -p "Do you want to add this swap file to /etc/fstab for permanent activation on boot? (Y/n): " add_to_fstab
    if [[ ! "$add_to_fstab" =~ ^[Nn]$ ]]; then
        if ! grep -q "$swap_file_path" /etc/fstab; then
            echo "$swap_file_path none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Swap file added to /etc/fstab.${NC}"
                log_message "SUCCESS" "Swap file '$swap_file_path' added to /etc/fstab."
            else
                echo -e "${RED}ERROR: Failed to add swap file to /etc/fstab. Add manually if needed.${NC}"
                log_message "ERROR" "Failed to add swap file to /etc/fstab."
            fi
        else
            echo -e "${YELLOW}Swap file '$swap_file_path' already exists in /etc/fstab.${NC}"
            log_message "INFO" "Swap file '$swap_file_path' already in /etc/fstab."
        fi
    else
        echo -e "${CYAN}Skipping /etc/fstab update. Remember to activate manually on reboot or add later.${NC}"
        log_message "INFO" "Skipped adding swap file to /etc/fstab (user choice)."
    fi
    display_swap_status # Show updated swap status
    return 0
}

remove_swap_file() {
    print_subsection "Remove Swap File"
    local active_swaps=$(swapon --show | grep -v NAME | awk '{print $1}')
    if [ -z "$active_swaps" ]; then
        echo -e "${YELLOW}No active swap devices or files found to remove.${NC}"
        log_message "INFO" "No active swap devices to remove."
        return 0
    fi

    echo -e "${MAGENTA}Active Swap Devices:${NC}"
    echo -e "$active_swaps"
    echo -e "${CYAN}-----------------------------------------------------${NC}"

    local swap_to_remove=$(read_user_input "Enter full path of swap file to remove (e.g., /swapfile)")

    if [ -z "$swap_to_remove" ]; then
        echo -e "${RED}ERROR: Swap file path cannot be empty. Aborting.${NC}"
        log_message "ERROR" "Swap file path empty during removal attempt."
        return 1
    fi

    if ! echo "$active_swaps" | grep -q "$swap_to_remove"; then
        echo -e "${YELLOW}WARNING: '$swap_to_remove' is not an active swap device/file.${NC}"
        read -r -p "Attempt to remove it anyway (from fstab and delete file)? (y/N): " confirm_force_remove
        if [[ ! "$confirm_force_remove" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Aborting swap file removal.${NC}"
            log_message "INFO" "Aborted swap file removal (user opted not to force)."
            return 1
        fi
    fi

    echo -e "${CYAN}Deactivating swap file '${swap_to_remove}'...${NC}"
    log_message "INFO" "Deactivating swap file '$swap_to_remove'."
    sudo swapoff "$swap_to_remove"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to deactivate swap file '${swap_to_remove}'. It might be in use.${NC}"
        log_message "ERROR" "Failed to deactivate swap file '$swap_to_remove'."
        return 1
    fi

    echo -e "${CYAN}Removing entry from /etc/fstab (if present)...${NC}"
    # Use sed to remove the line, -i for in-place edit, -r for extended regex
    sudo sed -i -r "\#^${swap_to_remove}#d" /etc/fstab
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Entry for '$swap_to_remove' removed from /etc/fstab.${NC}"
        log_message "SUCCESS" "Entry for '$swap_to_remove' removed from /etc/fstab."
    else
        echo -e "${YELLOW}Warning: Could not remove entry for '$swap_to_remove' from /etc/fstab. Check manually.${NC}"
        log_message "WARN" "Failed to remove entry for '$swap_to_remove' from /etc/fstab."
    fi

    echo -e "${CYAN}Deleting swap file '${swap_to_remove}'...${NC}"
    sudo rm -f "$swap_to_remove"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Swap file '${swap_to_remove}' deleted successfully!${NC}"
        log_message "SUCCESS" "Swap file '$swap_to_remove' deleted."
    else
        echo -e "${RED}ERROR: Failed to delete swap file '${swap_to_remove}'. Check permissions.${NC}"
        log_message "ERROR" "Failed to delete swap file '$swap_to_remove'."
        return 1
    fi
    display_swap_status # Show updated swap status
    return 0
}

adjust_swappiness() {
    print_subsection "Adjust Swappiness Value"
    local current_swappiness=$(sysctl vm.swappiness | awk '{print $3}')
    echo -e "${MAGENTA}Current vm.swappiness: ${current_swappiness}${NC}"
    echo -e "${CYAN}Swappiness values range from 0 to 100.${NC}"
    echo -e "  - ${GREEN}0:${NC} Kernel will avoid swapping process data to disk for as long as possible."
    echo -e "  - ${YELLOW}60 (default):${NC} Balanced approach."
    echo -e "  - ${RED}100:${NC} Kernel will aggressively swap process data to disk."
    echo -e "${YELLOW}Consider lowering swappiness (e.g., 10-20) for desktop systems with ample RAM.${NC}"
    echo -e "${YELLOW}High swappiness might be useful for servers handling many idle processes.${NC}"

    local new_swappiness=$(read_user_input "Enter new swappiness value (0-100)" "$current_swappiness")

    if ! [[ "$new_swappiness" =~ ^[0-9]+$ ]] || [ "$new_swappiness" -lt 0 ] || [ "$new_swappiness" -gt 100 ]; then
        echo -e "${RED}ERROR: Invalid swappiness value. Please enter a number between 0 and 100.${NC}"
        log_message "ERROR" "Invalid swappiness value entered: '$new_swappiness'."
        return 1
    fi

    echo -e "${CYAN}Setting vm.swappiness to ${new_swappiness} (temporary)...${NC}"
    log_message "INFO" "Setting vm.swappiness to '$new_swappiness' (temporary)."
    sudo sysctl vm.swappiness="$new_swappiness"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}vm.swappiness updated successfully for current session!${NC}"
        log_message "SUCCESS" "vm.swappiness set to '$new_swappiness' for current session."
    else
        echo -e "${RED}ERROR: Failed to set vm.swappiness. Check permissions.${NC}"
        log_message "ERROR" "Failed to set vm.swappiness."
        return 1
    fi

    read -r -p "Do you want to make this change permanent by adding it to /etc/sysctl.conf? (Y/n): " make_permanent
    if [[ ! "$make_permanent" =~ ^[Nn]$ ]]; then
        local sysctl_conf_entry="vm.swappiness = $new_swappiness"
        if grep -q "vm.swappiness" /etc/sysctl.conf; then
            echo -e "${CYAN}Updating existing vm.swappiness entry in /etc/sysctl.conf...${NC}"
            sudo sed -i "/^vm.swappiness/c\\$sysctl_conf_entry" /etc/sysctl.conf
            log_message "SUCCESS" "Updated vm.swappiness in /etc/sysctl.conf to '$new_swappiness'."
        else
            echo -e "${CYAN}Adding vm.swappiness entry to /etc/sysctl.conf...${NC}"
            echo "$sysctl_conf_entry" | sudo tee -a /etc/sysctl.conf >/dev/null
            log_message "SUCCESS" "Added vm.swappiness entry to /etc/sysctl.conf: '$sysctl_conf_entry'."
        fi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Change made permanent in /etc/sysctl.conf.${NC}"
            echo -e "${YELLOW}Apply changes now with 'sudo sysctl -p' or they will take effect after reboot.${NC}"
            log_message "INFO" "Instructed user to run 'sudo sysctl -p' for immediate effect."
        else
            echo -e "${RED}ERROR: Failed to make swappiness change permanent in /etc/sysctl.conf. Add manually if needed.${NC}"
            log_message "ERROR" "Failed to make swappiness change permanent."
        fi
    else
        echo -e "${CYAN}Skipping permanent change. Swappiness will reset on reboot.${NC}"
        log_message "INFO" "Skipped making swappiness change permanent (user choice)."
    fi
    display_swap_status # Show current swappiness
    return 0
}

toggle_all_swap() {
    print_subsection "Enable/Disable All Swap"
    local current_swap_count=$(swapon --show | grep -v NAME | wc -l)

    if [ "$current_swap_count" -gt 0 ]; then
        echo -e "${YELLOW}Currently active swap devices:${NC}"
        swapon --show
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        read -r -p "All active swap will be deactivated. Are you sure? (y/N): " confirm_deactivate
        if [[ ! "$confirm_deactivate" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Aborting swap deactivation.${NC}"
            log_message "INFO" "Aborted all swap deactivation."
            return 1
        fi
        echo -e "${CYAN}Deactivating all swap...${NC}"
        sudo swapoff -a
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}All swap deactivated successfully!${NC}"
            log_message "SUCCESS" "All swap deactivated."
        else
            echo -e "${RED}ERROR: Failed to deactivate all swap. Check for errors.${NC}"
            log_message "ERROR" "Failed to deactivate all swap."
            return 1
        fi
    else
        echo -e "${YELLOW}No active swap devices found. Activating all swap from /etc/fstab...${NC}"
        log_message "INFO" "No active swap. Attempting to activate from fstab."
        sudo swapon -a
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}All swap from /etc/fstab activated successfully!${NC}"
            log_message "SUCCESS" "All swap from /etc/fstab activated."
        else
            echo -e "${RED}ERROR: Failed to activate swap. Check /etc/fstab entries.${NC}"
            log_message "ERROR" "Failed to activate all swap from fstab."
            return 1
        fi
    fi
    display_swap_status # Show updated swap status
    return 0
}

explain_swap() {
    print_subsection "About Swap Space"
    echo -e "${CYAN}What is Swap Space?${NC}"
    echo "  - Swap space is a portion of a hard drive or SSD that is used as virtual"
    echo "    memory. When your system runs out of physical RAM, it moves less-used"
    echo "    pages of memory from RAM to swap space on disk."
    echo "  - It's a fallback mechanism to prevent out-of-memory errors and system crashes."
    echo ""
    echo -e "${CYAN}Why manage Swap?${NC}"
    echo "  - ${GREEN}Performance:${NC} Disk (even SSD) is much slower than RAM. Excessive"
    echo "    swapping ('thrashing') can drastically slow down your system."
    echo "  - ${YELLOW}Hibernation:${NC} If you intend to use hibernation, your swap space"
    echo "    should typically be at least as large as your RAM."
    echo "  - ${RED}Optimizing:${NC} Adjusting 'swappiness' can fine-tune how aggressively"
    echo "    the kernel uses swap. Lower values (e.g., 10-20) are often better for"
    echo "    desktops with ample RAM, while higher values (e.g., 60-100) might be"
    echo "    suitable for servers or systems with limited RAM to prevent OOM errors."
    echo ""
    echo -e "${CYAN}Swap File vs. Swap Partition:${NC}"
    echo "  - ${MAGENTA}Swap Partition:${NC} A dedicated partition on the disk. Generally"
    echo "    considered slightly faster but requires partitioning before OS install."
    echo "  - ${MAGENTA}Swap File:${NC} A regular file on an existing filesystem. More flexible"
    echo "    as it can be created/resized on the fly without repartitioning."
    echo "    This script focuses on managing swap files."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Swap explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Swap Space Manager (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Display Current Swap Status${NC}"
    echo -e "${GREEN}2. Create New Swap File${NC}"
    echo -e "${GREEN}3. Remove Existing Swap File${NC}"
    echo -e "${GREEN}4. Adjust Swappiness Value${NC}"
    echo -e "${GREEN}5. Enable/Disable All Swap${NC}"
    echo -e "${GREEN}6. About Swap Space${NC}"
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

    log_message "INFO" "Swap manager script started."

    # Pre-check essential command
    if ! check_command "swapon" || ! check_command "free" || ! check_command "sysctl"; then
        echo -e "${RED}ERROR: One or more required commands (swapon, free, sysctl) not found. Exiting.${NC}"
        log_message "ERROR" "Missing essential commands for swap management."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_swap_status; pause_script ;;
            2) create_swap_file; pause_script ;;
            3) remove_swap_file; pause_script ;;
            4) adjust_swappiness; pause_script ;;
            5) toggle_all_swap; pause_script ;;
            6) explain_swap; pause_script ;;
            0)
                echo -e "${CYAN}Exiting Swap Space Manager. Goodbye!${NC}"
                log_message "INFO" "Swap manager script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 6.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
