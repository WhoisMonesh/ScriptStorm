#!/bin/bash

# system-info.sh - Displays comprehensive system information
# Version: 2.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 18, 2025
# Description: This script gathers and displays detailed information about the system's
#              hardware, operating system, network, processes, disk usage, and more.
#              It aims for clarity, robustness, and user-friendliness.

# --- Configuration ---
LOG_FILE="/var/log/system-info.log" # Log file for errors and significant events
REPORT_DIR="/tmp/system_info_reports" # Directory to save reports if needed
REPORT_PREFIX="system_info_report_"
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

log_message() {
    local type="$1" # INFO, WARN, ERROR
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

# --- System Information Gathering Functions ---

get_os_info() {
    print_subsection "Operating System Information"
    if check_command "lsb_release"; then
        lsb_release -a 2>/dev/null || log_message "WARN" "lsb_release failed to retrieve info."
    elif [ -f "/etc/os-release" ]; then
        grep -E "PRETTY_NAME|NAME|VERSION|ID|VERSION_ID" /etc/os-release 2>/dev/null || log_message "WARN" "/etc/os-release could not be read."
    elif [ -f "/etc/redhat-release" ]; then
        cat /etc/redhat-release 2>/dev/null || log_message "WARN" "/etc/redhat-release could not be read."
    elif [ -f "/etc/debian_version" ]; then
        echo "Debian Version: $(cat /etc/debian_version)" 2>/dev/null || log_message "WARN" "/etc/debian_version could not be read."
    else
        log_message "WARN" "Could not determine OS release information."
    fi
    echo "Kernel Version: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
}

get_cpu_info() {
    print_subsection "CPU Information"
    if check_command "lscpu"; then
        lscpu | grep -E "Model name|Architecture|CPU\(s\)|Core\(s\) per socket|Socket\(s\)|Thread\(s\) per core|Vendor ID|CPU max MHz|CPU min MHz" 2>/dev/null || log_message "WARN" "lscpu failed to retrieve CPU info."
    elif [ -f "/proc/cpuinfo" ]; then
        grep -E "model name|processor|cpu cores|vendor_id|cpu MHz" /proc/cpuinfo | sort -u 2>/dev/null || log_message "WARN" "/proc/cpuinfo could not be read."
    else
        log_message "WARN" "Could not determine CPU information."
    fi
}

get_memory_info() {
    print_subsection "Memory Information"
    if check_command "free"; then
        free -h 2>/dev/null || log_message "WARN" "free command failed to retrieve memory info."
    else
        log_message "WARN" "free command not found. Trying /proc/meminfo."
        grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null || log_message "WARN" "/proc/meminfo could not be read."
    fi
}

get_disk_info() {
    print_subsection "Disk Usage and Information"
    echo "Filesystem Disk Usage:"
    if check_command "df"; then
        df -h -x tmpfs -x devtmpfs 2>/dev/null || log_message "WARN" "df command failed to retrieve disk usage."
    else
        log_message "WARN" "df command not found."
    fi

    echo -e "\nBlock Device Information:"
    if check_command "lsblk"; then
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID,MODEL 2>/dev/null || log_message "WARN" "lsblk command failed to retrieve block device info."
    else
        log_message "WARN" "lsblk command not found."
    fi

    echo -e "\nDisk I/O Statistics (Last 5 seconds):"
    if check_command "iostat"; then
        iostat -d 5 1 2>/dev/null || log_message "WARN" "iostat command failed to retrieve I/O stats. (Install 'sysstat' package)"
    else
        log_message "WARN" "iostat command not found. Install 'sysstat' package for disk I/O statistics."
    fi
}

get_network_info() {
    print_subsection "Network Information"
    echo "Network Interfaces:"
    if check_command "ip"; then
        ip -c a 2>/dev/null || log_message "WARN" "ip command failed to retrieve network interface info."
    elif check_command "ifconfig"; then
        ifconfig -a 2>/dev/null || log_message "WARN" "ifconfig command failed to retrieve network interface info."
    else
        log_message "WARN" "Neither ip nor ifconfig found. Cannot display network interfaces."
    fi

    echo -e "\nRouting Table:"
    if check_command "ip"; then
        ip r 2>/dev/null || log_message "WARN" "ip command failed to retrieve routing table."
    elif check_command "netstat"; then
        netstat -rn 2>/dev/null || log_message "WARN" "netstat command failed to retrieve routing table."
    else
        log_message "WARN" "Neither ip nor netstat found. Cannot display routing table."
    fi

    echo -e "\nDNS Servers:"
    if [ -f "/etc/resolv.conf" ]; then
        grep "nameserver" /etc/resolv.conf 2>/dev/null || log_message "WARN" "/etc/resolv.conf could not be read for DNS servers."
    else
        log_message "WARN" "/etc/resolv.conf not found."
    fi

    echo -e "\nOpen Ports (Listening):"
    if check_command "ss"; then
        ss -tuln 2>/dev/null || log_message "WARN" "ss command failed to retrieve open ports."
    elif check_command "netstat"; then
        netstat -tulnp 2>/dev/null || log_message "WARN" "netstat command failed to retrieve open ports."
    else
        log_message "WARN" "Neither ss nor netstat found. Cannot display open ports."
    fi
}

get_process_info() {
    print_subsection "Top Running Processes"
    echo "Top 10 CPU-consuming processes:"
    if check_command "ps"; then
        ps aux --sort=-%cpu | head -n 11 2>/dev/null || log_message "WARN" "ps command failed to retrieve processes by CPU."
    else
        log_message "WARN" "ps command not found."
    fi

    echo -e "\nTop 10 Memory-consuming processes:"
    if check_command "ps"; then
        ps aux --sort=-%mem | head -n 11 2>/dev/null || log_message "WARN" "ps command failed to retrieve processes by Memory."
    else
        # Already warned if ps is not found
        :
    fi
}

get_user_info() {
    print_subsection "User Information"
    echo "Logged-in Users:"
    if check_command "who"; then
        who 2>/dev/null || log_message "WARN" "who command failed to retrieve logged-in users."
    else
        log_message "WARN" "who command not found."
    fi

    echo -e "\nLast Logins:"
    if check_command "last"; then
        last -n 5 2>/dev/null || log_message "WARN" "last command failed to retrieve last logins."
    else
        log_message "WARN" "last command not found."
    fi
}

get_package_info() {
    print_subsection "Package Information (Top 10 installed/recent)"
    if check_command "dpkg"; then # Debian/Ubuntu
        echo "Recently installed Debian packages (last 10):"
        grep " install " /var/log/dpkg.log | tail -n 10 2>/dev/null || log_message "WARN" "Failed to get dpkg log."
    elif check_command "rpm"; then # RedHat/CentOS/Fedora
        echo "Recently installed RPM packages (last 10):"
        rpm -qa --last | head -n 10 2>/dev/null || log_message "WARN" "Failed to get rpm installed packages."
    elif check_command "pacman"; then # Arch Linux
        echo "Recently installed Arch packages (last 10):"
        pacman -Ql | head -n 10 2>/dev/null || log_message "WARN" "Failed to get pacman installed packages."
    else
        log_message "WARN" "No common package manager (dpkg, rpm, pacman) found to list installed packages."
    fi
}

get_system_logs() {
    print_subsection "Recent System Logs (Last 20 lines)"
    if check_command "journalctl"; then
        journalctl -n 20 --no-pager 2>/dev/null || log_message "WARN" "journalctl failed to retrieve recent logs."
    elif [ -f "/var/log/syslog" ]; then
        tail -n 20 /var/log/syslog 2>/dev/null || log_message "WARN" "/var/log/syslog could not be read."
    elif [ -f "/var/log/messages" ]; then
        tail -n 20 /var/log/messages 2>/dev/null || log_message "WARN" "/var/log/messages could not be read."
    else
        log_message "WARN" "No common system log file found (syslog, messages) or journalctl not available."
    fi
}

get_hardware_details() {
    print_subsection "Hardware Details (LSPCI/LSUSB)"
    if check_command "lspci"; then
        echo "PCI Devices:"
        lspci -tv 2>/dev/null || log_message "WARN" "lspci failed to retrieve PCI info."
    else
        log_message "WARN" "lspci command not found. Install 'pciutils' package."
    fi

    echo -e "\nUSB Devices:"
    if check_command "lsusb"; then
        lsusb -tv 2>/dev/null || log_message "WARN" "lsusb failed to retrieve USB info."
    else
        log_message "WARN" "lsusb command not found. Install 'usbutils' package."
    fi
}

get_firewall_status() {
    print_subsection "Firewall Status"
    if check_command "ufw"; then
        echo "UFW Status:"
        ufw status 2>/dev/null || log_message "WARN" "ufw status command failed."
    elif check_command "firewall-cmd"; then
        echo "FirewallD Status:"
        firewall-cmd --state 2>/dev/null || log_message "WARN" "firewall-cmd failed to get state."
        firewall-cmd --list-all 2>/dev/null || log_message "WARN" "firewall-cmd failed to list all rules."
    elif check_command "iptables"; then
        echo "Iptables Rules (Filter Table):"
        iptables -L -n -v 2>/dev/null || log_message "WARN" "iptables failed to list rules. Run with sudo if necessary."
    else
        log_message "WARN" "No common firewall management tool found (ufw, firewall-cmd, iptables)."
    fi
}

get_cron_jobs() {
    print_subsection "Scheduled Cron Jobs (System-wide and User-specific)"
    echo "System-wide Cron Jobs (/etc/cron.*):"
    if [ -d "/etc/cron.d" ]; then
        ls -l /etc/cron.d/ 2>/dev/null || log_message "WARN" "Could not list /etc/cron.d."
        echo "---"
        for cronfile in /etc/cron.d/*; do
            if [ -f "$cronfile" ]; then
                echo "File: $(basename "$cronfile")"
                cat "$cronfile" 2>/dev/null || log_message "WARN" "Could not read $cronfile."
                echo "---"
            fi
        done
    else
        log_message "WARN" "/etc/cron.d directory not found."
    fi

    echo -e "\nUser Cron Jobs (for current user - if applicable, requires root to see others):"
    if check_command "crontab"; then
        crontab -l 2>/dev/null || echo "No crontab for current user or permissions denied."
    else
        log_message "WARN" "crontab command not found."
    fi
}

get_mounted_filesystems() {
    print_subsection "Mounted Filesystems"
    if check_command "findmnt"; then
        findmnt --raw --full --output=SOURCE,TARGET,FSTYPE,OPTIONS,USED,AVAIL 2>/dev/null || log_message "WARN" "findmnt failed to retrieve mounted filesystems."
    elif check_command "mount"; then
        mount -l 2>/dev/null || log_message "WARN" "mount command failed to retrieve mounted filesystems."
    else
        log_message "WARN" "Neither findmnt nor mount found."
    fi
}

# --- Main Script Execution ---

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    # Ensure report directory exists
    mkdir -p "$REPORT_DIR"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Could not create report directory $REPORT_DIR."
        echo -e "${RED}ERROR: Could not create report directory $REPORT_DIR. Continuing without report saving.${NC}"
        REPORT_DIR="" # Disable report saving if directory cannot be created
    fi


    echo -e "${CYAN}Starting System Information Report...${NC}"
    log_message "INFO" "system-info.sh started."

    start_time=$(date +%s)

    # Call all information gathering functions
    print_header "General System Overview"
    get_os_info
    get_cpu_info
    get_memory_info

    print_header "Storage and I/O"
    get_disk_info
    get_mounted_filesystems

    print_header "Network and Connectivity"
    get_network_info
    get_firewall_status

    print_header "Processes and Users"
    get_process_info
    get_user_info

    print_header "Software and Scheduled Tasks"
    get_package_info
    get_cron_jobs

    print_header "Hardware and Diagnostics"
    get_hardware_details
    get_system_logs

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log_message "INFO" "System information report completed in ${duration} seconds."
    echo -e "\n${CYAN}System Information Report Completed.${NC}"
    echo -e "${CYAN}Report generated in ${duration} seconds.${NC}"
    echo -e "${CYAN}Detailed logs are available at: ${LOG_FILE}${NC}"

    # Optionally save the output to a file
    if [ -n "$REPORT_DIR" ]; then
        REPORT_FILE="${REPORT_DIR}/${REPORT_PREFIX}$(date "$DATE_FORMAT").txt"
        {
            echo "--- System Information Report ---"
            echo "Generated On: $(date)"
            echo "Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm"
            echo "---------------------------------"
            main_output # Re-run main logic but redirect to file this time
        } > "$REPORT_FILE" 2>&1

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Full report saved to: ${REPORT_FILE}${NC}"
        else
            log_message "ERROR" "Failed to save full report to ${REPORT_FILE}."
            echo -e "${RED}ERROR: Failed to save full report to ${REPORT_FILE}. See log for details.${NC}"
        fi
    fi
}

# This function is a wrapper to capture the output of all info-gathering functions
# when saving to a file. It avoids re-executing the entire script logic.
main_output() {
    get_os_info
    get_cpu_info
    get_memory_info
    get_disk_info
    get_mounted_filesystems
    get_network_info
    get_firewall_status
    get_process_info
    get_user_info
    get_package_info
    get_cron_jobs
    get_hardware_details
    get_system_logs
}


# --- Script Entry Point ---
if [[ "$EUID" -eq 0 ]]; then
    main
else
    echo -e "${YELLOW}WARNING: Running as non-root user. Some information may be restricted (e.g., /proc/cpuinfo, system logs, lspci, lsusb).${NC}"
    echo -e "${YELLOW}Consider running with 'sudo bash system-info.sh' for a complete report.${NC}"
    main # Still run, but with warnings for potential missing info
fi
