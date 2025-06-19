#!/bin/bash

# disk-analyzer.sh - Analyzes Disk Usage
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides comprehensive disk usage analysis, including
#              filesystem usage, top directories by size, and inode usage.
#              It offers options for interactive exploration.

# --- Configuration ---
LOG_FILE="/var/log/disk-analyzer.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"
DEFAULT_DU_DEPTH=2 # Default depth for 'du' analysis
TOP_N_DIRS=10      # Number of top directories to show by size

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
        echo -e "${YELLOW}WARNING: Running as non-root user. Some information may be restricted (e.g., inaccessible directories for 'du').${NC}"
        log_message "WARN" "Attempted to run script as non-root user."
    fi
}

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

# --- Disk Analysis Functions ---

analyze_filesystem_usage() {
    print_subsection "Filesystem Disk Usage Overview"
    if check_command "df"; then
        echo "Displays disk space usage for mounted filesystems."
        echo -e "${CYAN}-------------------------------------------------------------------------------------------------------------------${NC}"
        # Exclude common pseudo-filesystems like tmpfs, devtmpfs, sysfs, proc, etc.
        df -h -x tmpfs -x devtmpfs -x fuse.lxcfs -x overlay -x cgroup -x rpc_pipefs -x autofs -x debugfs -x securityfs -x pstore -x binfmt_misc 2>/dev/null \
        || log_message "ERROR" "df command failed. Check permissions or 'df' utility."
        echo -e "${CYAN}-------------------------------------------------------------------------------------------------------------------${NC}"
        log_message "INFO" "Filesystem disk usage analyzed."
    else
        echo -e "${RED}ERROR: 'df' command not found. Cannot analyze filesystem usage.${NC}"
        log_message "ERROR" "'df' command not found."
    fi
    pause_script
}

analyze_directory_usage() {
    print_subsection "Analyze Directory Space Usage (Top $TOP_N_DIRS)"
    local target_path=$(read_user_input "Enter path to analyze (e.g., /, /var, /home/user, default: /)" "/")
    local du_depth=$(read_user_input "Enter directory depth for analysis (default: $DEFAULT_DU_DEPTH)" "$DEFAULT_DU_DEPTH")

    if [ ! -d "$target_path" ]; then
        echo -e "${RED}ERROR: Path '$target_path' does not exist or is not a directory.${NC}"
        log_message "ERROR" "Invalid path for du analysis: $target_path"
        pause_script
        return 1
    fi

    echo -e "${CYAN}Analyzing '$target_path' with depth $du_depth...${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    if check_command "du"; then
        # -h: human-readable, -d: depth, -c: total, -s: summarize (for subdirs), --exclude: skip mount points for nested du
        # This command is tricky for depth and total. Let's simplify for top dirs.
        # Find top N largest directories at specified depth
        sudo du -ah --max-depth="$du_depth" "$target_path" 2>/dev/null | sort -rh | head -n "$TOP_N_DIRS" \
        || log_message "ERROR" "du command failed for path '$target_path'. Check permissions or 'du' utility."
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        log_message "INFO" "Directory usage analyzed for '$target_path' (depth $du_depth)."
    else
        echo -e "${RED}ERROR: 'du' command not found. Cannot analyze directory usage.${NC}"
        log_message "ERROR" "'du' command not found."
    fi
    pause_script
}

analyze_inode_usage() {
    print_subsection "Filesystem Inode Usage"
    if check_command "df"; then
        echo "Inodes represent the number of files and directories. High inode usage can prevent new files."
        echo -e "${CYAN}-------------------------------------------------------------------------------------------------------------------${NC}"
        df -i -x tmpfs -x devtmpfs -x fuse.lxcfs -x overlay -x cgroup -x rpc_pipefs -x autofs -x debugfs -x securityfs -x pstore -x binfmt_misc 2>/dev/null \
        || log_message "ERROR" "df -i command failed. Check permissions or 'df' utility."
        echo -e "${CYAN}-------------------------------------------------------------------------------------------------------------------${NC}"
        log_message "INFO" "Inode usage analyzed."
    else
        echo -e "${RED}ERROR: 'df' command not found. Cannot analyze inode usage.${NC}"
        log_message "ERROR" "'df' command not found."
    fi
    pause_script
}

find_large_files() {
    print_subsection "Find Largest Files (Top $TOP_N_DIRS)"
    local target_path=$(read_user_input "Enter starting path to search (e.g., /, /var/log, default: /)" "/")

    if [ ! -d "$target_path" ]; then
        echo -e "${RED}ERROR: Path '$target_path' does not exist or is not a directory.${NC}"
        log_message "ERROR" "Invalid path for large file search: $target_path"
        pause_script
        return 1
    fi

    echo -e "${CYAN}Searching for top $TOP_N_DIRS largest files in '$target_path'...${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    if check_command "find"; then
        # -xdev: stay on same filesystem (prevents crossing mount points)
        # -type f: find files only
        # -print0: null-separated output for safe processing of filenames with spaces/special chars
        # sort -zrh: null-separated, human-readable, reverse sort
        # head -zn: null-separated, take top N
        # xargs -0 du -h: process null-separated list with du -h for human-readable sizes
        find "$target_path" -xdev -type f -print0 2>/dev/null | xargs -0 du -h 2>/dev/null | sort -rh | head -n "$TOP_N_DIRS" \
        || log_message "ERROR" "find or du failed for large file search in '$target_path'. Check permissions."
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        log_message "INFO" "Largest files search completed in '$target_path'."
    else
        echo -e "${RED}ERROR: 'find' command not found. Cannot find large files.${NC}"
        log_message "ERROR" "'find' command not found."
    fi
    pause_script
}

# --- Main Script Logic ---

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

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Disk Usage Analyzer (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Filesystem Disk Usage (df -h)${NC}"
    echo -e "${GREEN}2. Analyze Directory Space Usage (du)${NC}"
    echo -e "${GREEN}3. Filesystem Inode Usage (df -i)${NC}"
    echo -e "${GREEN}4. Find Top Largest Files${NC}"
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

    log_message "INFO" "Disk analyzer script started."
    check_root # Check for root, but allow non-root to run with warnings.

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) analyze_filesystem_usage ;;
            2) analyze_directory_usage ;;
            3) analyze_inode_usage ;;
            4) find_large_files ;;
            0)
                echo -e "${CYAN}Exiting Disk Usage Analyzer. Goodbye!${NC}"
                log_message "INFO" "Disk analyzer script exited."
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
