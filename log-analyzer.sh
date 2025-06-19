#!/bin/bash

# log-analyzer.sh - Parses and Analyzes System Logs
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides a menu-driven interface to parse and analyze
#              various system log files. It can filter for specific keywords,
#              show recent logs, summarize errors/warnings, and analyze failed logins.

# --- Configuration ---
LOG_FILE="/var/log/log-analyzer.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Common system log files to analyze (add/remove as needed)
# Order matters for "Analyze All Common Logs"
declare -a COMMON_LOG_FILES=(
    "/var/log/syslog"           # Debian/Ubuntu general system messages
    "/var/log/messages"         # RHEL/CentOS/Fedora general system messages
    "/var/log/auth.log"         # Debian/Ubuntu authentication logs
    "/var/log/secure"           # RHEL/CentOS/Fedora authentication logs
    "/var/log/kern.log"         # Kernel logs
    "/var/log/boot.log"         # Boot messages
    "/var/log/faillog"          # Failed login attempts (binary, requires 'faillog -a')
    "/var/log/dpkg.log"         # Debian package manager logs
    "/var/log/yum.log"          # RHEL/CentOS/Fedora package manager logs
    # Add application-specific logs if desired, e.g.:
    # "/var/log/apache2/error.log"
    # "/var/log/nginx/error.log"
    # "/var/log/mysql/error.log"
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
        echo -e "${YELLOW}WARNING: Running as non-root user. Some log files may not be readable.${NC}"
        log_message "WARN" "Attempted to run script as non-root user."
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

# --- Log Analysis Functions ---

view_recent_logs() {
    print_subsection "View Recent Logs"
    local log_path=$(read_user_input "Enter log file path (e.g., /var/log/syslog)" "")
    local num_lines=$(read_user_input "Number of lines to display (default: 20)" "20")

    if [ -z "$log_path" ]; then
        echo -e "${RED}ERROR: Log file path cannot be empty.${NC}"
        log_message "ERROR" "View recent logs failed: log path empty."
        pause_script
        return 1
    fi

    if [ ! -f "$log_path" ]; then
        echo -e "${RED}ERROR: Log file '$log_path' not found or is not a regular file.${NC}"
        log_message "ERROR" "Log file '$log_path' not found for recent view."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Displaying last $num_lines lines of '$log_path':${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    tail -n "$num_lines" "$log_path" 2>/dev/null || log_message "ERROR" "Failed to read '$log_path'."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Viewed last $num_lines lines of '$log_path'."
    pause_script
}

filter_logs_by_keyword() {
    print_subsection "Filter Logs by Keyword"
    local log_path=$(read_user_input "Enter log file path (e.g., /var/log/auth.log)" "")
    local keyword=$(read_user_input "Enter keyword to search for" "")
    local num_lines=$(read_user_input "Number of matching lines to display (default: all)" "")

    if [ -z "$log_path" ]; then
        echo -e "${RED}ERROR: Log file path cannot be empty.${NC}"
        log_message "ERROR" "Filter logs failed: log path empty."
        pause_script
        return 1
    fi
    if [ -z "$keyword" ]; then
        echo -e "${RED}ERROR: Keyword cannot be empty.${NC}"
        log_message "ERROR" "Filter logs failed: keyword empty."
        pause_script
        return 1
    fi
    if [ ! -f "$log_path" ]; then
        echo -e "${RED}ERROR: Log file '$log_path' not found or is not a regular file.${NC}"
        log_message "ERROR" "Log file '$log_path' not found for keyword filter."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Searching for '$keyword' in '$log_path':${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    if [ -n "$num_lines" ]; then
        grep -i "$keyword" "$log_path" 2>/dev/null | head -n "$num_lines" || log_message "ERROR" "Grep failed on '$log_path'."
    else
        grep -i "$keyword" "$log_path" 2>/dev/null || log_message "ERROR" "Grep failed on '$log_path'."
    fi
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Filtered '$log_path' for keyword '$keyword'."
    pause_script
}

summarize_errors_warnings() {
    print_subsection "Summarize Errors and Warnings"
    local log_path=$(read_user_input "Enter log file path (e.g., /var/log/syslog) or leave empty for all common logs" "")

    local files_to_scan
    if [ -z "$log_path" ]; then
        echo -e "${CYAN}Analyzing common system logs for 'error|warn|fail' keywords...${NC}"
        files_to_scan=("${COMMON_LOG_FILES[@]}")
    else
        if [ ! -f "$log_path" ]; then
            echo -e "${RED}ERROR: Log file '$log_path' not found or is not a regular file.${NC}"
            log_message "ERROR" "Log file '$log_path' not found for error/warning summary."
            pause_script
            return 1
        fi
        echo -e "${CYAN}Analyzing '$log_path' for 'error|warn|fail' keywords...${NC}"
        files_to_scan=("$log_path")
    fi

    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    for file in "${files_to_scan[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${MAGENTA}File: $file${NC}"
            # Count and display errors/warnings. Using 'grep -c' for count and then showing unique lines
            local errors=$(grep -i -E 'error|fail|denied' "$file" 2>/dev/null | wc -l)
            local warnings=$(grep -i -E 'warn|warning' "$file" 2>/dev/null | wc -l)

            echo "  Errors/Failures/Denied: $errors"
            echo "  Warnings: $warnings"
            if (( errors > 0 )); then
                echo "  Recent Errors (last 5 unique):"
                grep -i -E 'error|fail|denied' "$file" 2>/dev/null | tail -n 10 | sort -u | head -n 5 || echo "    (none)"
            fi
            if (( warnings > 0 )); then
                echo "  Recent Warnings (last 5 unique):"
                grep -i -E 'warn|warning' "$file" 2>/dev/null | tail -n 10 | sort -u | head -n 5 || echo "    (none)"
            fi
            echo -e "${CYAN}---${NC}"
            log_message "INFO" "Summarized errors/warnings for '$file'."
        else
            log_message "WARN" "Skipping non-existent or unreadable log file: $file"
        fi
    done
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    pause_script
}

analyze_failed_logins() {
    print_subsection "Analyze Failed Login Attempts"
    local auth_log_path="/var/log/auth.log" # Default for Debian/Ubuntu
    if [ -f "/var/log/secure" ]; then        # For RHEL/CentOS/Fedora
        auth_log_path="/var/log/secure"
    fi

    echo -e "${CYAN}Analyzing failed login attempts from '$auth_log_path' or 'faillog' command...${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    # Try 'faillog' command first, as it's more accurate for persistent failed logins
    if check_command "faillog"; then
        echo "Summary from faillog:"
        faillog -a -u -t 7 # All users, display last 7 days
        echo ""
    else
        log_message "WARN" "'faillog' command not found. Falling back to parsing auth log."
        echo -e "${YELLOW}WARNING: 'faillog' command not found. Install 'util-linux' or 'shadow-utils' package for more accurate results.${NC}"
    fi

    # Parse auth log for general failed attempts
    if [ -f "$auth_log_path" ]; then
        echo "Recent failed SSH/authentication attempts from $auth_log_path:"
        grep -i -E 'failed|invalid|disconnect' "$auth_log_path" | grep -i -E 'ssh|password|authentication' | tail -n 20 \
        || log_message "WARN" "No recent failed logins found in '$auth_log_path'."
    else
        echo -e "${RED}ERROR: Authentication log '$auth_log_path' not found.${NC}"
        log_message "ERROR" "Authentication log '$auth_log_path' not found."
    fi
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Analyzed failed login attempts."
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Log Analyzer (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. View Recent Logs from a Specific File${NC}"
    echo -e "${GREEN}2. Filter Logs by Keyword from a Specific File${NC}"
    echo -e "${GREEN}3. Summarize Errors and Warnings (from selected or common logs)${NC}"
    echo -e "${GREEN}4. Analyze Failed Login Attempts${NC}"
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

    log_message "INFO" "Log analyzer script started."
    check_root # Check for root, but allow non-root to run with warnings.

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) view_recent_logs ;;
            2) filter_logs_by_keyword ;;
            3) summarize_errors_warnings ;;
            4) analyze_failed_logins ;;
            0)
                echo -e "${CYAN}Exiting System Log Analyzer. Goodbye!${NC}"
                log_message "INFO" "Log analyzer script exited."
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
