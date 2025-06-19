#!/bin/bash

# failed-logins.sh - Monitors Failed Login Attempts
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script monitors failed login attempts by analyzing system logs
#              (/var/log/auth.log or /var/log/secure), /var/log/btmp, and 'faillog' data.
#              It provides summaries by user and IP, lists recent attempts,
#              and can send alerts if a high number of failures is detected.

# --- Configuration ---
LOG_FILE="/var/log/failed-logins.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Paths to common authentication log files
AUTH_LOG_DEBIAN="/var/log/auth.log"
AUTH_LOG_RHEL="/var/log/secure"
BTMP_FILE="/var/log/btmp" # Binary file for failed logins, read by 'lastb'

# Threshold for sending an alert (number of failed attempts from one IP/user in recent analysis)
ALERT_THRESHOLD=10

# Number of recent failed login attempts to display
NUM_RECENT_ATTEMPTS=20

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="security-monitor@yourdomain.com" # Sender email for alerts

# --- Colors for better readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Global Variables ---
AUTH_LOG_FILE="" # Determined dynamically

# --- Helper Functions ---

log_message() {
    local type="$1" # INFO, WARN, ERROR, SUCCESS, ALERT
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
        echo -e "${RED}ERROR: This script must be run as root to access logs and use tools like 'lastb' or 'faillog'.${NC}"
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

detect_auth_log() {
    if [ -f "$AUTH_LOG_DEBIAN" ]; then
        AUTH_LOG_FILE="$AUTH_LOG_DEBIAN"
    elif [ -f "$AUTH_LOG_RHEL" ]; then
        AUTH_LOG_FILE="$AUTH_LOG_RHEL"
    fi

    if [ -z "$AUTH_LOG_FILE" ]; then
        echo -e "${RED}ERROR: Neither '$AUTH_LOG_DEBIAN' nor '$AUTH_LOG_RHEL' found.${NC}"
        log_message "ERROR" "No authentication log file found."
        pause_script
        exit 1
    fi
    log_message "INFO" "Detected auth log: $AUTH_LOG_FILE."
}

# --- Analysis Functions ---

get_failed_login_summary() {
    print_subsection "Failed Login Summary (from $AUTH_LOG_FILE and $BTMP_FILE)"
    local failed_attempts_total=0
    local failed_users_summary=""
    local failed_ips_summary=""
    local alert_triggered=false

    echo -e "${CYAN}Analyzing failed attempts from $AUTH_LOG_FILE...${NC}"
    if [ -f "$AUTH_LOG_FILE" ]; then
        local log_output=$(grep -iE 'failed password|authentication failure|invalid user' "$AUTH_LOG_FILE" 2>/dev/null)
        failed_attempts_total=$(echo "$log_output" | wc -l)

        echo -e "\n${MAGENTA}Top Failed Users (from auth log):${NC}"
        if [ -n "$log_output" ]; then
            failed_users_summary=$(echo "$log_output" | awk '{for(i=1;i<=NF;i++) if($i=="user" && $(i+1)!="") print $(i+1)}' | sort | uniq -c | sort -nr | head -n 10)
            if [ -z "$failed_users_summary" ]; then # Fallback for different log formats
                failed_users_summary=$(echo "$log_output" | grep -oE 'user [^ ]+' | awk '{print $2}' | sort | uniq -c | sort -nr | head -n 10)
            fi
            echo "$failed_users_summary"
            
            echo -e "\n${MAGENTA}Top Failed Source IPs (from auth log):${NC}"
            failed_ips_summary=$(echo "$log_output" | grep -oE '(from |rhost=)[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $NF}' | sort | uniq -c | sort -nr | head -n 10)
            echo "$failed_ips_summary"
        else
            echo -e "${YELLOW}No failed login attempts found in $AUTH_LOG_FILE for common patterns.${NC}"
        fi
    else
        echo -e "${YELLOW}Auth log file '$AUTH_LOG_FILE' not found.${NC}"
    fi

    echo -e "\n${CYAN}Analyzing failed attempts from $BTMP_FILE (via lastb)...${NC}"
    if check_command "lastb" && [ -f "$BTMP_FILE" ]; then
        local lastb_output=$(sudo lastb -aF --fulltimes 2>/dev/null)
        local lastb_total=$(echo "$lastb_output" | wc -l)
        if [ -n "$lastb_output" ]; then
            failed_attempts_total=$((failed_attempts_total + lastb_total))
            echo -e "\n${MAGENTA}Top Failed Users (from lastb):${NC}"
            echo "$lastb_output" | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 10
            echo -e "\n${MAGENTA}Top Failed Source IPs (from lastb):${NC}"
            echo "$lastb_output" | awk '{print $NF}' | sort | uniq -c | sort -nr | head -n 10
        else
            echo -e "${YELLOW}No failed login attempts found in $BTMP_FILE.${NC}"
        fi
    else
        echo -e "${YELLOW}Command 'lastb' not found or '$BTMP_FILE' not present/readable.${NC}"
        log_message "WARN" "'lastb' not found or $BTMP_FILE not readable."
    fi

    echo -e "\n${CYAN}-------------------------------------------------------------------${NC}"
    echo -e "${CYAN}Total failed login attempts found (recent logs): ${failed_attempts_total}${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Failed login summary collected. Total: $failed_attempts_total."

    # Check for alerts
    if (( failed_attempts_total >= ALERT_THRESHOLD )); then
        log_message "ALERT" "High number of failed login attempts detected: $failed_attempts_total. Threshold: $ALERT_THRESHOLD."
        send_email_alert "SECURITY ALERT: High Failed Logins on $(hostname)" \
                         "Total failed login attempts: $failed_attempts_total (Threshold: $ALERT_THRESHOLD).\n\n" \
                         "Top Users:\n$failed_users_summary\n\n" \
                         "Top IPs:\n$failed_ips_summary"
    fi
    pause_script
}

view_recent_failed_attempts() {
    print_subsection "Recent Failed Login Attempts (Last $NUM_RECENT_ATTEMPTS from auth log)"
    echo -e "${CYAN}Showing most recent failed attempts from $AUTH_LOG_FILE:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    if [ -f "$AUTH_LOG_FILE" ]; then
        grep -iE 'failed password|authentication failure|invalid user' "$AUTH_LOG_FILE" | tail -n "$NUM_RECENT_ATTEMPTS" \
        || echo -e "${YELLOW}No recent failed attempts found in $AUTH_LOG_FILE.${NC}"
    else
        echo -e "${RED}Auth log file '$AUTH_LOG_FILE' not found.${NC}"
        log_message "ERROR" "Auth log file '$AUTH_LOG_FILE' not found for recent view."
    fi
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Viewed recent failed attempts."
    pause_script
}

check_faillog_stats() {
    print_subsection "User-specific Failed Login Stats (faillog)"
    if ! check_command "faillog"; then
        echo -e "${RED}ERROR: 'faillog' command not found. Install 'shadow-utils' (RHEL/CentOS) or 'login' (Debian/Ubuntu) package.${NC}"
        log_message "ERROR" "'faillog' command not found."
        pause_script
        return 1
    fi
    echo -e "${CYAN}Displaying failed login counts per user from faillog:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    sudo faillog -a -u -t 365 # Show all users, -u for per-user, -t for last N days (365 for a year)
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to run 'faillog -a'. Check permissions.${NC}"
        log_message "ERROR" "Failed to run 'faillog -a'."
    fi
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Faillog stats checked."
    pause_script
}

reset_faillog_count() {
    print_subsection "Reset Failed Login Count for User (faillog -r)"
    if ! check_command "faillog"; then
        echo -e "${RED}ERROR: 'faillog' command not found. Cannot reset counts.${NC}"
        log_message "ERROR" "'faillog' command not found for reset."
        pause_script
        return 1
    fi

    local username=$(read_user_input "Enter username to reset failed login count for" "")
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        log_message "ERROR" "Reset faillog failed: Username empty."
        pause_script
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}ERROR: User '$username' does not exist.${NC}"
        log_message "ERROR" "Reset faillog failed: User '$username' does not exist."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Current failed login stats for '$username':${NC}"
    sudo faillog -u "$username" 2>/dev/null || log_message "WARN" "Failed to get current faillog for '$username'."

    if confirm_action "Are you sure you want to reset failed login count for '$username'?"; then
        sudo faillog -r -u "$username"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Failed login count for '$username' reset successfully.${NC}"
            log_message "SUCCESS" "Failed login count for '$username' reset."
            send_email_alert "Security Action: Failed Login Reset" "Failed login count for user '$username' reset by script on $(hostname)."
        else
            echo -e "${RED}ERROR: Failed to reset failed login count for '$username'.${NC}"
            log_message "ERROR" "Failed to reset faillog for '$username'."
        fi
    fi
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Failed Login Monitor (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}Auth Log File: $AUTH_LOG_FILE${NC}"
    echo -e "${MAGENTA}Alert Threshold: $ALERT_THRESHOLD failed attempts${NC}"
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Get Failed Login Summary (Users & IPs)${NC}"
    echo -e "${GREEN}2. View Recent Failed Attempts (Raw Log)${NC}"
    echo -e "${GREEN}3. Check User-specific Failed Login Stats (faillog)${NC}"
    echo -e "${GREEN}4. Reset Failed Login Count for a User${NC}"
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

    log_message "INFO" "Failed logins monitor script started."
    check_root # This script *requires* root.
    detect_auth_log # Determine the correct auth log path

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) get_failed_login_summary ;;
            2) view_recent_failed_attempts ;;
            3) check_faillog_stats ;;
            4) reset_faillog_count ;;
            0)
                echo -e "${CYAN}Exiting Failed Login Monitor. Goodbye!${NC}"
                log_message "INFO" "Failed logins monitor script exited."
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
