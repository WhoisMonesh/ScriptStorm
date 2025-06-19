#!/bin/bash
# set-timezone.sh - Configures system timezone
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script allows interactive configuration of the system timezone
#              using timedatectl. It lists available timezones and sets the chosen one.

# --- Configuration ---
LOG_FILE="/var/log/set-timezone.log" # Log file for script actions and errors
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
        echo -e "${RED}Please run with 'sudo ./set-timezone.sh'.${NC}"
        log_message "ERROR" "Script not run as root."
        exit 1
    fi
    log_message "INFO" "Script is running as root."
}

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

# --- Timezone Configuration Functions ---
check_timedatectl() {
    if ! check_command "timedatectl"; then
        echo -e "${RED}ERROR: 'timedatectl' command not found.${NC}"
        echo -e "${RED}This script requires systemd's 'timedatectl' (available on most modern Linux distributions).${NC}"
        log_message "ERROR" "'timedatectl' command not found."
        return 1
    fi
    log_message "INFO" "'timedatectl' command found."
    return 0
}

display_current_timezone() {
    print_subsection "Current System Timezone"
    if ! check_timedatectl; then
        return 1
    fi

    local current_info=$(timedatectl)
    local current_zone=$(echo "$current_info" | grep "Time zone:" | awk '{print $3}')
    local rtc_time=$(echo "$current_info" | grep "RTC time:" | awk '{$1=$2=""; print $0}' | xargs)
    local system_clock_synced=$(echo "$current_info" | grep "System clock synchronized:" | awk '{print $4}')

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "  ${MAGENTA}Time zone:${NC} $(echo "$current_info" | grep "Time zone:")"
    echo -e "  ${MAGENTA}RTC time:${NC} $rtc_time"
    echo -e "  ${MAGENTA}System clock synchronized:${NC} $system_clock_synced"
    echo -e "${CYAN}-----------------------------------------------------${NC}"

    if [ -z "$current_zone" ]; then
        echo -e "${YELLOW}Could not determine current timezone. 'timedatectl' output might be unexpected.${NC}"
        log_message "WARN" "Could not determine current timezone from timedatectl output."
        return 1
    fi
    log_message "INFO" "Displayed current timezone: $current_zone."
}

list_available_timezones() {
    print_subsection "Available Timezones"
    if ! check_timedatectl; then
        return 1
    fi

    echo -e "${CYAN}Listing all available timezones. This may take a moment...${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    timedatectl list-timezones | nl | less -R # Use less for pagination
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Listed available timezones using 'timedatectl list-timezones'."
    pause_script
}

set_system_timezone() {
    print_subsection "Set System Timezone"
    if ! check_timedatectl; then
        return 1
    fi

    echo -e "${YELLOW}It is highly recommended to view the list of available timezones (Option 2) first.${NC}"
    local desired_timezone=$(read_user_input "Enter the desired timezone (e.g., 'America/New_York', 'Asia/Kolkata')")

    if [ -z "$desired_timezone" ]; then
        echo -e "${RED}Timezone cannot be empty. Aborting.${NC}"
        log_message "WARN" "Timezone input was empty. Aborted setting timezone."
        return 1
    fi

    echo -e "${CYAN}Setting timezone to: ${desired_timezone}${NC}"
    log_message "INFO" "Attempting to set timezone to '$desired_timezone'."

    sudo timedatectl set-timezone "$desired_timezone"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Timezone set successfully!${NC}"
        log_message "SUCCESS" "Timezone successfully set to '$desired_timezone'."
        display_current_timezone # Show new current timezone
    else
        echo -e "${RED}ERROR: Failed to set timezone to '${desired_timezone}'.${NC}"
        echo -e "${RED}Please ensure the timezone name is correct and check system logs.${NC}"
        log_message "ERROR" "Failed to set timezone to '$desired_timezone'."
        return 1
    fi
    return 0
}

read_user_input() {
    local prompt="$1"
    local input=""
    echo -n "$prompt: "
    read -r input
    echo "$input"
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Timezone Configuration (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Display Current Timezone${NC}"
    echo -e "${GREEN}2. List Available Timezones${NC}"
    echo -e "${GREEN}3. Set System Timezone${NC}"
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

    log_message "INFO" "Timezone configuration script started."

    # Pre-check essential command
    if ! check_timedatectl; then
        log_message "ERROR" "'timedatectl' not found. Exiting."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_current_timezone; pause_script ;;
            2) list_available_timezones ;;
            3) set_system_timezone; pause_script ;;
            0)
                echo -e "${CYAN}Exiting System Timezone Configuration. Goodbye!${NC}"
                log_message "INFO" "Timezone configuration script exited."
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
