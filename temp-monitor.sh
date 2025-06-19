#!/bin/bash

# temp-monitor.sh - System Temperature Monitoring
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script monitors system temperatures (CPU, Disk, etc.) using
#              lm-sensors and smartmontools. It displays current readings,
#              can continuously monitor, and sends alerts if thresholds are exceeded.

# --- Configuration ---
LOG_FILE="/var/log/temp-monitor.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Temperature Thresholds (in Celsius)
CPU_WARN_TEMP=70  # Warning threshold for CPU
CPU_CRIT_TEMP=85  # Critical threshold for CPU
DISK_WARN_TEMP=45 # Warning threshold for Disks
DISK_CRIT_TEMP=55 # Critical threshold for Disks

# Continuous monitoring refresh interval (seconds)
REFRESH_INTERVAL=5

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="temp-monitor@yourdomain.com" # Sender email for alerts

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

# Root is recommended for smartctl and more comprehensive sensor detection
check_root_for_optional_ops() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${YELLOW}WARNING: Running as non-root user. Disk temperatures (smartctl) may not be available.${NC}"
        log_message "WARN" "Running as non-root. Disk temp info may be limited."
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

# --- Temperature Gathering Functions ---

check_sensors_installed() {
    if ! check_command "sensors"; then
        echo -e "${RED}ERROR: 'lm-sensors' package (command 'sensors') not found.${NC}"
        echo -e "${RED}Please install it (e.g., 'sudo apt install lm-sensors' or 'sudo dnf install lm_sensors').${NC}"
        log_message "ERROR" "'sensors' command not found."
        return 1
    fi
    log_message "INFO" "'sensors' command found."

    # Check if sensors are configured/detected
    if ! sensors 2>/dev/null | grep -qE "(Core|Package|CPU) Temp:"; then
        echo -e "${YELLOW}WARNING: 'sensors' command found, but no CPU/core temperatures detected.${NC}"
        echo -e "${YELLOW}You may need to run 'sudo sensors-detect' and reboot to configure sensors.${NC}"
        log_message "WARN" "'sensors' found but no CPU temps detected. Suggest 'sensors-detect'."
        # Do not exit, continue for other temps (e.g., disk)
    fi
    return 0
}

check_smartctl_installed() {
    if ! check_command "smartctl"; then
        echo -e "${YELLOW}WARNING: 'smartmontools' package (command 'smartctl') not found.${NC}"
        echo -e "${YELLOW}Disk temperature monitoring will be unavailable. Install 'smartmontools' if needed.${NC}"
        log_message "WARN" "'smartctl' command not found. Disk temp monitoring disabled."
        return 1
    fi
    log_message "INFO" "'smartctl' command found."
    return 0
}

get_cpu_temps() {
    local cpu_temp_output=""
    if check_command "sensors"; then
        cpu_temp_output=$(sensors 2>/dev/null | grep -E 'Core \d+:|Package id:|CPU Temp:' | awk '{printf "%s %s\n", $1, $3}')
    fi
    echo "$cpu_temp_output"
}

get_disk_temps() {
    local disk_temp_output=""
    if check_command "smartctl" && check_root_for_optional_ops; then
        local disks=$(lsblk -dno NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')
        for disk in $disks; do
            local temp=$(sudo smartctl -a "$disk" 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $10}' | head -n 1)
            if [ -n "$temp" ]; then
                disk_temp_output+="Disk ${disk##*/}: $temp C\n"
            else
                log_message "WARN" "Could not get temperature for disk $disk via smartctl."
            fi
        done
    fi
    echo -e "$disk_temp_output"
}

# --- Display & Alert Logic ---

display_current_temps() {
    local cpu_temps_raw=$(get_cpu_temps)
    local disk_temps_raw=$(get_disk_temps)

    clear # Clear screen for refresh
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Current System Temperatures <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo "Last Updated: $(date "$DATE_FORMAT")"
    echo -e "${CYAN}-----------------------------------------------------${NC}"

    local max_cpu_temp=0
    local has_cpu_info=false
    if [ -n "$cpu_temps_raw" ]; then
        echo -e "${MAGENTA}CPU Temperatures:${NC}"
        while read -r line; do
            echo "$line"
            local temp_val=$(echo "$line" | awk '{print $2}' | tr -d '+C')
            if (( $(echo "$temp_val > $max_cpu_temp" | bc -l) )); then
                max_cpu_temp="$temp_val"
            fi
            has_cpu_info=true
        done <<< "$cpu_temps_raw"
    else
        echo -e "${YELLOW}CPU Temperatures: Not available (check lm-sensors configuration).${NC}"
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"

    local max_disk_temp=0
    local has_disk_info=false
    if [ -n "$disk_temps_raw" ]; then
        echo -e "${MAGENTA}Disk Temperatures:${NC}"
        while read -r line; do
            # Extract temp value for comparison
            local temp_val=$(echo "$line" | awk '{print $2}') # e.g., "40" from "Disk sda: 40 C"
            echo "$line"
            if (( $(echo "$temp_val > $max_disk_temp" | bc -l) )); then
                max_disk_temp="$temp_val"
            fi
            has_disk_info=true
        done <<< "$disk_temps_raw"
    else
        echo -e "${YELLOW}Disk Temperatures: Not available (check smartmontools installation/root access).${NC}"
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"

    # Check and alert thresholds
    if [ "$has_cpu_info" = true ]; then
        if (( $(echo "$max_cpu_temp >= $CPU_CRIT_TEMP" | bc -l) )); then
            echo -e "${RED}CRITICAL: CPU temperature ($max_cpu_temp C) is above critical threshold ($CPU_CRIT_TEMP C)!${NC}"
            log_message "ALERT" "CRITICAL: CPU temp ($max_cpu_temp C) >= critical threshold ($CPU_CRIT_TEMP C)."
            send_email_alert "CRITICAL: High CPU Temp on $(hostname)" "CPU temperature is $max_cpu_temp C (critical threshold: $CPU_CRIT_TEMP C) on $(hostname). Please investigate!"
        elif (( $(echo "$max_cpu_temp >= $CPU_WARN_TEMP" | bc -l) )); then
            echo -e "${YELLOW}WARNING: CPU temperature ($max_cpu_temp C) is above warning threshold ($CPU_WARN_TEMP C).${NC}"
            log_message "ALERT" "WARNING: CPU temp ($max_cpu_temp C) >= warning threshold ($CPU_WARN_TEMP C)."
            send_email_alert "WARNING: High CPU Temp on $(hostname)" "CPU temperature is $max_cpu_temp C (warning threshold: $CPU_WARN_TEMP C) on $(hostname)."
        else
            echo -e "${GREEN}CPU Temperature: OK (${max_cpu_temp} C)${NC}"
        fi
    fi

    if [ "$has_disk_info" = true ]; then
        if (( $(echo "$max_disk_temp >= $DISK_CRIT_TEMP" | bc -l) )); then
            echo -e "${RED}CRITICAL: Disk temperature ($max_disk_temp C) is above critical threshold ($DISK_CRIT_TEMP C)!${NC}"
            log_message "ALERT" "CRITICAL: Disk temp ($max_disk_temp C) >= critical threshold ($DISK_CRIT_TEMP C)."
            send_email_alert "CRITICAL: High Disk Temp on $(hostname)" "Disk temperature is $max_disk_temp C (critical threshold: $DISK_CRIT_TEMP C) on $(hostname). Please investigate!"
        elif (( $(echo "$max_disk_temp >= $DISK_WARN_TEMP" | bc -l) )); then
            echo -e "${YELLOW}WARNING: Disk temperature ($max_disk_temp C) is above warning threshold ($DISK_WARN_TEMP C).${NC}"
            log_message "ALERT" "WARNING: Disk temp ($max_disk_temp C) >= warning threshold ($DISK_WARN_TEMP C)."
            send_email_alert "WARNING: High Disk Temp on $(hostname)" "Disk temperature is $max_disk_temp C (warning threshold: $DISK_WARN_TEMP C) on $(hostname)."
        else
            echo -e "${GREEN}Disk Temperature: OK (${max_disk_temp} C)${NC}"
        fi
    fi
    
    log_message "INFO" "Displayed current temperatures. CPU Max: $max_cpu_temp C, Disk Max: $max_disk_temp C."
}

continuous_monitor() {
    print_subsection "Continuous Temperature Monitoring"
    echo -e "${CYAN}Monitoring temperatures every ${REFRESH_INTERVAL} seconds. Press Ctrl+C to stop.${NC}"
    log_message "INFO" "Starting continuous temperature monitoring (interval: $REFRESH_INTERVAL s)."
    while true; do
        display_current_temps
        sleep "$REFRESH_INTERVAL"
    done
}

explain_temp_monitoring() {
    print_subsection "About Temperature Monitoring"
    echo -e "${CYAN}Why monitor temperatures?${NC}"
    echo "  - High temperatures can indicate insufficient cooling, dust buildup,"
    echo "    component failure, or heavy workload."
    echo "  - Sustained high temperatures can lead to system instability (throttling, crashes),"
    echo "    component degradation, and shortened hardware lifespan."
    echo ""
    echo -e "${CYAN}Key tools used: ${NC}"
    echo "  - ${GREEN}lm-sensors (command: sensors):${NC} Reads data from various hardware sensors,"
    echo "    including CPU core temperatures, motherboard sensors, and some GPU sensors."
    echo "    Requires 'sudo sensors-detect' and possibly a reboot for initial setup."
    echo "  - ${GREEN}smartmontools (command: smartctl):${NC} Accesses S.M.A.R.T. (Self-Monitoring,"
    echo "    Analysis and Reporting Technology) data from hard drives and SSDs, which"
    echo "    often includes temperature readings. Requires root privileges."
    echo ""
    echo -e "${CYAN}Troubleshooting: ${NC}"
    echo "  - If 'sensors' shows no temperatures, run 'sudo sensors-detect' and follow prompts."
    echo "    Then reboot. You might also need to install specific kernel modules."
    echo "  - If 'smartctl' shows no disk temperatures, ensure 'smartmontools' is installed"
    echo "    and you are running the script with sudo."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Temperature monitoring explanation displayed."
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Temperature Monitor (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}CPU Warning: ${CPU_WARN_TEMP}°C, Critical: ${CPU_CRIT_TEMP}°C${NC}"
    echo -e "${MAGENTA}Disk Warning: ${DISK_WARN_TEMP}°C, Critical: ${DISK_CRIT_TEMP}°C${NC}"
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Display Current Temperatures Once${NC}"
    echo -e "${GREEN}2. Start Continuous Monitoring${NC}"
    echo -e "${GREEN}3. About Temperature Monitoring & Troubleshooting${NC}"
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

    log_message "INFO" "Temperature monitor script started."

    # Pre-check essential commands, but don't exit if optional ones are missing
    check_sensors_installed || log_message "WARN" "'sensors' not fully setup, CPU temp might be unavailable."
    check_smartctl_installed || log_message "WARN" "'smartctl' not found, disk temp will be unavailable."

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_current_temps; pause_script ;;
            2) continuous_monitor ;;
            3) explain_temp_monitoring ;;
            0)
                echo -e "${CYAN}Exiting System Temperature Monitor. Goodbye!${NC}"
                log_message "INFO" "Temperature monitor script exited."
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
