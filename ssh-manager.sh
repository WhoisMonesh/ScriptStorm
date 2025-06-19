#!/bin/bash

# ssh-manager.sh - SSH Configuration Manager
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: A comprehensive script to manage SSH client configurations (~/.ssh/config),
#              SSH key pairs, and SSH server settings (/etc/ssh/sshd_config).
#              Includes functionalities for adding/removing hosts, generating/copying keys,
#              modifying server parameters, and reloading the SSH service.

# --- Configuration ---
LOG_FILE="/var/log/ssh-manager.log"     # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

SSH_CLIENT_CONFIG="$HOME/.ssh/config"   # SSH Client configuration file
SSH_KEYS_DIR="$HOME/.ssh"               # Directory for SSH keys
SSHD_CONFIG_FILE="/etc/ssh/sshd_config" # SSH Server configuration file
SSHD_CONFIG_BACKUP_DIR="/var/backups/sshd_config" # Directory for SSHD config backups

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="ssh-manager@yourdomain.com" # Sender email for alerts

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

check_root_for_server_ops() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}ERROR: SSH server configuration requires root privileges.${NC}"
        log_message "ERROR" "Attempted SSH server operation as non-root user."
        pause_script
        return 1
    fi
    return 0
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

reload_sshd_service() {
    print_subsection "Reloading SSH Service"
    if check_root_for_server_ops; then
        echo -e "${CYAN}Attempting to reload sshd service...${NC}"
        sudo systemctl reload sshd 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}SSHD service reloaded successfully.${NC}"
            log_message "SUCCESS" "SSHD service reloaded."
            send_email_alert "SSH Manager: SSHD Reloaded" "SSHD service reloaded successfully on $(hostname)."
        else
            echo -e "${RED}ERROR: Failed to reload sshd service. Check logs and configuration.${NC}"
            log_message "ERROR" "Failed to reload sshd service."
            send_email_alert "SSH Manager: SSHD Reload Failed" "SSHD service reload FAILED on $(hostname). Please investigate!"
        fi
    fi
    pause_script
}

backup_sshd_config() {
    local timestamp=$(date "$DATE_FORMAT")
    local backup_file="${SSHD_CONFIG_FILE}.${timestamp}"
    mkdir -p "$SSHD_CONFIG_BACKUP_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to create SSHD config backup directory: $SSHD_CONFIG_BACKUP_DIR."
        echo -e "${RED}ERROR: Failed to create SSHD config backup directory. Check permissions.${NC}"
        return 1
    fi

    cp -p "$SSHD_CONFIG_FILE" "$SSHD_CONFIG_BACKUP_DIR/$backup_file"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backed up ${SSHD_CONFIG_FILE} to $SSHD_CONFIG_BACKUP_DIR/$backup_file.${NC}"
        log_message "SUCCESS" "Backed up $SSHD_CONFIG_FILE to $backup_file."
        return 0
    else
        echo -e "${RED}ERROR: Failed to backup ${SSHD_CONFIG_FILE}.${NC}"
        log_message "ERROR" "Failed to backup $SSHD_CONFIG_FILE."
        return 1
    fi
}

restore_sshd_config() {
    print_subsection "Restore SSHD Configuration from Backup"
    if ! check_root_for_server_ops; then return; fi

    local backup_files=($(ls -t "$SSHD_CONFIG_BACKUP_DIR"/sshd_config.* 2>/dev/null))
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No SSHD configuration backups found in $SSHD_CONFIG_BACKUP_DIR.${NC}"
        log_message "WARN" "No SSHD config backups found for restore."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Available SSHD config backups (most recent first):${NC}"
    local i=1
    for file in "${backup_files[@]}"; do
        echo "  $i. $(basename "$file")"
        i=$((i+1))
    done

    local choice=$(read_user_input "Enter the number of the backup to restore (0 to cancel)" "")
    if [[ "$choice" -eq 0 ]]; then
        echo -e "${YELLOW}Restore cancelled.${NC}"
        log_message "INFO" "SSHD config restore cancelled."
        pause_script
        return 0
    fi

    if [[ "$choice" -ge 1 && "$choice" -le ${#backup_files[@]} ]]; then
        local selected_backup="${backup_files[$((choice-1))]}"
        echo -e "${YELLOW}WARNING: This will overwrite your current ${SSHD_CONFIG_FILE}.${NC}"
        if confirm_action "Are you sure you want to restore from $(basename "$selected_backup")?"; then
            cp -p "$selected_backup" "$SSHD_CONFIG_FILE"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Successfully restored ${SSHD_CONFIG_FILE} from $(basename "$selected_backup").${NC}"
                log_message "SUCCESS" "Restored $SSHD_CONFIG_FILE from $selected_backup."
                reload_sshd_service
            else
                echo -e "${RED}ERROR: Failed to restore ${SSHD_CONFIG_FILE}.${NC}"
                log_message "ERROR" "Failed to restore $SSHD_CONFIG_FILE from $selected_backup."
            fi
        fi
    else
        echo -e "${RED}Invalid choice.${NC}"
    fi
    pause_script
}

# Generic function to modify an sshd_config setting
modify_sshd_setting() {
    local setting_name="$1"
    local new_value="$2"
    local default_value_hint="$3" # Optional hint for user
    
    if ! check_root_for_server_ops; then return 1; fi
    if ! backup_sshd_config; then return 1; fi # Always backup before modifying

    echo -e "${CYAN}Modifying SSHD setting: ${setting_name}${NC}"
    echo "Current value(s) for ${setting_name}:"
    grep -E "^#?${setting_name}\s+" "$SSHD_CONFIG_FILE" | sed -E "s/^\s*#?//g" # Show active and commented out
    echo "Default/Recommended: $default_value_hint"
    
    local confirm_val=$(read_user_input "Enter new value for ${setting_name}" "$new_value")

    if [ -z "$confirm_val" ]; then
        echo -e "${YELLOW}No new value entered. Skipping modification for ${setting_name}.${NC}"
        log_message "INFO" "Modification for $setting_name skipped (empty value)."
        pause_script
        return 0
    fi

    if confirm_action "Apply change: ${setting_name} $confirm_val?"; then
        # Use sed to replace or add the setting
        # 1. Remove any existing lines for this setting (commented or uncommented)
        sudo sed -i "/^[[:space:]]*#\?${setting_name}[[:space:]]\+/d" "$SSHD_CONFIG_FILE"
        # 2. Add the new setting at the end of the file
        echo "${setting_name} ${confirm_val}" | sudo tee -a "$SSHD_CONFIG_FILE" >/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Setting '${setting_name}' updated to '${confirm_val}' successfully.${NC}"
            log_message "SUCCESS" "SSHD setting '$setting_name' updated to '$confirm_val'."
            reload_sshd_service
        else
            echo -e "${RED}ERROR: Failed to update setting '${setting_name}'.${NC}"
            log_message "ERROR" "Failed to update SSHD setting '$setting_name'."
        fi
    fi
    pause_script
}

# --- SSH Client Configuration Functions ---

add_client_host() {
    print_subsection "Add/Edit SSH Client Host Entry"
    mkdir -p "$SSH_KEYS_DIR"
    chmod 700 "$SSH_KEYS_DIR"
    touch "$SSH_CLIENT_CONFIG"
    chmod 600 "$SSH_CLIENT_CONFIG"

    local host_alias=$(read_user_input "Enter Host alias (e.g., myserver, test-vm)" "")
    if [ -z "$host_alias" ]; then echo -e "${RED}Host alias cannot be empty.${NC}"; pause_script; return 1; fi

    # Check if host already exists
    if grep -qE "^Host\s+$host_alias$" "$SSH_CLIENT_CONFIG" 2>/dev/null; then
        echo -e "${YELLOW}Host '$host_alias' already exists. This will modify existing entry.${NC}"
        if ! confirm_action "Continue to modify existing entry?"; then pause_script; return 0; fi
        # Remove existing block to re-add cleaner
        sed -i "/^Host\s\+$host_alias$/,/^$/{/^$/!d;}" "$SSH_CLIENT_CONFIG"
        sed -i "/^Host\s\+$host_alias$/d" "$SSH_CLIENT_CONFIG" # Remove the Host line itself
    fi

    local hostname=$(read_user_input "Enter HostName (IP address or FQDN)" "")
    local user=$(read_user_input "Enter User" "")
    local port=$(read_user_input "Enter Port (default: 22)" "22")
    local identity_file=$(read_user_input "Enter IdentityFile (e.g., ~/.ssh/id_rsa or leave empty)" "")

    echo -e "${CYAN}Adding/Updating entry for Host $host_alias...${NC}"
    echo -e "\nHost $host_alias" >> "$SSH_CLIENT_CONFIG"
    [ -n "$hostname" ] && echo "  HostName $hostname" >> "$SSH_CLIENT_CONFIG"
    [ -n "$user" ] && echo "  User $user" >> "$SSH_CLIENT_CONFIG"
    [ -n "$port" ] && echo "  Port $port" >> "$SSH_CLIENT_CONFIG"
    [ -n "$identity_file" ] && echo "  IdentityFile $identity_file" >> "$SSH_CLIENT_CONFIG"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Host '$host_alias' added/updated successfully in $SSH_CLIENT_CONFIG.${NC}"
        log_message "SUCCESS" "SSH client host '$host_alias' added/updated."
    else
        echo -e "${RED}ERROR: Failed to add/update host '$host_alias'.${NC}"
        log_message "ERROR" "Failed to add/update SSH client host '$host_alias'."
    fi
    pause_script
}

remove_client_host() {
    print_subsection "Remove SSH Client Host Entry"
    if [ ! -f "$SSH_CLIENT_CONFIG" ]; then
        echo -e "${YELLOW}SSH client config file not found: $SSH_CLIENT_CONFIG.${NC}"
        pause_script; return 1;
    fi

    local host_aliases=$(grep "^Host " "$SSH_CLIENT_CONFIG" | awk '{print $2}')
    if [ -z "$host_aliases" ]; then
        echo -e "${YELLOW}No host entries found in $SSH_CLIENT_CONFIG.${NC}"
        pause_script; return 0;
    fi

    echo -e "${CYAN}Available SSH Hosts:${NC}"
    echo "$host_aliases" | nl

    local choice=$(read_user_input "Enter the number of the host to remove (0 to cancel)" "")
    if [[ "$choice" -eq 0 ]]; then
        echo -e "${YELLOW}Removal cancelled.${NC}"
        pause_script; return 0;
    fi

    local alias_to_remove=$(echo "$host_aliases" | sed -n "${choice}p")
    if [ -z "$alias_to_remove" ]; then
        echo -e "${RED}Invalid choice.${NC}"
        pause_script; return 1;
    fi

    if confirm_action "Are you sure you want to remove host '$alias_to_remove'?"; then
        # Use sed to remove the entire block for the host
        sudo sed -i "/^Host\s\+$alias_to_remove$/,/^$/{/^$/!d;}" "$SSH_CLIENT_CONFIG"
        sudo sed -i "/^Host\s\+$alias_to_remove$/d" "$SSH_CLIENT_CONFIG"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Host '$alias_to_remove' removed successfully from $SSH_CLIENT_CONFIG.${NC}"
            log_message "SUCCESS" "SSH client host '$alias_to_remove' removed."
        else
            echo -e "${RED}ERROR: Failed to remove host '$alias_to_remove'.${NC}"
            log_message "ERROR" "Failed to remove SSH client host '$alias_to_remove'."
        fi
    fi
    pause_script
}

list_client_hosts() {
    print_subsection "List SSH Client Hosts"
    if [ ! -f "$SSH_CLIENT_CONFIG" ]; then
        echo -e "${YELLOW}SSH client config file not found: $SSH_CLIENT_CONFIG.${NC}"
        pause_script; return 1;
    fi
    echo -e "${CYAN}Contents of $SSH_CLIENT_CONFIG:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    cat "$SSH_CLIENT_CONFIG" 2>/dev/null || log_message "ERROR" "Failed to read $SSH_CLIENT_CONFIG."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed SSH client hosts."
    pause_script
}

test_ssh_connection() {
    print_subsection "Test SSH Connection"
    local host_alias=$(read_user_input "Enter Host alias or user@host to test" "")
    if [ -z "$host_alias" ]; then echo -e "${RED}Host cannot be empty.${NC}"; pause_script; return 1; fi

    echo -e "${CYAN}Attempting SSH connection test to '$host_alias' (verbose output)...${NC}"
    log_message "INFO" "Testing SSH connection to $host_alias."
    echo -e "${YELLOW}You may be prompted for passwords/passphrases.${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    ssh -v -o BatchMode=yes -o ConnectTimeout=10 "$host_alias" exit 2>&1
    local status=$?
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}SSH connection test to '$host_alias' was successful.${NC}"
        log_message "SUCCESS" "SSH connection test to $host_alias successful."
    else
        echo -e "${RED}SSH connection test to '$host_alias' FAILED. Exit code: $status.${NC}"
        log_message "ERROR" "SSH connection test to $host_alias FAILED."
    fi
    pause_script
}

# --- SSH Key Management Functions ---

generate_ssh_key() {
    print_subsection "Generate New SSH Key Pair"
    mkdir -p "$SSH_KEYS_DIR"
    chmod 700 "$SSH_KEYS_DIR"

    local key_type=$(read_user_input "Enter key type (rsa, dsa, ecdsa, ed25519, default: rsa)" "rsa")
    local key_file=$(read_user_input "Enter key file name (e.g., id_rsa, default: id_ed25519) - will be in $SSH_KEYS_DIR" "id_ed25519")
    local key_path="${SSH_KEYS_DIR}/${key_file}"

    if [ -f "$key_path" ]; then
        echo -e "${YELLOW}Key file '$key_path' already exists. ${NC}"
        if ! confirm_action "Overwrite existing key?"; then pause_script; return 0; fi
    fi

    echo -e "${CYAN}Generating ${key_type} key pair as '$key_path'...${NC}"
    log_message "INFO" "Generating SSH key: $key_path (type: $key_type)."
    ssh-keygen -t "$key_type" -f "$key_path"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH key pair generated successfully:${NC}"
        echo "  Public Key: ${key_path}.pub"
        echo "  Private Key: ${key_path}"
        log_message "SUCCESS" "SSH key pair '$key_path' generated."
    else
        echo -e "${RED}ERROR: Failed to generate SSH key pair.${NC}"
        log_message "ERROR" "Failed to generate SSH key pair: $key_path."
    fi
    pause_script
}

list_ssh_keys() {
    print_subsection "List SSH Key Pairs"
    if [ ! -d "$SSH_KEYS_DIR" ]; then
        echo -e "${YELLOW}SSH keys directory not found: $SSH_KEYS_DIR.${NC}"
        pause_script; return 1;
    fi

    echo -e "${CYAN}SSH Public Keys in $SSH_KEYS_DIR:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    ls -l "$SSH_KEYS_DIR"/*.pub 2>/dev/null | awk '{print $NF, $5, $6, $7, $8}' || echo "No public keys found."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    echo -e "${CYAN}SSH Private Keys in $SSH_KEYS_DIR:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    ls -l "$SSH_KEYS_DIR" | grep -v "\.pub$" | grep -E "^-r" | awk '{print $NF, $5, $6, $7, $8}' || echo "No private keys found (excluding public keys)."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed SSH key pairs."
    pause_script
}

copy_ssh_id() {
    print_subsection "Copy Public Key to Remote Server"
    if ! check_command "ssh-copy-id"; then
        echo -e "${RED}ERROR: 'ssh-copy-id' command not found. Install 'openssh-client' or 'openssh-server' package.${NC}"
        log_message "ERROR" "'ssh-copy-id' not found."
        pause_script
        return 1
    fi

    local user_host=$(read_user_input "Enter user@host to copy ID to (e.g., user@server.example.com)" "")
    if [ -z "$user_host" ]; then echo -e "${RED}User@host cannot be empty.${NC}"; pause_script; return 1; fi

    local public_key_file=$(read_user_input "Enter path to public key file (e.g., ~/.ssh/id_rsa.pub, default: ~/.ssh/id_rsa.pub)" "$HOME/.ssh/id_rsa.pub")
    if [ ! -f "$public_key_file" ]; then
        echo -e "${RED}ERROR: Public key file '$public_key_file' not found.${NC}"
        log_message "ERROR" "Public key file not found: $public_key_file."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Copying '$public_key_file' to '$user_host' using ssh-copy-id...${NC}"
    log_message "INFO" "Copying SSH ID: $public_key_file to $user_host."
    ssh-copy-id -i "$public_key_file" "$user_host"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Public key copied successfully.${NC}"
        log_message "SUCCESS" "Public key copied to $user_host."
    else
        echo -e "${RED}ERROR: Failed to copy public key. Check user@host, permissions, or password.${NC}"
        log_message "ERROR" "Failed to copy public key to $user_host."
    fi
    pause_script
}

delete_ssh_key() {
    print_subsection "Delete SSH Key Pair"
    if [ ! -d "$SSH_KEYS_DIR" ]; then
        echo -e "${YELLOW}SSH keys directory not found: $SSH_KEYS_DIR.${NC}"
        pause_script; return 1;
    fi

    local key_files=($(find "$SSH_KEYS_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null))
    if [ ${#key_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No private key files found in $SSH_KEYS_DIR.${NC}"
        pause_script; return 0;
    fi

    echo -e "${CYAN}Available SSH Private Keys:${NC}"
    local i=1
    for file in "${key_files[@]}"; do
        echo "  $i. $(basename "$file")"
        i=$((i+1))
    done

    local choice=$(read_user_input "Enter the number of the key to delete (0 to cancel)" "")
    if [[ "$choice" -eq 0 ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        pause_script; return 0;
    fi

    local key_to_delete="${key_files[$((choice-1))]}"
    local pub_key_to_delete="${key_to_delete}.pub"

    if [ -z "$key_to_delete" ]; then
        echo -e "${RED}Invalid choice.${NC}"
        pause_script; return 1;
    fi

    echo -e "${YELLOW}WARNING: This will permanently delete '$key_to_delete' and its public key '$pub_key_to_delete'.${NC}"
    if confirm_action "Are you sure you want to delete this key pair?"; then
        rm -v "$key_to_delete" "$pub_key_to_delete" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Key pair '${key_to_delete}' deleted successfully.${NC}"
            log_message "SUCCESS" "SSH key pair '$key_to_delete' deleted."
        else
            echo -e "${RED}ERROR: Failed to delete key pair '${key_to_delete}'. Check permissions.${NC}"
            log_message "ERROR" "Failed to delete SSH key pair '$key_to_delete'."
        fi
    fi
    pause_script
}

# --- SSH Server Configuration Functions ---

view_sshd_config() {
    print_subsection "View SSH Server Configuration"
    if [ ! -f "$SSHD_CONFIG_FILE" ]; then
        echo -e "${RED}ERROR: SSHD config file not found: $SSHD_CONFIG_FILE.${NC}"
        log_message "ERROR" "SSHD config file not found for viewing."
        pause_script; return 1;
    fi
    echo -e "${CYAN}Contents of $SSHD_CONFIG_FILE:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    cat "$SSHD_CONFIG_FILE" 2>/dev/null || log_message "ERROR" "Failed to read $SSHD_CONFIG_FILE."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Viewed SSHD configuration."
    pause_script
}

# Specific SSHD setting modifications using the generic function
modify_sshd_port() {
    print_subsection "Modify SSH Port"
    local current_port=$(grep -E "^Port\s+" "$SSHD_CONFIG_FILE" | awk '{print $2}' | tail -n 1) # Get last Port directive
    if [ -z "$current_port" ]; then current_port="22"; fi # Default if not found
    modify_sshd_setting "Port" "$current_port" "Default: 22"
}

modify_sshd_root_login() {
    print_subsection "Modify PermitRootLogin"
    local current_value=$(grep -E "^PermitRootLogin\s+" "$SSHD_CONFIG_FILE" | awk '{print $2}' | tail -n 1)
    if [ -z "$current_value" ]; then current_value="prohibit-password"; fi # Common default
    modify_sshd_setting "PermitRootLogin" "$current_value" "Options: yes, prohibit-password, forced-commands-only, no"
}

modify_sshd_password_auth() {
    print_subsection "Modify PasswordAuthentication"
    local current_value=$(grep -E "^PasswordAuthentication\s+" "$SSHD_CONFIG_FILE" | awk '{print $2}' | tail -n 1)
    if [ -z "$current_value" ]; then current_value="yes"; fi # Default is often yes
    modify_sshd_setting "PasswordAuthentication" "$current_value" "Options: yes, no"
}

modify_sshd_pubkey_auth() {
    print_subsection "Modify PubkeyAuthentication"
    local current_value=$(grep -E "^PubkeyAuthentication\s+" "$SSHD_CONFIG_FILE" | awk '{print $2}' | tail -n 1)
    if [ -z "$current_value" ]; then current_value="yes"; fi # Default is often yes
    modify_sshd_setting "PubkeyAuthentication" "$current_value" "Options: yes, no"
}

manage_sshd_user_group_access() {
    print_subsection "Manage SSHD User/Group Access (Allow/Deny)"
    if ! check_root_for_server_ops; then return; fi
    if ! backup_sshd_config; then return; fi

    echo -e "${CYAN}1. AllowUsers / DenyUsers${NC}"
    echo -e "${CYAN}2. AllowGroups / DenyGroups${NC}"
    echo -n "Choose type to manage (1 or 2, 0 to cancel): "
    read -r access_type_choice

    local setting_name=""
    local current_value=""
    local prompt_hint=""

    case "$access_type_choice" in
        1)
            setting_name="AllowUsers"
            current_value=$(grep -E "^${setting_name}\s+" "$SSHD_CONFIG_FILE" | sed -E "s/^\s*#?${setting_name}\s+//g" | tr '\n' ' ' | sed 's/ $//')
            if [ -z "$current_value" ]; then setting_name="DenyUsers"; fi # Check DenyUsers if AllowUsers not found
            current_value=$(grep -E "^${setting_name}\s+" "$SSHD_CONFIG_FILE" | sed -E "s/^\s*#?${setting_name}\s+//g" | tr '\n' ' ' | sed 's/ $//')
            prompt_hint="Space-separated usernames (e.g., user1 user2)"
            ;;
        2)
            setting_name="AllowGroups"
            current_value=$(grep -E "^${setting_name}\s+" "$SSHD_CONFIG_FILE" | sed -E "s/^\s*#?${setting_name}\s+//g" | tr '\n' ' ' | sed 's/ $//')
            if [ -z "$current_value" ]; then setting_name="DenyGroups"; fi # Check DenyGroups if AllowGroups not found
            current_value=$(grep -E "^${setting_name}\s+" "$SSHD_CONFIG_FILE" | sed -E "s/^\s*#?${setting_name}\s+//g" | tr '\n' ' ' | sed 's/ $//')
            prompt_hint="Space-separated group names (e.g., admin_group devops_group)"
            ;;
        0) echo -e "${YELLOW}Operation cancelled.${NC}"; pause_script; return 0;;
        *) echo -e "${RED}Invalid choice.${NC}"; pause_script; return 1;;
    esac

    echo -e "${CYAN}Current '${setting_name}' value: '${current_value}'${NC}"
    local new_setting_name=$(read_user_input "Choose new setting type (AllowUsers, DenyUsers, AllowGroups, DenyGroups)" "$setting_name")
    local new_value=$(read_user_input "Enter new value for ${new_setting_name} ($prompt_hint or 'none' to remove)" "$current_value")

    if [ -z "$new_value" ]; then
        echo -e "${YELLOW}No new value entered. Skipping modification.${NC}"
        log_message "INFO" "SSH access rule modification skipped (empty value)."
        pause_script
        return 0
    fi

    if confirm_action "Apply change: ${new_setting_name} ${new_value}?"; then
        # Remove any existing AllowUsers/DenyUsers/AllowGroups/DenyGroups lines
        sudo sed -i -E "/^[[:space:]]*#?(AllowUsers|DenyUsers|AllowGroups|DenyGroups)[[:space:]]+/d" "$SSHD_CONFIG_FILE"
        
        if [[ "$new_value" == "none" ]]; then
            echo -e "${GREEN}Removed all ${new_setting_name} rules.${NC}"
            log_message "SUCCESS" "Removed all $new_setting_name rules."
        else
            echo "${new_setting_name} ${new_value}" | sudo tee -a "$SSHD_CONFIG_FILE" >/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Setting '${new_setting_name}' updated to '${new_value}' successfully.${NC}"
                log_message "SUCCESS" "SSHD access rule '$new_setting_name' updated to '$new_value'."
            else
                echo -e "${RED}ERROR: Failed to update setting '${new_setting_name}'.${NC}"
                log_message "ERROR" "Failed to update SSHD access rule '$new_setting_name'."
            fi
        fi
        reload_sshd_service
    fi
    pause_script
}

# --- Main Menus ---

display_client_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> SSH Client Configuration (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Add/Edit Host Entry${NC}"
    echo -e "${GREEN}2. Remove Host Entry${NC}"
    echo -e "${GREEN}3. List All Host Entries${NC}"
    echo -e "${GREEN}4. Test SSH Connection${NC}"
    echo -e "${YELLOW}0. Back to Main Menu${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

display_key_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> SSH Key Management (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Generate New Key Pair${NC}"
    echo -e "${GREEN}2. List SSH Key Pairs${NC}"
    echo -e "${GREEN}3. Copy Public Key to Server (ssh-copy-id)${NC}"
    echo -e "${GREEN}4. Delete SSH Key Pair${NC}"
    echo -e "${YELLOW}0. Back to Main Menu${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

display_server_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> SSH Server Configuration (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. View Current sshd_config${NC}"
    echo -e "${GREEN}2. Modify SSH Port${NC}"
    echo -e "${GREEN}3. Modify PermitRootLogin${NC}"
    echo -e "${GREEN}4. Modify PasswordAuthentication${NC}"
    echo -e "${GREEN}5. Modify PubkeyAuthentication${NC}"
    echo -e "${GREEN}6. Manage User/Group Access (Allow/DenyUsers/Groups)${NC}"
    echo -e "${GREEN}7. Reload SSH Service${NC}"
    echo -e "${GREEN}8. Restore sshd_config from Backup${NC}"
    echo -e "${YELLOW}0. Back to Main Menu${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main_menu_loop() {
    local choice
    while true; do
        clear
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${BLUE}>>> SSH Manager (WhoisMonesh) <<<${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${GREEN}1. SSH Client Configuration (~/.ssh/config)${NC}"
        echo -e "${GREEN}2. SSH Key Management (~/.ssh/)${NC}"
        echo -e "${GREEN}3. SSH Server Configuration (/etc/ssh/sshd_config)${NC}"
        echo -e "${YELLOW}0. Exit${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -n "Enter your choice: "
        read -r choice

        case "$choice" in
            1)
                while true; do
                    display_client_menu
                    read -r client_choice
                    case "$client_choice" in
                        1) add_client_host ;;
                        2) remove_client_host ;;
                        3) list_client_hosts ;;
                        4) test_ssh_connection ;;
                        0) break ;;
                        *) echo -e "${RED}Invalid choice. Please enter a number between 0 and 4.${NC}"; pause_script ;;
                    esac
                done
                ;;
            2)
                while true; do
                    display_key_menu
                    read -r key_choice
                    case "$key_choice" in
                        1) generate_ssh_key ;;
                        2) list_ssh_keys ;;
                        3) copy_ssh_id ;;
                        4) delete_ssh_key ;;
                        0) break ;;
                        *) echo -e "${RED}Invalid choice. Please enter a number between 0 and 4.${NC}"; pause_script ;;
                    esac
                done
                ;;
            3)
                while true; do
                    display_server_menu
                    read -r server_choice
                    case "$server_choice" in
                        1) view_sshd_config ;;
                        2) modify_sshd_port ;;
                        3) modify_sshd_root_login ;;
                        4) modify_sshd_password_auth ;;
                        5) modify_sshd_pubkey_auth ;;
                        6) manage_sshd_user_group_access ;;
                        7) reload_sshd_service ;;
                        8) restore_sshd_config ;;
                        0) break ;;
                        *) echo -e "${RED}Invalid choice. Please enter a number between 0 and 8.${NC}"; pause_script ;;
                    esac
                done
                ;;
            0)
                echo -e "${CYAN}Exiting SSH Manager. Goodbye!${NC}"
                log_message "INFO" "SSH manager script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 3.${NC}"
                log_message "WARN" "Invalid main menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main() {
    # Ensure log directory and SSH keys directory exist
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi
    mkdir -p "$SSH_KEYS_DIR"
    chmod 700 "$SSH_KEYS_DIR" # Ensure correct permissions for ~/.ssh
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create SSH keys directory $SSH_KEYS_DIR. Exiting.${NC}"
        log_message "ERROR" "Failed to create SSH keys directory: $SSH_KEYS_DIR"
        exit 1
    fi
    touch "$SSH_CLIENT_CONFIG" # Ensure client config file exists
    chmod 600 "$SSH_CLIENT_CONFIG" # Ensure correct permissions

    log_message "INFO" "SSH manager script started."
    main_menu_loop
}

main
