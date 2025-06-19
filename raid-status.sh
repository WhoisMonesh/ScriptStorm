#!/bin/bash
# raid-status.sh - Checks RAID array health
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script checks the health of RAID arrays managed by mdadm.
#              It can list arrays, show detailed status, and send email alerts
#              if a RAID array is degraded or has a failed disk.

# --- Configuration ---
LOG_FILE="/var/log/raid-status.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="raid-monitor@yourdomain.com" # Sender email for alerts

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

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

# --- RAID Monitoring Functions ---
check_mdadm_installed() {
    if ! check_command "mdadm"; then
        echo -e "${RED}ERROR: 'mdadm' package not found.${NC}"
        echo -e "${RED}Please install it (e.g., 'sudo apt install mdadm' or 'sudo dnf install mdadm').${NC}"
        log_message "ERROR" "'mdadm' command not found."
        return 1
    fi
    log_message "INFO" "'mdadm' command found."
    return 0
}

list_raid_arrays() {
    print_subsection "Detected RAID Arrays"
    if ! check_mdadm_installed; then
        return 1
    fi

    local arrays=$(sudo mdadm --detail --scan 2>/dev/null | awk '{print $2}')
    if [ -z "$arrays" ]; then
        echo -e "${YELLOW}No RAID arrays detected. Ensure mdadm is configured and arrays are assembled.${NC}"
        log_message "INFO" "No RAID arrays detected."
        return 1
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${MAGENTA}Device${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo "$arrays" | while read -r array; do
        echo "$array"
    done
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Listed detected RAID arrays."
}

check_raid_status() {
    print_subsection "Detailed RAID Array Status"
    if ! check_mdadm_installed; then
        return 1
    fi

    local arrays=$(sudo mdadm --detail --scan 2>/dev/null | awk '{print $2}')
    if [ -z "$arrays" ]; then
        echo -e "${YELLOW}No RAID arrays found to check status.${NC}"
        log_message "WARN" "No RAID arrays found for detailed status check."
        return 1
    fi

    local overall_health="OK"
    local alert_message=""

    echo "$arrays" | while read -r array; do
        echo -e "\n${CYAN}--- Status for ${array} ---${NC}"
        local details=$(sudo mdadm --detail "$array" 2>&1)
        echo "$details"

        # Check for 'State : clean', 'active', 'recovering', 'resyncing'
        if echo "$details" | grep -q "State : clean"; then
            echo -e "${GREEN}Status: CLEAN - Array is healthy.${NC}"
            log_message "INFO" "$array: Status is CLEAN."
        elif echo "$details" | grep -q "State : active"; then
            # Active usually means clean, but sometimes it can be active, degraded.
            # We need to specifically look for 'degraded' or 'failed' state.
            if echo "$details" | grep -q "State : active, degraded"; then
                echo -e "${RED}Status: DEGRADED - Array is degraded! One or more drives may have failed.${NC}"
                log_message "ALERT" "$array: CRITICAL - Array is DEGRADED."
                overall_health="DEGRADED"
                alert_message+="\nCRITICAL: RAID array $array is DEGRADED on $(hostname)! Please investigate immediately.\n$details\n"
            elif echo "$details" | grep -q "State : active, FAILED"; then
                echo -e "${RED}Status: FAILED - Array has failed drives! Data loss possible.${NC}"
                log_message "ALERT" "$array: CRITICAL - Array has FAILED drives."
                overall_health="FAILED"
                alert_message+="\nCRITICAL: RAID array $array has FAILED drives on $(hostname)! Data loss probable.\n$details\n"
            else
                echo -e "${GREEN}Status: ACTIVE - Array is healthy (possibly resyncing/recovering).${NC}"
                log_message "INFO" "$array: Status is ACTIVE."
            fi
        elif echo "$details" | grep -q "State : rebuilding"; then
            echo -e "${YELLOW}Status: REBUILDING - Array is currently rebuilding.${NC}"
            log_message "INFO" "$array: Status is REBUILDING."
        else
            echo -e "${RED}Status: UNKNOWN/POTENTIALLY FAULTY - Investigate this array!${NC}"
            log_message "ERROR" "$array: Status is UNKNOWN/POTENTIALLY FAULTY. Details: $details"
            overall_health="UNKNOWN"
            alert_message+="\nWARNING: RAID array $array has UNKNOWN/POTENTIALLY FAULTY status on $(hostname)! Please investigate.\n$details\n"
        fi

        # Check for individual device states
        local failed_devices=$(echo "$details" | grep -E '\[[FU]\]' | awk '{print $NF}')
        local spare_devices=$(echo "$details" | grep -E '\[S\]' | awk '{print $NF}')

        if [ -n "$failed_devices" ]; then
            echo -e "${RED}Failed Devices: ${failed_devices}${NC}"
            overall_health="DEGRADED" # Or FAILED, depending on exact count
            alert_message+="\nFAILED DEVICES DETECTED in $array: $failed_devices\n"
        fi

        if [ -n "$spare_devices" ]; then
            echo -e "${YELLOW}Spare Devices: ${spare_devices}${NC}"
        fi
    done

    if [ "$overall_health" != "OK" ] && [ -n "$alert_message" ]; then
        send_email_alert "RAID ALERT: $(hostname) - RAID Health: $overall_health" "$alert_message"
    elif [ "$overall_health" == "OK" ]; then
        log_message "SUCCESS" "All RAID arrays are healthy."
    fi
}

explain_raid_monitoring() {
    print_subsection "About RAID Monitoring"
    echo -e "${CYAN}Why monitor RAID array health?${NC}"
    echo "  - RAID (Redundant Array of Independent Disks) provides data redundancy"
    echo "    and/or improved performance by combining multiple physical disk drives"
    echo "    into one logical unit."
    echo "  - Monitoring is critical to detect drive failures early, allowing you to"
    echo "    replace faulty disks and rebuild the array before data loss occurs."
    echo "  - A degraded array is running without full redundancy, putting your data"
    echo "    at higher risk in case of another drive failure."
    echo ""
    echo -e "${CYAN}Key tool used: ${NC}"
    echo "  - ${GREEN}mdadm:${NC} A Linux utility used to manage and monitor software RAID devices."
    echo "    It allows creation, management, and monitoring of RAID arrays like RAID0, RAID1, RAID5, etc."
    echo ""
    echo -e "${CYAN}Common RAID States:${NC}"
    echo "  - ${GREEN}clean:${NC} The array is healthy and all components are functioning correctly."
    echo "  - ${YELLOW}rebuilding/resyncing:${NC} The array is in the process of rebuilding"
    echo "    after a disk replacement or initial synchronization."
    echo "  - ${RED}degraded:${NC} One or more disks have failed, and the array is running"
    echo "    with reduced redundancy. Immediate action is required!"
    echo "  - ${RED}failed:${NC} Multiple disks have failed, leading to potential data loss."
    echo "    Critical intervention is needed."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "RAID monitoring explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> RAID Array Health Monitor (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. List Detected RAID Arrays${NC}"
    echo -e "${GREEN}2. Check Detailed RAID Array Status${NC}"
    echo -e "${GREEN}3. About RAID Monitoring & Troubleshooting${NC}"
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

    log_message "INFO" "RAID monitor script started."

    # Pre-check essential command
    if ! check_mdadm_installed; then
        log_message "ERROR" "mdadm not found. Exiting."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) list_raid_arrays; pause_script ;;
            2) check_raid_status; pause_script ;;
            3) explain_raid_monitoring; pause_script ;;
            0)
                echo -e "${CYAN}Exiting RAID Array Health Monitor. Goodbye!${NC}"
                log_message "INFO" "RAID monitor script exited."
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
