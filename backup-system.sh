#!/bin/bash

# backup-system.sh - Complete System Backup Solution
# Version: 2.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides a menu-driven interface for comprehensive
#              system backups. It supports full system (excluding non-essential),
#              specific directories, different compression levels, local/remote
#              destinations, retention policies, and notifications.

# --- Configuration ---
LOG_FILE="/var/log/backup-system.log"    # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"
TIMESTAMP=$(date "$DATE_FORMAT")

# Default Backup Settings
DEFAULT_LOCAL_BACKUP_DIR="/mnt/backups/local" # Local backup destination
DEFAULT_COMPRESSION="gz"                    # gz (gzip), bz2 (bzip2), xz (xz)
DEFAULT_RETENTION_DAYS=7                    # Number of days to keep backups
DEFAULT_RETENTION_COUNT=5                   # Number of most recent backups to keep

# Remote Backup Settings (Uncomment and configure for remote backups)
# REMOTE_BACKUP_USER="backupuser"
# REMOTE_BACKUP_HOST="your.backup.server.com"
# REMOTE_BACKUP_PATH="/mnt/remote_backups" # Path on the remote server
# Use SSH key-based authentication for remote backups for automation

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send success/failure alerts
SENDER_EMAIL="backup-system@yourdomain.com" # Sender email for alerts

# Directories to EXCLUDE during a FULL system backup (crucial for valid backups)
declare -a FULL_SYSTEM_EXCLUDES=(
    "/dev"
    "/proc"
    "/sys"
    "/tmp"
    "/run"
    "/mnt"
    "/media"
    "/lost+found"
    "/var/cache/apt/archives" # Debian/Ubuntu package cache
    "/var/tmp"
    "/var/run"
    "/var/lock"
    # Add your backup destination if it's on the same filesystem as /
    "${DEFAULT_LOCAL_BACKUP_DIR}"
    # If REMOTE_BACKUP_PATH is mounted locally for rsync, exclude it
    # "/path/to/remote/mountpoint"
)

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
        echo -e "${RED}ERROR: This script must be run as root for full system backups and access to all files.${NC}"
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

# --- Backup Core Logic ---

build_tar_excludes() {
    local excludes_string=""
    for exclude_path in "${FULL_SYSTEM_EXCLUDES[@]}"; do
        # Add a test to ensure the exclude path exists, otherwise tar will complain
        if [ -e "$exclude_path" ]; then
            excludes_string+=" --exclude=${exclude_path}"
        else
            log_message "WARN" "Exclude path '$exclude_path' does not exist. Skipping."
        fi
    done
    echo "$excludes_string"
}

select_compression_flags() {
    local comp_choice="$1"
    case "$comp_choice" in
        "gz") echo "z" ;;
        "bz2") echo "j" ;;
        "xz") echo "J" ;;
        *) echo "z" ;; # Default to gzip
    esac
}

select_compression_suffix() {
    local comp_choice="$1"
    case "$comp_choice" in
        "gz") echo "tar.gz" ;;
        "bz2") echo "tar.bz2" ;;
        "xz") echo "tar.xz" ;;
        *) echo "tar.gz" ;; # Default to gzip
    esac
}

perform_tar_backup() {
    local backup_source="$1"
    local backup_type_label="$2" # e.g., "Full System", "Home Directory"
    local backup_destination=$(read_user_input "Enter backup destination directory (local path or user@host:/path)" "$DEFAULT_LOCAL_BACKUP_DIR")
    local compression_method=$(read_user_input "Choose compression (gz, bz2, xz, default: $DEFAULT_COMPRESSION)" "$DEFAULT_COMPRESSION")

    local comp_flag=$(select_compression_flags "$compression_method")
    local comp_suffix=$(select_compression_suffix "$compression_method")
    local backup_filename="${backup_type_label// /-}-${TIMESTAMP}.${comp_suffix}"
    local full_backup_path=""
    local remote_target=""
    local remote_host=""

    if [[ "$backup_destination" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\:.*$ ]]; then
        # Remote destination (user@host:/path)
        remote_host=$(echo "$backup_destination" | cut -d':' -f1)
        remote_target=$(echo "$backup_destination" | cut -d':' -f2-)
        full_backup_path="${remote_host}:${remote_target}/${backup_filename}"
        log_message "INFO" "Initiating remote TAR backup to: $full_backup_path"
        echo -e "${CYAN}Attempting remote backup to $full_backup_path...${NC}"
        # ssh is implied here for remote tar. It's best to have SSH keys setup.
        # tar options: c (create), p (preserve permissions), v (verbose), f (file), - (stdout)
        # We pipe local tar output to remote ssh tar.
        # It's important to specify '-C /' for full system backups if source is '/'
        local tar_base_dir="/"
        if [[ "$backup_source" != "/" ]]; then
            tar_base_dir=$(dirname "$backup_source")
        fi

        local tar_command="tar -C \"$tar_base_dir\" -cv${comp_flag}f - \"$(basename "$backup_source")\""
        if [[ "$backup_source" == "/" ]]; then # Full system
            tar_command="tar -C / -cv${comp_flag}f - ${EXCLUDES_TAR_STRING} ." # '.' means current dir, which is /
        fi

        # Remote command to receive and save tar stream
        local ssh_command="ssh $remote_host \"mkdir -p '$remote_target' && cat > '$remote_target/$backup_filename'\""
        
        eval "$tar_command" | eval "$ssh_command"
        BACKUP_STATUS=$?

    else
        # Local destination
        mkdir -p "$backup_destination"
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to create local backup directory '$backup_destination'. Check permissions.${NC}"
            log_message "ERROR" "Failed to create local backup dir: $backup_destination"
            send_email_alert "Backup Failed: Directory Creation" "Backup to $backup_destination failed due to directory creation error."
            pause_script
            return 1
        fi
        full_backup_path="${backup_destination}/${backup_filename}"
        log_message "INFO" "Initiating local TAR backup to: $full_backup_path"
        echo -e "${CYAN}Attempting local backup to $full_backup_path...${NC}"

        local tar_cmd_options="-cv${comp_flag}f"
        local tar_source_option="$backup_source"
        local excludes_list=()

        if [[ "$backup_source" == "/" ]]; then # Full system
            tar_cmd_options="-cv${comp_flag}f -C /" # Change directory to root
            tar_source_option="." # Backup current directory (which is now /)
            for excl in "${FULL_SYSTEM_EXCLUDES[@]}"; do
                # Tar exclude paths must be relative to the CWD, which is /
                local relative_excl=$(echo "$excl" | sed 's/^\///')
                if [ -n "$relative_excl" ]; then
                    excludes_list+=("--exclude=${relative_excl}")
                fi
            done
        fi
        
        # Build the full tar command
        local tar_command_string="tar ${tar_cmd_options} \"$full_backup_path\" ${excludes_list[@]} \"$tar_source_option\""
        eval "$tar_command_string"
        BACKUP_STATUS=$?
    fi

    if [ $BACKUP_STATUS -eq 0 ]; then
        echo -e "${GREEN}TAR backup of '$backup_source' to '$full_backup_path' completed successfully.${NC}"
        log_action "SUCCESS" "TAR backup of '$backup_source' completed to '$full_backup_path'."
        send_email_alert "Backup Success: $backup_type_label" "TAR backup of $backup_source to $full_backup_path completed on $(hostname)."
        verify_backup "$full_backup_path"
        if [[ "$backup_destination" == "$DEFAULT_LOCAL_BACKUP_DIR" ]]; then # Only run retention on local default
             manage_retention "$backup_destination" "$backup_type_label" "$comp_suffix"
        fi
    else
        echo -e "${RED}ERROR: TAR backup of '$backup_source' to '$full_backup_path' FAILED.${NC}"
        log_action "ERROR" "TAR backup of '$backup_source' FAILED. Exit code: $BACKUP_STATUS."
        send_email_alert "Backup FAILED: $backup_type_label" "TAR backup of $backup_source to $full_backup_path FAILED on $(hostname). Exit code: $BACKUP_STATUS."
    fi
    pause_script
}

perform_rsync_backup() {
    print_subsection "Perform rsync Backup (Incremental)"
    local backup_source=$(read_user_input "Enter source path for rsync (e.g., /var/www, /home/user)" "")
    local backup_destination=$(read_user_input "Enter rsync destination (local path or user@host:/path)" "$DEFAULT_LOCAL_BACKUP_DIR/rsync_data")

    if [ -z "$backup_source" ] || [ ! -d "$backup_source" ]; then
        echo -e "${RED}ERROR: Invalid source path '$backup_source'. It must be a valid directory.${NC}"
        log_action "ERROR" "rsync backup failed: invalid source '$backup_source'."
        pause_script
        return 1
    fi

    local rsync_options="-avz --delete --exclude-from=<(echo \"*~\" ; echo \".cache/\")" # archive, verbose, compress, delete extraneous, exclude temp files
    local log_output="/tmp/rsync_log_$(date +%s).txt"

    echo -e "${CYAN}Performing rsync backup from '$backup_source' to '$backup_destination'...${NC}"
    log_message "INFO" "Initiating rsync backup from '$backup_source' to '$backup_destination'."

    # Add --backup-dir for true incremental or just rely on --delete for sync
    # For a true incremental, use --link-dest and a previous snapshot. This script will keep it simple.

    rsync $rsync_options "$backup_source"/ "$backup_destination" > "$log_output" 2>&1
    BACKUP_STATUS=$?

    if [ $BACKUP_STATUS -eq 0 ]; then
        echo -e "${GREEN}Rsync backup of '$backup_source' to '$backup_destination' completed successfully.${NC}"
        log_action "SUCCESS" "Rsync backup of '$backup_source' completed to '$backup_destination'. Log: $log_output"
        send_email_alert "Backup Success: Rsync" "Rsync backup of $backup_source to $backup_destination completed on $(hostname). See $log_output for details."
    else
        echo -e "${RED}ERROR: Rsync backup of '$backup_source' to '$backup_destination' FAILED.${NC}"
        echo -e "${RED}Rsync Log Output:${NC}"
        cat "$log_output"
        log_action "ERROR" "Rsync backup of '$backup_source' FAILED. Exit code: $BACKUP_STATUS. Log: $log_output"
        send_email_alert "Backup FAILED: Rsync" "Rsync backup of $backup_source to $backup_destination FAILED on $(hostname). Exit code: $BACKUP_STATUS. See $log_output for details."
    fi
    rm -f "$log_output" # Clean up temporary log
    pause_script
}

manage_retention() {
    print_subsection "Managing Backup Retention"
    local backup_dir="$1"
    local backup_type_label="$2"
    local comp_suffix="$3"

    if [ -z "$backup_dir" ]; then
        log_message "WARN" "Retention management called without a directory."
        return 1
    fi

    log_message "INFO" "Applying retention policy to '$backup_dir' for '${backup_type_label}*.$comp_suffix'."

    # Delete backups older than DEFAULT_RETENTION_DAYS
    echo -e "${CYAN}Deleting backups older than $DEFAULT_RETENTION_DAYS days from '$backup_dir'...${NC}"
    find "$backup_dir" -maxdepth 1 -name "${backup_type_label// /-}-*.${comp_suffix}" -type f -mtime +"$DEFAULT_RETENTION_DAYS" -exec rm -v {} \; \
    || log_message "WARN" "No backups older than $DEFAULT_RETENTION_DAYS days found or failed to delete."

    # Keep only the last DEFAULT_RETENTION_COUNT backups
    echo -e "${CYAN}Keeping only the last $DEFAULT_RETENTION_COUNT backups from '$backup_dir'...${NC}"
    ls -t "$backup_dir"/${backup_type_label// /-}-*.${comp_suffix} 2>/dev/null | tail -n +"$((DEFAULT_RETENTION_COUNT + 1))" | xargs -r rm -v \
    || log_message "WARN" "Fewer than $DEFAULT_RETENTION_COUNT backups found or failed to delete oldest."

    log_message "SUCCESS" "Retention policy applied to '$backup_dir'."
    echo -e "${GREEN}Retention policy applied.${NC}"
}

verify_backup() {
    print_subsection "Verifying Backup Archive"
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}ERROR: Backup file '$backup_file' not found for verification.${NC}"
        log_message "ERROR" "Verification failed: backup file '$backup_file' not found."
        return 1
    fi

    echo -e "${CYAN}Verifying integrity of '$backup_file'...${NC}"
    log_message "INFO" "Verifying backup: $backup_file"

    local compression_test_cmd=""
    if [[ "$backup_file" == *.tar.gz ]]; then
        compression_test_cmd="gzip -t"
    elif [[ "$backup_file" == *.tar.bz2 ]]; then
        compression_test_cmd="bzip2 -t"
    elif [[ "$backup_file" == *.tar.xz ]]; then
        compression_test_cmd="xz -t"
    else
        echo -e "${YELLOW}WARNING: Unknown compression type for '$backup_file'. Skipping compression test.${NC}"
        log_message "WARN" "Unknown compression type for '$backup_file', skipping compression test."
    fi

    if [ -n "$compression_test_cmd" ]; then
        echo "  Testing compression integrity..."
        $compression_test_cmd "$backup_file"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  Compression integrity OK.${NC}"
            log_message "INFO" "Compression integrity OK for '$backup_file'."
        else
            echo -e "${RED}  Compression integrity FAILED.${NC}"
            log_message "ERROR" "Compression integrity FAILED for '$backup_file'."
            send_email_alert "Backup Warning: Compression Failure" "Compression integrity check failed for backup: $backup_file"
            return 1
        fi
    fi

    echo "  Listing contents of archive (first 5 files) to check readability..."
    tar -tf "$backup_file" | head -n 5
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  Archive content listing OK (first 5 files).${NC}"
        log_message "INFO" "Archive content listing OK for '$backup_file'."
    else
        echo -e "${RED}  Archive content listing FAILED. Backup might be corrupt.${NC}"
        log_message "ERROR" "Archive content listing FAILED for '$backup_file'."
        send_email_alert "Backup Warning: Corrupt Archive" "Archive content listing failed for backup: $backup_file"
        return 1
    fi

    echo -e "${GREEN}Backup verification completed for '$backup_file'.${NC}"
    log_message "SUCCESS" "Backup verification completed for '$backup_file'."
}


# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Backup Solution (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Full System Backup (tar, excludes /dev, /proc, /sys, etc.)${NC}"
    echo -e "${GREEN}2. Backup Specific Directory (tar)${NC}"
    echo -e "${GREEN}3. Sync/Incremental Backup (rsync)${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    # Ensure log directory and local backup directory exist
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi
    mkdir -p "$DEFAULT_LOCAL_BACKUP_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create default local backup directory $DEFAULT_LOCAL_BACKUP_DIR. Exiting.${NC}"
        log_message "ERROR" "Failed to create default local backup dir: $DEFAULT_LOCAL_BACKUP_DIR"
        exit 1
    fi

    log_message "INFO" "Backup system script started."
    check_root # This script *requires* root for full functionality.

    # Pre-build excludes string for tar
    EXCLUDES_TAR_STRING=$(build_tar_excludes)

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) perform_tar_backup "/" "Full System" ;;
            2)
                read -r -p "Enter source directory to backup (e.g., /home/user, /etc): " SRC_DIR
                if [ -d "$SRC_DIR" ]; then
                    perform_tar_backup "$SRC_DIR" "$(basename "$SRC_DIR")"
                else
                    echo -e "${RED}ERROR: Source directory '$SRC_DIR' not found. Please enter a valid path.${NC}"
                    log_message "ERROR" "Invalid source dir for specific backup: $SRC_DIR"
                    pause_script
                fi
                ;;
            3) perform_rsync_backup ;;
            0)
                echo -e "${CYAN}Exiting System Backup Solution. Goodbye!${NC}"
                log_message "INFO" "Backup system script exited."
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
