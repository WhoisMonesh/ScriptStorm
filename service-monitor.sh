#!/bin/bash

# service-monitor.sh - Monitors Critical Services
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script checks the status of predefined critical systemd services.
#              It logs their status and can optionally send email notifications
#              if a service is found to be down.

# --- Configuration ---
LOG_FILE="/var/log/service-monitor.log"  # Log file for service status and alerts
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="service-monitor@yourdomain.com" # Sender email for alerts
ALERT_ON_DOWN_ONLY="true" # Set to "true" to only alert when a service transitions to 'down'
                          # Set to "false" to alert every time a service is 'down'

# List of critical systemd services to monitor (space-separated)
# Examples: sshd apache2 nginx mariadb postgresql docker cron rsyslog systemd-journald
CRITICAL_SERVICES=(
    "sshd"
    "apache2"
    "mysql" # Or mariadb, postgresql etc.
    "cron"
    "nginx" # Add if you use nginx instead of apache2, or both
    "docker" # If you use docker
)

# --- Colors for better readability (for console output) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log_message() {
    local type="$1" # INFO, ALERT, ERROR, SUCCESS
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

    # Using 'mail' command. Ensure 'mailutils' or ' heirloom-mailx' is installed.
    echo "$body" | mail -s "$subject" -r "$SENDER_EMAIL" "$NOTIFICATION_EMAIL"
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Email alert sent: '$subject'"
    else
        log_message "ERROR" "Failed to send email alert: '$subject'. Check mail configuration."
        echo -e "${RED}ERROR: Failed to send email alert. Check 'mail' command setup.${NC}"
    fi
}

# --- Service Monitoring Logic ---

monitor_service() {
    local service_name="$1"
    local current_status

    # Check if the service exists
    systemctl status "$service_name" &>/dev/null
    if [ $? -ne 0 ]; then
        current_status="${RED}UNKNOWN${NC}"
        log_message "ERROR" "Service '$service_name' does not exist or systemctl failed."
        send_email_alert "Service Monitor Alert: UNKNOWN Service $service_name" \
                         "The service '$service_name' could not be found or checked by systemctl on $(hostname)."
        echo -e "${YELLOW}Service: ${service_name} - Status: ${current_status}${NC}"
        return 1
    fi

    # Get the active state of the service (e.g., active, inactive, failed)
    current_active_state=$(systemctl is-active "$service_name" 2>/dev/null)
    current_sub_state=$(systemctl show -p SubState --value "$service_name" 2>/dev/null)

    # Determine status for logging/display
    if [ "$current_active_state" == "active" ]; then
        current_status="${GREEN}RUNNING${NC}"
    elif [ "$current_active_state" == "inactive" ]; then
        current_status="${YELLOW}INACTIVE${NC}"
    elif [ "$current_active_state" == "failed" ]; then
        current_status="${RED}FAILED${NC}"
    else
        current_status="${YELLOW}UNKNOWN (${current_active_state})${NC}"
    fi

    echo -e "Service: ${service_name} - Status: ${current_status} (Active: ${current_active_state}, Sub: ${current_sub_state})${NC}"

    # Check against previous status to avoid spamming alerts if ALERT_ON_DOWN_ONLY is true
    local previous_status_file="/tmp/service_status_${service_name}.last"
    local previous_active_state=""
    if [ -f "$previous_status_file" ]; then
        previous_active_state=$(cat "$previous_status_file")
    fi

    # If service is not active (down/failed/inactive)
    if [ "$current_active_state" != "active" ]; then
        log_message "ALERT" "Service '$service_name' is ${current_active_state} (SubState: ${current_sub_state})."
        if [ "$ALERT_ON_DOWN_ONLY" == "true" ]; then
            if [ "$previous_active_state" == "active" ] || [ ! -f "$previous_status_file" ]; then
                # Only send alert if it just went down, or if it's the first check
                send_email_alert "Service Monitor Alert: $service_name is ${current_active_state}!" \
                                 "The service '$service_name' on $(hostname) is currently ${current_active_state} (SubState: ${current_sub_state}). Please investigate."
            else
                log_message "INFO" "Service '$service_name' is still ${current_active_state}. No new alert sent (ALERT_ON_DOWN_ONLY is true)."
            fi
        else
            # Always send alert if down (ALERT_ON_DOWN_ONLY is false)
            send_email_alert "Service Monitor Alert: $service_name is ${current_active_state}!" \
                             "The service '$service_name' on $(hostname) is currently ${current_active_state} (SubState: ${current_sub_state}). Please investigate."
        fi
    elif [ "$current_active_state" == "active" ] && [ "$previous_active_state" != "active" ]; then
        # If service was previously down and is now active, send a recovery alert
        log_message "INFO" "Service '$service_name' has recovered and is now active."
        send_email_alert "Service Monitor Alert: $service_name has RECOVERED!" \
                         "The service '$service_name' on $(hostname) has recovered and is now active."
    else
        log_message "INFO" "Service '$service_name' is active."
    fi

    # Save current status for next check
    echo "$current_active_state" > "$previous_status_file"
}

# --- Main Script Execution ---

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    echo -e "${CYAN}Starting Critical Service Monitoring...${NC}"
    log_message "INFO" "Service monitor script started."

    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${BLUE}>>> Critical Service Status Check <<<${NC}"
    echo -e "${BLUE}================================================================${NC}"

    if [ ${#CRITICAL_SERVICES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No critical services configured to monitor.${NC}"
        echo -e "${YELLOW}Please add service names to the CRITICAL_SERVICES array in the script.${NC}"
        log_message "WARN" "No critical services configured for monitoring."
    else
        for service in "${CRITICAL_SERVICES[@]}"; do
            monitor_service "$service"
            echo "---"
        done
    fi

    echo -e "\n${CYAN}Critical Service Monitoring Completed.${NC}"
    log_message "INFO" "Service monitor script completed."
    echo -e "${CYAN}Detailed logs are available at: ${LOG_FILE}${NC}"
}

# --- Script Entry Point ---
if [[ "$EUID" -eq 0 ]]; then
    main
else
    echo -e "${RED}ERROR: This script must be run as root to check service status.${NC}"
    log_message "ERROR" "Attempted to run service-monitor.sh as non-root user."
    exit 1
fi
