#!/bin/bash

# user-management.sh - User Account Management Tool
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 18, 2025
# Description: This script provides a menu-driven interface for common user account
#              management tasks, including adding, deleting, modifying, listing users,
#              and managing user groups. It emphasizes safety and error handling.

# --- Configuration ---
LOG_FILE="/var/log/user-management.log" # Log file for script actions and errors
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

log_action() {
    local type="$1" # INFO, SUCCESS, ERROR
    local message="$2"
    echo -e "$(date "$DATE_FORMAT") [${type}] ${message}" | tee -a "$LOG_FILE"
}

print_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> User Account Management Tool (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Create New User${NC}"
    echo -e "${GREEN}2. Delete User${NC}"
    echo -e "${GREEN}3. Modify User Properties${NC}"
    echo -e "${GREEN}4. List All Users${NC}"
    echo -e "${GREEN}5. Add User to Group(s)${NC}"
    echo -e "${GREEN}6. Remove User from Group${NC}"
    echo -e "${GREEN}7. Create New Group${NC}"
    echo -e "${GREEN}8. Delete Group${NC}"
    echo -e "${GREEN}9. List All Groups${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
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

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root.${NC}"
        log_action "ERROR" "Attempted to run script as non-root user."
        exit 1
    fi
}

user_exists() {
    id "$1" &>/dev/null
    return $?
}

group_exists() {
    getent group "$1" &>/dev/null
    return $?
}

# --- User Management Functions ---

create_user() {
    print_subsection "Create New User"
    local username
    local password
    local uid
    local gid
    local home_dir
    local shell
    local comment
    local create_home="yes"
    local default_shell="/bin/bash" # Common default shell
    local default_home_prefix="/home" # Common home directory prefix

    username=$(read_user_input "Enter username" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_action "ERROR" "Create user failed: Username empty."
        return 1
    fi

    if user_exists "$username"; then
        echo -e "${YELLOW}WARNING: User '$username' already exists.${NC}"
        log_action "INFO" "Create user attempted for existing user: $username."
        return 0
    fi

    password=$(read_user_input "Enter password for $username (leave empty for no password, or use 'passwd' later)" "")
    comment=$(read_user_input "Enter full name or comment (e.g., 'John Doe')" "")
    home_dir=$(read_user_input "Enter home directory (default: ${default_home_prefix}/$username)" "${default_home_prefix}/$username")
    shell=$(read_user_input "Enter login shell (default: ${default_shell})" "${default_shell}")

    echo -n "Create home directory? (yes/no, default: yes): "
    read -r create_home_choice
    if [[ "$create_home_choice" =~ ^[nN][oO]?$ ]]; then
        create_home="no"
    fi

    local useradd_cmd="useradd"
    [ -n "$comment" ] && useradd_cmd+=" -c \"$comment\""
    [ "$create_home" = "yes" ] && useradd_cmd+=" -m"
    [ -n "$home_dir" ] && useradd_cmd+=" -d \"$home_dir\""
    [ -n "$shell" ] && useradd_cmd+=" -s \"$shell\""

    eval "$useradd_cmd" "$username"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}User '$username' created successfully.${NC}"
        log_action "SUCCESS" "User '$username' created."
        if [ -n "$password" ]; then
            echo "$username:$password" | chpasswd
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Password set for '$username'.${NC}"
                log_action "SUCCESS" "Password set for user '$username'."
            else
                echo -e "${RED}ERROR: Failed to set password for '$username'.${NC}"
                log_action "ERROR" "Failed to set password for user '$username'."
            fi
        else
            echo -e "${YELLOW}WARNING: No password set for '$username'. User may not be able to login directly.${NC}"
            log_action "WARN" "No password set for user '$username'."
        fi
    else
        echo -e "${RED}ERROR: Failed to create user '$username'.${NC}"
        log_action "ERROR" "Failed to create user '$username'."
    fi

    echo -n "Press Enter to continue..." && read -r
}

delete_user() {
    print_subsection "Delete User"
    local username=$(read_user_input "Enter username to delete" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_action "ERROR" "Delete user failed: Username empty."
        return 1
    fi

    if ! user_exists "$username"; then
        echo -e "${YELLOW}WARNING: User '$username' does not exist.${NC}"
        log_action "INFO" "Delete user attempted for non-existent user: $username."
        return 0
    fi

    echo -n "Are you sure you want to delete user '$username' and their home directory? (yes/no): "
    local confirm
    read -r confirm
    if [[ "$confirm" =~ ^[yY][eE][sS]$ ]]; then
        userdel -r "$username"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}User '$username' and their home directory deleted successfully.${NC}"
            log_action "SUCCESS" "User '$username' deleted with home directory."
        else
            echo -e "${RED}ERROR: Failed to delete user '$username'.${NC}"
            log_action "ERROR" "Failed to delete user '$username'."
        fi
    else
        echo -e "${YELLOW}User deletion cancelled.${NC}"
        log_action "INFO" "User deletion cancelled for '$username'."
    fi
    echo -n "Press Enter to continue..." && read -r
}

modify_user() {
    print_subsection "Modify User Properties"
    local username=$(read_user_input "Enter username to modify" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_action "ERROR" "Modify user failed: Username empty."
        return 1
    fi

    if ! user_exists "$username"; then
        echo -e "${RED}ERROR: User '$username' does not exist.${NC}"
        log_action "ERROR" "Modify user attempted for non-existent user: $username."
        return 1
    fi

    echo -e "\n${CYAN}Current properties for $username:${NC}"
    finger "$username" 2>/dev/null || echo "Could not get finger info. Using id command."
    id "$username"

    echo -e "\n${CYAN}Enter new values (leave blank to keep current value):${NC}"
    local new_comment=$(read_user_input "New Full Name/Comment" "")
    local new_home_dir=$(read_user_input "New Home Directory" "")
    local new_shell=$(read_user_input "New Login Shell" "")
    local new_password_set=$(read_user_input "Set New Password? (yes/no, default: no)" "no")

    local usermod_cmd="usermod"
    local changed="no"

    [ -n "$new_comment" ] && usermod_cmd+=" -c \"$new_comment\"" && changed="yes"
    [ -n "$new_home_dir" ] && usermod_cmd+=" -d \"$new_home_dir\"" && changed="yes"
    [ -n "$new_shell" ] && usermod_cmd+=" -s \"$new_shell\"" && changed="yes"

    if [ "$changed" = "yes" ]; then
        eval "$usermod_cmd" "$username"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}User '$username' properties updated successfully.${NC}"
            log_action "SUCCESS" "User '$username' properties modified."
        else
            echo -e "${RED}ERROR: Failed to modify user '$username' properties.${NC}"
            log_action "ERROR" "Failed to modify user '$username' properties."
            echo -n "Press Enter to continue..." && read -r
            return 1
        fi
    else
        echo -e "${YELLOW}No user properties to modify (except password).${NC}"
    fi

    if [[ "$new_password_set" =~ ^[yY][eE][sS]$ ]]; then
        local new_pass=$(read_user_input "Enter NEW password for $username" "")
        if [ -n "$new_pass" ]; then
            echo "$username:$new_pass" | chpasswd
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Password updated for '$username'.${NC}"
                log_action "SUCCESS" "Password updated for user '$username'."
            else
                echo -e "${RED}ERROR: Failed to update password for '$username'.${NC}"
                log_action "ERROR" "Failed to update password for user '$username'."
            fi
        else
            echo -e "${YELLOW}WARNING: New password not set (input was empty).${NC}"
            log_action "WARN" "Password update attempted for user '$username' but password was empty."
        fi
    fi

    echo -n "Press Enter to continue..." && read -r
}

list_users() {
    print_subsection "List All Users"
    echo -e "${CYAN}Username              UID    GID    Home Directory      Shell${NC}"
    echo -e "${CYAN}-----------------------------------------------------------------${NC}"
    getent passwd | awk -F: '{printf "%-20s %-6s %-6s %-20s %s\n", $1, $3, $4, $6, $7}'
    echo -e "${CYAN}-----------------------------------------------------------------${NC}"
    log_action "INFO" "Listed all users."
    echo -n "Press Enter to continue..." && read -r
}

add_user_to_group() {
    print_subsection "Add User to Group(s)"
    local username=$(read_user_input "Enter username to add to group(s)" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_action "ERROR" "Add user to group failed: Username empty."
        return 1
    fi

    if ! user_exists "$username"; then
        echo -e "${RED}ERROR: User '$username' does not exist.${NC}"
        log_action "ERROR" "Add user to group attempted for non-existent user: $username."
        return 1
    fi

    echo "Current groups for $username: $(id -Gn "$username" 2>/dev/null)"

    local groups_to_add=$(read_user_input "Enter group names to add (space-separated)" "")
    if [ -z "$groups_to_add" ]; then
        echo -e "${YELLOW}No groups specified. Operation cancelled.${NC}"
        log_action "INFO" "Add user '$username' to group cancelled (no groups specified)."
        echo -n "Press Enter to continue..." && read -r
        return 0
    fi

    for group_name in $groups_to_add; do
        if group_exists "$group_name"; then
            usermod -aG "$group_name" "$username"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}User '$username' added to group '$group_name' successfully.${NC}"
                log_action "SUCCESS" "User '$username' added to group '$group_name'."
            else
                echo -e "${RED}ERROR: Failed to add user '$username' to group '$group_name'.${NC}"
                log_action "ERROR" "Failed to add user '$username' to group '$group_name'."
            fi
        else
            echo -e "${YELLOW}WARNING: Group '$group_name' does not exist. Skipping.${NC}"
            log_action "WARN" "Attempted to add user '$username' to non-existent group '$group_name'."
        fi
    done
    echo -n "Press Enter to continue..." && read -r
}

remove_user_from_group() {
    print_subsection "Remove User from Group"
    local username=$(read_user_input "Enter username to remove from group" "")
    if [ -z "$username" ]; then
        echo -e "${RED}ERROR: Username cannot be empty.${NC}"
        log_action "ERROR" "Remove user from group failed: Username empty."
        return 1
    fi

    if ! user_exists "$username"; then
        echo -e "${RED}ERROR: User '$username' does not exist.${NC}"
        log_action "ERROR" "Remove user from group attempted for non-existent user: $username."
        return 1
    fi

    echo "Current groups for $username: $(id -Gn "$username" 2>/dev/null)"

    local group_name=$(read_user_input "Enter group name to remove user '$username' from" "")
    if [ -z "$group_name" ]; then
        echo -e "${RED}ERROR: Group name cannot be empty.${NC}"
        log_action "ERROR" "Remove user from group failed: Group name empty."
        return 1
    fi

    if ! group_exists "$group_name"; then
        echo -e "${YELLOW}WARNING: Group '$group_name' does not exist. No action taken.${NC}"
        log_action "WARN" "Attempted to remove user '$username' from non-existent group '$group_name'."
        echo -n "Press Enter to continue..." && read -r
        return 0
    fi

    gpasswd -d "$username" "$group_name"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}User '$username' removed from group '$group_name' successfully.${NC}"
        log_action "SUCCESS" "User '$username' removed from group '$group_name'."
    else
        echo -e "${RED}ERROR: Failed to remove user '$username' from group '$group_name'. This might mean the user was not a member, or it's their primary group.${NC}"
        log_action "ERROR" "Failed to remove user '$username' from group '$group_name'."
    fi
    echo -n "Press Enter to continue..." && read -r
}


create_group() {
    print_subsection "Create New Group"
    local groupname=$(read_user_input "Enter new group name" "")
    if [ -z "$groupname" ]; then
        echo -e "${RED}ERROR: Group name cannot be empty.${NC}"
        log_action "ERROR" "Create group failed: Group name empty."
        return 1
    fi

    if group_exists "$groupname"; then
        echo -e "${YELLOW}WARNING: Group '$groupname' already exists.${NC}"
        log_action "INFO" "Create group attempted for existing group: $groupname."
        return 0
    fi

    groupadd "$groupname"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Group '$groupname' created successfully.${NC}"
        log_action "SUCCESS" "Group '$groupname' created."
    else
        echo -e "${RED}ERROR: Failed to create group '$groupname'.${NC}"
        log_action "ERROR" "Failed to create group '$groupname'."
    fi
    echo -n "Press Enter to continue..." && read -r
}

delete_group() {
    print_subsection "Delete Group"
    local groupname=$(read_user_input "Enter group name to delete" "")
    if [ -z "$groupname" ]; then
        echo -e "${RED}ERROR: Group name cannot be empty.${NC}"
        log_action "ERROR" "Delete group failed: Group name empty."
        return 1
    fi

    if ! group_exists "$groupname"; then
        echo -e "${YELLOW}WARNING: Group '$groupname' does not exist.${NC}"
        log_action "INFO" "Delete group attempted for non-existent group: $groupname."
        return 0
    fi

    echo -n "Are you sure you want to delete group '$groupname'? (yes/no): "
    local confirm
    read -r confirm
    if [[ "$confirm" =~ ^[yY][eE][sS]$ ]]; then
        groupdel "$groupname"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Group '$groupname' deleted successfully.${NC}"
            log_action "SUCCESS" "Group '$groupname' deleted."
        else
            echo -e "${RED}ERROR: Failed to delete group '$groupname'. Make sure no users have it as their primary group.${NC}"
            log_action "ERROR" "Failed to delete group '$groupname'."
        fi
    else
        echo -e "${YELLOW}Group deletion cancelled.${NC}"
        log_action "INFO" "Group deletion cancelled for '$groupname'."
    fi
    echo -n "Press Enter to continue..." && read -r
}

list_groups() {
    print_subsection "List All Groups"
    echo -e "${CYAN}Group Name          GID    Members${NC}"
    echo -e "${CYAN}-----------------------------------------------------------------${NC}"
    getent group | awk -F: '{printf "%-20s %-6s %s\n", $1, $3, $4}'
    echo -e "${CYAN}-----------------------------------------------------------------${NC}"
    log_action "INFO" "Listed all groups."
    echo -n "Press Enter to continue..." && read -r
}


# --- Main Script Logic ---
main() {
    check_root

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_action "INFO" "User management script started."

    local choice
    while true; do
        print_menu
        read -r choice

        case "$choice" in
            1) create_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) list_users ;;
            5) add_user_to_group ;;
            6) remove_user_from_group ;;
            7) create_group ;;
            8) delete_group ;;
            9) list_groups ;;
            0)
                echo -e "${CYAN}Exiting User Account Management Tool. Goodbye!${NC}"
                log_action "INFO" "User management script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 9.${NC}"
                log_action "WARN" "Invalid menu choice: '$choice'."
                echo -n "Press Enter to continue..." && read -r
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
