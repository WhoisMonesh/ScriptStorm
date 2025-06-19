#!/bin/bash

# bulk-user-create.sh - Creates Multiple User Accounts from a CSV file
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script reads user details from a specified CSV file and
#              creates multiple user accounts. It supports setting primary and
#              secondary groups, home directories, and generating initial passwords.

# --- Configuration ---
LOG_FILE="/var/log/bulk-user-create.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Default settings for new users
DEFAULT_SHELL="/bin/bash"       # Default login shell
DEFAULT_HOME_PREFIX="/home"     # Default home directory prefix (e.g., /home/username)
PASSWORD_LENGTH=12              # Length of randomly generated passwords
FORCE_PASSWORD_CHANGE="true"    # true/false: Force user to change password on first login

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="user-creation-script@yourdomain.com" # Sender email for alerts

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
        echo -e "${RED}ERROR: This script must be run as root to create user accounts.${NC}"
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

generate_random_password() {
    # Generate a random password using /dev/urandom and tr
    # Ensures a mix of alphanumeric and special characters
    tr -dc A-Za-z0-9_@#$%^&*()_+=- | head -c "$PASSWORD_LENGTH" </dev/urandom
}

# --- User Creation Logic ---

process_user_file() {
    print_subsection "Process User Data File"
    local user_file=$(read_user_input "Enter path to user data CSV file" "")

    if [ -z "$user_file" ]; then
        echo -e "${RED}ERROR: User data file path cannot be empty.${NC}"
        log_message "ERROR" "Bulk user creation failed: file path empty."
        pause_script
        return 1
    fi

    if [ ! -f "$user_file" ]; then
        echo -e "${RED}ERROR: User data file '$user_file' not found.${NC}"
        log_message "ERROR" "Bulk user creation failed: file '$user_file' not found."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Analyzing user data from '$user_file'...\n${NC}"
    echo -e "${CYAN}Expected CSV format (comma-separated):${NC}"
    echo -e "${CYAN}username,fullname,primary_group,secondary_groups (optional),shell (optional),home_directory (optional)${NC}"
    echo -e "${CYAN}Example: jdoe,John Doe,users,sudo;developers,/bin/bash,/home/jdoe${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    local total_users=0
    local created_users=0
    local failed_users=0
    local new_users_summary=""
    local user_details_output_file="/tmp/new_user_passwords_$(date +%Y%m%d%H%M%S).txt"

    echo -e "${MAGENTA}User Creation Summary with Passwords (Save this file securely!):${NC}" | tee "$user_details_output_file"
    echo "------------------------------------------------------------------" | tee -a "$user_details_output_file"

    # Read the CSV file line by line, skipping comments and empty lines
    while IFS=',' read -r username fullname primary_group secondary_groups custom_shell custom_home_dir; do
        # Trim whitespace from all variables
        username=$(echo "$username" | xargs)
        fullname=$(echo "$fullname" | xargs)
        primary_group=$(echo "$primary_group" | xargs)
        secondary_groups=$(echo "$secondary_groups" | xargs)
        custom_shell=$(echo "$custom_shell" | xargs)
        custom_home_dir=$(echo "$custom_home_dir" | xargs)

        # Skip empty lines or lines starting with #
        if [[ -z "$username" || "$username" =~ ^# ]]; then
            continue
        fi

        total_users=$((total_users + 1))
        echo -e "\n${CYAN}Processing user: $username...${NC}"
        log_message "INFO" "Processing user: $username."

        if id "$username" &>/dev/null; then
            echo -e "${YELLOW}WARNING: User '$username' already exists. Skipping.${NC}"
            log_message "WARN" "User '$username' already exists. Skipping."
            failed_users=$((failed_users + 1))
            continue
        fi

        # Determine shell and home directory
        local user_shell="${custom_shell:-$DEFAULT_SHELL}"
        local user_home_dir="${custom_home_dir:-${DEFAULT_HOME_PREFIX}/$username}"
        
        # Build useradd command
        local useradd_cmd="useradd -m" # -m to create home directory
        [ -n "$fullname" ] && useradd_cmd+=" -c \"$fullname\""
        [ -n "$primary_group" ] && useradd_cmd+=" -g \"$primary_group\"" # Set primary group
        [ -n "$user_home_dir" ] && useradd_cmd+=" -d \"$user_home_dir\""
        [ -n "$user_shell" ] && useradd_cmd+=" -s \"$user_shell\""

        # Execute useradd
        eval "$useradd_cmd" "$username"
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to create user '$username'. Check primary group or other parameters.${NC}"
            log_message "ERROR" "Failed to create user '$username'."
            failed_users=$((failed_users + 1))
            continue
        fi

        # Set password
        local generated_password=$(generate_random_password)
        echo "$username:$generated_password" | chpasswd
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to set password for '$username'. User created without password.${NC}"
            log_message "ERROR" "Failed to set password for '$username'."
            failed_users=$((failed_users + 1))
            # Continue to next steps, but mark as failed
        else
            echo -e "${GREEN}Password set for '$username'.${NC}"
            log_message "SUCCESS" "Password set for '$username'."
            
            if [ "$FORCE_PASSWORD_CHANGE" == "true" ]; then
                chage -d 0 "$username" # Force password change on first login
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}User '$username' will be forced to change password on first login.${NC}"
                    log_message "SUCCESS" "User '$username' forced password change on first login."
                else
                    echo -e "${YELLOW}WARNING: Failed to force password change for '$username'.${NC}"
                    log_message "WARN" "Failed to force password change for '$username'."
                fi
            fi

            # Add to secondary groups
            if [ -n "$secondary_groups" ]; then
                # secondary_groups might be comma or semicolon separated
                IFS=';,' read -ra groups_array <<< "$secondary_groups"
                for group in "${groups_array[@]}"; do
                    group=$(echo "$group" | xargs) # Trim whitespace from each group name
                    if [ -n "$group" ]; then
                        if ! getent group "$group" &>/dev/null; then
                            echo -e "${YELLOW}WARNING: Group '$group' does not exist. Creating it.${NC}"
                            sudo groupadd "$group"
                            if [ $? -ne 0 ]; then
                                echo -e "${RED}ERROR: Failed to create group '$group'. Skipping for user '$username'.${NC}"
                                log_message "ERROR" "Failed to create group '$group' for user '$username'."
                                continue
                            fi
                        fi
                        sudo usermod -aG "$group" "$username"
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}User '$username' added to secondary group '$group'.${NC}"
                            log_message "SUCCESS" "User '$username' added to secondary group '$group'."
                        else
                            echo -e "${RED}ERROR: Failed to add user '$username' to group '$group'.${NC}"
                            log_message "ERROR" "Failed to add user '$username' to group '$group'."
                        fi
                    fi
                done
            fi
            
            created_users=$((created_users + 1))
            new_users_summary+="User: $username, Password: $generated_password, Primary Group: $primary_group, Secondary Groups: $secondary_groups, Shell: $user_shell, Home: $user_home_dir"
            if [ "$FORCE_PASSWORD_CHANGE" == "true" ]; then
                new_users_summary+=", Force PWD Change: Yes"
            else
                new_users_summary+=", Force PWD Change: No"
            fi
            new_users_summary+="\n"

            echo "$username : $generated_password" | tee -a "$user_details_output_file"
        fi

    done < <(grep -vE '^\s*#|^\s*$' "$user_file") # Process file, ignoring comments and empty lines

    echo -e "${CYAN}\n-------------------------------------------------------------------${NC}"
    echo -e "${CYAN}Bulk User Creation Process Completed.${NC}"
    echo -e "${CYAN}Total users processed: $total_users${NC}"
    echo -e "${CYAN}Users created successfully: $created_users${NC}"
    echo -e "${CYAN}Users failed/skipped: $failed_users${NC}"
    echo -e "${MAGENTA}IMPORTANT: Review '$user_details_output_file' for newly created user credentials.${NC}"
    log_message "INFO" "Bulk user creation process finished. Total: $total_users, Created: $created_users, Failed: $failed_users."
    send_email_alert "Bulk User Creation Report" "Bulk user creation completed on $(hostname).\n\nTotal users processed: $total_users\nUsers created successfully: $created_users\nUsers failed/skipped: $failed_users\n\nGenerated password summary is in $user_details_output_file.\n\nSummary:\n$new_users_summary"
    
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Bulk User Account Creation (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Create Users from CSV File${NC}"
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

    log_message "INFO" "Bulk user creation script started."
    check_root # This script *requires* root.

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) process_user_file ;;
            0)
                echo -e "${CYAN}Exiting Bulk User Account Creation. Goodbye!${NC}"
                log_message "INFO" "Bulk user creation script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 0.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
