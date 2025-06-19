#!/bin/bash

# user-expiry-check.sh - Checks Account Expiration Dates
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script checks the expiration dates of local user accounts.
#              It can list all users with their expiry status, identify accounts
#              nearing or already past expiration, and provide an option to
#              modify or extend user account expiry dates.

# --- Configuration ---
LOG_FILE="/var/log/user-expiry-check.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Number of days before expiration to consider an account "nearing expiration"
NEARING_EXPIRY_DAYS=30

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="user-expiry-monitor@yourdomain.com" # Sender email for alerts

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
        echo -e "${RED}ERROR: This script must be run as root to check and modify user account expiration dates.${NC}"
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
    echo -n "${YELLOW}$prompt (yes/no): ${NC}"
    read -r response
    if [[ "$response" =~ ^[yY][eE][sS]$ ]]; then
        return 0 # True
    else
        echo -e "${YELLOW}Action cancelled.${NC}"
        return 1 # False
    fi
}

get_local_users() {
    # Get all regular users (UID >= 1000, usually)
    # Exclude users with nologin shell
    getent passwd | awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ {print $1}' | sort
}

get_account_expiry_date() {
    local username="$1"
    if ! check_command "chage"; then
        echo -e "${RED}ERROR: 'chage' command not found. Cannot check user expiry.${NC}"
        log_message "ERROR" "'chage' command not found."
        return 1
    fi
    sudo chage -l "$username" 2>/dev/null | grep "Account expires" | awk -F': ' '{print $2}'
}

# --- Core Expiry Check Functions ---

list_users_with_expiry() {
    print_subsection "User Accounts with Expiration Status"
    echo -e "${CYAN}Username              Account Expiry Date   Status${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    local users=$(get_local_users)
    if [ -z "$users" ]; then
        echo -e "${YELLOW}No local user accounts found to check.${NC}"
        log_message "INFO" "No local user accounts found."
        pause_script
        return 1
    fi

    local current_date_epoch=$(date +%s)
    local expired_count=0
    local nearing_count=0

    for user in $users; do
        local expiry_date_str=$(get_account_expiry_date "$user")
        local status_msg=""
        local color_code=""

        if [ "$expiry_date_str" == "never" ]; then
            status_msg="Never Expires"
            color_code="${GREEN}"
        else
            local expiry_date_epoch=$(date -d "$expiry_date_str" +%s 2>/dev/null)
            if [ $? -ne 0 ]; then
                status_msg="Invalid Date"
                color_code="${RED}"
                log_message "WARN" "Invalid expiry date for user $user: $expiry_date_str"
            else
                local days_left=$(( (expiry_date_epoch - current_date_epoch) / (60*60*24) ))

                if (( days_left < 0 )); then
                    status_msg="EXPIRED"
                    color_code="${RED}"
                    expired_count=$((expired_count + 1))
                elif (( days_left <= NEARING_EXPIRY_DAYS )); then
                    status_msg="Expires in $days_left days"
                    color_code="${YELLOW}"
                    nearing_count=$((nearing_count + 1))
                else
                    status_msg="Active"
                    color_code="${NC}" # No special color for far future
                fi
            fi
        fi
        printf "%-20s %-22s ${color_code}%s${NC}\n" "$user" "$expiry_date_str" "$status_msg"
    done
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed user expiry status. Expired: $expired_count, Nearing Expiry: $nearing_count."
    if (( expired_count > 0 )); then
        send_email_alert "User Account Alert: Expired Accounts" "The following user accounts on $(hostname) are expired: $(check_expired_accounts_internal | tr '\n' ', '). Please investigate."
    fi
    if (( nearing_count > 0 )); then
        send_email_alert "User Account Alert: Accounts Nearing Expiration" "The following user accounts on $(hostname) are nearing expiration within $NEARING_EXPIRY_DAYS days: $(check_nearing_expiration_internal | tr '\n' ', '). Please investigate."
    fi

    pause_script
}

check_expired_accounts_internal() {
    local users=$(get_local_users)
    local current_date_epoch=$(date +%s)
    local expired_users=""
    for user in $users; do
        local expiry_date_str=$(get_account_expiry_date "$user")
        if [ "$expiry_date_str" != "never" ]; then
            local expiry_date_epoch=$(date -d "$expiry_date_str" +%s 2>/dev/null)
            if [ $? -eq 0 ]; then
                local days_left=$(( (expiry_date_epoch - current_date_epoch) / (60*60*24) ))
                if (( days_left < 0 )); then
                    expired_users+="$user "
                fi
            fi
        fi
    done
    echo "$expired_users"
}

check_expired_accounts() {
    print_subsection "Expired User Accounts"
    local expired_users=$(check_expired_accounts_internal)
    if [ -z "$expired_users" ]; then
        echo -e "${GREEN}No expired user accounts found.${NC}"
        log_message "INFO" "No expired user accounts found."
    else
        echo -e "${RED}The following user accounts are EXPIRED:${NC}"
        for user in $expired_users; do
            echo -e "${RED}- $user (Account expired on: $(get_account_expiry_date "$user"))${NC}"
        done
        log_message "ALERT" "Expired user accounts found: $expired_users"
    fi
    pause_script
}

check_nearing_expiration_internal() {
    local users=$(get_local_users)
    local current_date_epoch=$(date +%s)
    local nearing_users=""
    for user in $users; do
        local expiry_date_str=$(get_account_expiry_date "$user")
        if [ "$expiry_date_str" != "never" ]; then
            local expiry_date_epoch=$(date -d "$expiry_date_str" +%s 2>/dev/null)
            if [ $? -eq 0 ]; then
                local days_left=$(( (expiry_date_epoch - current_date_epoch) / (60*60*24) ))
                if (( days_left >= 0 && days_left <= NEARING_EXPIRY_DAYS )); then
                    nearing_users+="$user "
                fi
            fi
        fi
    done
    echo "$nearing_users"
}

check_nearing_expiration() {
    print_subsection "User Accounts Nearing Expiration (within $NEARING_EXPIRY_DAYS days)"
    local nearing_users=$(check_nearing_expiration_internal)
    if [ -z "$nearing_users" ]; then
        echo -e "${GREEN}No user accounts nearing expiration found.${NC}"
        log_message "INFO" "No user accounts nearing expiration found."
    else
        echo -e "${YELLOW}The following user accounts are nearing expiration:${NC}"
        for user in $nearing_users; do
            local expiry_date_str=$(get_account_expiry_date "$user")
            local expiry_date_epoch=$(date -d "$expiry_date_str" +%s)
            local days_left=$(( (expiry_date_epoch - $(date +%s)) / (60*60*24) ))
            echo -e "${YELLOW}- $user (Expires on: $expiry_date_str, in $days_left days)${NC}"
        done
        log_message "ALERT" "User accounts nearing expiration: $nearing_users"
    fi
    pause_script
}

modify_user_expiry() {
    print_subsection "Modify User Account Expiration"
    local username=$(read_user_input "Enter username to modify expiry for" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_message "ERROR" "Modify user expiry failed: Username empty."
        pause_script
        return 1
    fi

    if ! id "$username" &>/dev/null; then
        echo -e "${RED}ERROR: User '$username' does not exist.${NC}"
        log_message "ERROR" "Modify user expiry failed: User '$username' does not exist."
        pause_script
        return 1
    fi

    local current_expiry=$(get_account_expiry_date "$username")
    echo -e "${CYAN}Current account expiry for '$username': $current_expiry${NC}"

    echo -e "${YELLOW}Enter new expiry date (YYYY-MM-DD), 'never', or 'clear' to remove expiry.${NC}"
    local new_expiry_input=$(read_user_input "New expiry date/option" "")

    if [ -z "$new_expiry_input" ]; then
        echo -e "${YELLOW}No expiry date entered. Operation cancelled.${NC}"
        log_message "INFO" "Modify user expiry cancelled: no input."
        pause_script
        return 0
    fi

    local chage_option=""
    local chage_value=""
    local action_desc=""

    case "$new_expiry_input" in
        "never")
            chage_option="-E -1" # -1 means never expire
            chage_value="" # Not needed for -E -1
            action_desc="set to never expire"
            ;;
        "clear")
            chage_option="-E" # -E with no date clears expiry
            chage_value=""
            action_desc="remove expiry"
            ;;
        *) # Assuming YYYY-MM-DD format
            # Validate date format (basic check)
            if ! [[ "$new_expiry_input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                echo -e "${RED}ERROR: Invalid date format. Use YYYY-MM-DD, 'never', or 'clear'.${NC}"
                log_message "ERROR" "Invalid date format for expiry: $new_expiry_input."
                pause_script
                return 1
            fi
            # Test if date is valid
            date -d "$new_expiry_input" +%s >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}ERROR: Invalid date entered: '$new_expiry_input'.${NC}"
                log_message "ERROR" "Invalid date for expiry: $new_expiry_input (invalid date)."
                pause_script
                return 1
            fi
            chage_option="-E"
            chage_value="$new_expiry_input"
            action_desc="set to $new_expiry_input"
            ;;
    esac

    if confirm_action "Are you sure you want to $action_desc for user '$username'?"; then
        sudo chage $chage_option "$chage_value" "$username"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}User '$username' account expiry successfully $action_desc.${NC}"
            log_message "SUCCESS" "User '$username' account expiry $action_desc."
        else
            echo -e "${RED}ERROR: Failed to $action_desc for user '$username'.${NC}"
            log_message "ERROR" "Failed to $action_desc for user '$username'."
        fi
    fi
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> User Account Expiration Check (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. List All Users with Expiry Status${NC}"
    echo -e "${GREEN}2. Check for Expired Accounts${NC}"
    echo -e "${GREEN}3. Check for Accounts Nearing Expiration (within ${NEARING_EXPIRY_DAYS} days)${NC}"
    echo -e "${GREEN}4. Modify User Account Expiration Date${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_message "INFO" "User expiry check script started."
    check_root # This script *requires* root.

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) list_users_with_expiry ;;
            2) check_expired_accounts ;;
            3) check_nearing_expiration ;;
            4) modify_user_expiry ;;
            0)
                echo -e "${CYAN}Exiting User Account Expiration Check. Goodbye!${NC}"
                log_message "INFO" "User expiry check script exited."
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
