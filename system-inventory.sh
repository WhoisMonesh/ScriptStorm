#!/bin/bash

# system-inventory.sh - Hardware/Software Inventory
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script gathers detailed hardware and software inventory
#              information from a Linux system, including CPU, Memory, Disks,
#              Network, PCI/USB devices, BIOS, OS, installed packages,
#              running services, and key software versions.

# --- Configuration ---
LOG_FILE="/var/log/system-inventory.log"    # Log file for script actions and errors
REPORT_DIR="/tmp/system_inventory_reports" # Directory to save full reports
REPORT_PREFIX="system_inventory_report_"
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="inventory-script@yourdomain.com" # Sender email for alerts

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
        echo -e "${YELLOW}WARNING: Running as non-root user. Some hardware details (BIOS, PCI, USB, some disk/network info) may be restricted or unavailable.${NC}"
        log_message "WARN" "Attempted to run script as non-root user. Limited data might be collected."
        return 1
    fi
    return 0
}

pause_script() {
    echo -n "Press Enter to continue..." && read -r
}

# --- Inventory Gathering Functions ---

get_os_info() {
    print_subsection "Operating System and Kernel"
    echo "Hostname: $(hostname)"
    if check_command "lsb_release"; then
        lsb_release -a 2>/dev/null || log_message "WARN" "lsb_release failed."
    elif [ -f "/etc/os-release" ]; then
        grep -E "PRETTY_NAME|NAME|VERSION|ID|VERSION_ID" /etc/os-release 2>/dev/null || log_message "WARN" "/etc/os-release failed."
    else
        log_message "WARN" "Could not determine OS release information."
    fi
    echo "Kernel Version: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p)"
    log_message "INFO" "OS info collected."
}

get_cpu_info() {
    print_subsection "CPU (Processor) Information"
    if check_command "lscpu"; then
        lscpu | grep -E "Model name|Architecture|CPU\(s\)|Core\(s\) per socket|Socket\(s\)|Thread\(s\) per core|Vendor ID|CPU max MHz|CPU min MHz|Cache" 2>/dev/null || log_message "WARN" "lscpu failed."
    elif [ -f "/proc/cpuinfo" ]; then
        grep -E "model name|processor|cpu cores|vendor_id|cpu MHz|cache size" /proc/cpuinfo | sort -u 2>/dev/null || log_message "WARN" "/proc/cpuinfo failed."
    else
        log_message "WARN" "Could not determine CPU information (lscpu or /proc/cpuinfo missing)."
    fi
    log_message "INFO" "CPU info collected."
}

get_memory_info() {
    print_subsection "Memory (RAM) Information"
    if check_command "free"; then
        free -h 2>/dev/null || log_message "WARN" "free command failed."
    else
        log_message "WARN" "free command not found. Trying /proc/meminfo."
        grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null || log_message "WARN" "/proc/meminfo failed."
    fi
    if check_command "dmidecode"; then
        echo -e "\nMemory Modules (requires root):"
        sudo dmidecode --type memory 2>/dev/null || log_message "WARN" "dmidecode for memory failed (requires root/dmidecode)."
    else
        log_message "WARN" "dmidecode not found. Cannot get detailed memory module info."
    fi
    log_message "INFO" "Memory info collected."
}

get_disk_info() {
    print_subsection "Disk and Storage Information"
    if check_command "lsblk"; then
        echo "Block Devices:"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID,MODEL,ROTA,SCHED 2>/dev/null || log_message "WARN" "lsblk failed."
    else
        log_message "WARN" "lsblk command not found. Trying fdisk -l."
        if check_command "fdisk"; then
            echo "Disk Partitions (requires root):"
            sudo fdisk -l 2>/dev/null | grep -E "^Disk /dev/|/dev/" || log_message "WARN" "fdisk -l failed (requires root)."
        else
            log_message "WARN" "fdisk command not found."
        fi
    fi
    echo -e "\nFilesystem Usage:"
    if check_command "df"; then
        df -h -x tmpfs -x devtmpfs -x fuse.lxcfs -x overlay -x cgroup -x rpc_pipefs -x autofs -x debugfs -x securityfs -x pstore -x binfmt_misc 2>/dev/null || log_message "WARN" "df failed."
    else
        log_message "WARN" "df command not found."
    fi
    log_message "INFO" "Disk info collected."
}

get_network_info() {
    print_subsection "Network Interface Information"
    if check_command "ip"; then
        echo "Network Interfaces (IP Addresses):"
        ip -c a 2>/dev/null || log_message "WARN" "ip command failed."
        echo -e "\nNetwork Interface Details (requires root for some info):"
        for interface in $(ip -o link show | awk -F': ' '{print $2}'); do
            echo "--- Interface: $interface ---"
            ethtool "$interface" 2>/dev/null | grep -E "Link detected:|Duplex:|Speed:|Driver:" || log_message "WARN" "ethtool failed for $interface (requires ethtool/permissions)."
        done
    elif check_command "ifconfig"; then
        echo "Network Interfaces (IP Addresses):"
        ifconfig -a 2>/dev/null || log_message "WARN" "ifconfig command failed."
        log_message "WARN" "ethtool cannot be used with ifconfig easily."
    else
        log_message "WARN" "Neither ip nor ifconfig found. Cannot display network interfaces."
    fi
    echo -e "\nDNS Servers:"
    grep "nameserver" /etc/resolv.conf 2>/dev/null || log_message "WARN" "/etc/resolv.conf failed."
    log_message "INFO" "Network info collected."
}

get_pci_info() {
    print_subsection "PCI Devices"
    if check_command "lspci"; then
        lspci -tv 2>/dev/null || log_message "WARN" "lspci failed (requires pciutils/permissions)."
    else
        log_message "WARN" "lspci command not found. Install 'pciutils' package."
    fi
    log_message "INFO" "PCI info collected."
}

get_usb_info() {
    print_subsection "USB Devices"
    if check_command "lsusb"; then
        lsusb -tv 2>/dev/null || log_message "WARN" "lsusb failed (requires usbutils/permissions)."
    else
        log_message "WARN" "lsusb command not found. Install 'usbutils' package."
    fi
    log_message "INFO" "USB info collected."
}

get_bios_motherboard_info() {
    print_subsection "BIOS and Motherboard Information"
    if check_command "dmidecode"; then
        sudo dmidecode --type bios 2>/dev/null || log_message "WARN" "dmidecode for bios failed (requires root/dmidecode)."
        echo ""
        sudo dmidecode --type baseboard 2>/dev/null || log_message "WARN" "dmidecode for baseboard failed (requires root/dmidecode)."
    else
        log_message "WARN" "dmidecode not found. Cannot get BIOS/Motherboard info."
    end_time=$(date +%s)
    fi
    log_message "INFO" "BIOS/Motherboard info collected."
}

get_installed_packages() {
    print_subsection "Installed Packages"
    echo -e "${CYAN}Note: This list can be very long. Use 'q' to quit 'less' or 'Space' to page.${NC}"
    echo "Installed packages (via detected package manager):"
    local pkg_manager_cmd=""
    if check_command "dpkg"; then # Debian/Ubuntu
        pkg_manager_cmd="dpkg -l | grep '^ii' | awk '{print \$2 \" \" \$3}'"
    elif check_command "rpm"; then # RHEL/CentOS/Fedora/openSUSE (generic RPM)
        pkg_manager_cmd="rpm -qa | sort"
    elif check_command "pacman"; then # Arch Linux
        pkg_manager_cmd="pacman -Qq"
    else
        echo -e "${YELLOW}No common package manager (dpkg, rpm, pacman) found to list installed packages.${NC}"
        log_message "WARN" "No common package manager found to list packages."
        pause_script
        return 1
    fi
    
    if [ -n "$pkg_manager_cmd" ]; then
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        eval "$pkg_manager_cmd" 2>/dev/null | less -F -R -X || log_message "WARN" "Failed to list packages."
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    fi
    log_message "INFO" "Installed packages listed."
    pause_script
}

get_running_services() {
    print_subsection "Running System Services"
    if check_command "systemctl"; then
        echo -e "${CYAN}Active systemd services:${NC}"
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        systemctl list-units --type=service --state=running --no-pager 2>/dev/null || log_message "WARN" "systemctl failed."
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    elif check_command "service"; then # Fallback for older systems
        echo -e "${CYAN}Running services (via 'service --status-all'):${NC}"
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        service --status-all | grep '\[ + \]' || log_message "WARN" "service --status-all failed."
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    else
        log_message "WARN" "Neither systemctl nor service command found."
    fi
    log_message "INFO" "Running services collected."
    pause_script
}

get_software_versions() {
    print_subsection "Key Software Versions"
    echo "Bash Version: $(bash --version | head -n 1)"
    if check_command "python3"; then echo "Python3 Version: $(python3 --version 2>/dev/null)"; fi
    if check_command "python"; then echo "Python Version: $(python --version 2>/dev/null)"; fi
    if check_command "perl"; then echo "Perl Version: $(perl -v | grep 'This is perl' | head -n 1)"; fi
    if check_command "gcc"; then echo "GCC Version: $(gcc --version | head -n 1)"; fi
    if check_command "g++"; then echo "G++ Version: $(g++ --version | head -n 1)"; fi
    if check_command "openssl"; then echo "OpenSSL Version: $(openssl version 2>/dev/null)"; fi
    if check_command "docker"; then echo "Docker Version: $(docker --version 2>/dev/null)"; fi
    if check_command "git"; then echo "Git Version: $(git --version 2>/dev/null)"; fi
    if check_command "nginx"; then echo "Nginx Version: $(nginx -v 2>&1 | awk -F'/' '{print $2}' | awk '{print $1}')"; fi
    if check_command "apache2"; then echo "Apache2 Version: $(apache2 -v 2>/dev/null | grep "Server version" | head -n 1)"; fi
    if check_command "php"; then echo "PHP Version: $(php -v | head -n 1)"; fi
    if check_command "java"; then echo "Java Version: $(java -version 2>&1 | head -n 1)"; fi
    if check_command "node"; then echo "Node.js Version: $(node -v 2>/dev/null)"; fi
    if check_command "npm"; then echo "NPM Version: $(npm -v 2>/dev/null)"; fi
    log_message "INFO" "Software versions collected."
    pause_script
}

get_environment_vars() {
    print_subsection "Important Environment Variables"
    echo -e "${CYAN}Selected environment variables:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    env | grep -E "PATH|HOME|USER|LANG|TERM|SHELL|EDITOR|DISPLAY" | sort
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Environment variables collected."
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Inventory (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Operating System & Kernel Info${NC}"
    echo -e "${GREEN}2. CPU Information${NC}"
    echo -e "${GREEN}3. Memory (RAM) Information${NC}"
    echo -e "${GREEN}4. Disk & Storage Information${NC}"
    echo -e "${GREEN}5. Network Interface Information${NC}"
    echo -e "${GREEN}6. PCI Devices${NC}"
    echo -e "${GREEN}7. USB Devices${NC}"
    echo -e "${GREEN}8. BIOS & Motherboard Information${NC}"
    echo -e "${GREEN}9. Installed Packages (may be long)${NC}"
    echo -e "${MAGENTA}S. Running System Services${NC}"
    echo -e "${MAGENTA}V. Key Software Versions${NC}"
    echo -e "${MAGENTA}E. Important Environment Variables${NC}"
    echo -e "${CYAN}F. Generate FULL Inventory Report to File${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

generate_full_report() {
    print_header "Generating Full System Inventory Report"
    local report_file="${REPORT_DIR}/${REPORT_PREFIX}$(date "$DATE_FORMAT").txt"
    mkdir -p "$REPORT_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create report directory $REPORT_DIR. Cannot save report.${NC}"
        log_message "ERROR" "Failed to create report directory: $REPORT_DIR."
        pause_script
        return 1
    fi

    echo -e "${CYAN}Generating report to: $report_file${NC}"
    log_message "INFO" "Generating full report to $report_file."

    { # Start of redirection block
        echo "--- System Inventory Report ---"
        echo "Generated On: $(date)"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "-----------------------------"
        
        get_os_info
        get_cpu_info
        get_memory_info
        get_disk_info
        get_network_info
        get_pci_info
        get_usb_info
        get_bios_motherboard_info
        
        # For long lists like packages, avoid interactive prompts
        print_subsection "Installed Packages (Full List)"
        local pkg_manager_cmd=""
        if check_command "dpkg"; then pkg_manager_cmd="dpkg -l | grep '^ii' | awk '{print \$2 \" \" \$3}'";
        elif check_command "rpm"; then pkg_manager_cmd="rpm -qa | sort";
        elif check_command "pacman"; then pkg_manager_cmd="pacman -Qq";
        fi
        if [ -n "$pkg_manager_cmd" ]; then
            eval "$pkg_manager_cmd" 2>/dev/null || echo "Failed to list packages."
        else
            echo "No common package manager found."
        fi

        get_running_services
        get_software_versions
        get_environment_vars
        
        echo -e "\n--- End of Report ---"
    } > "$report_file" 2>&1 # Redirect all stdout/stderr to report file

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Full inventory report saved to: ${report_file}${NC}"
        log_message "SUCCESS" "Full report saved to $report_file."
        send_email_alert "System Inventory Report Generated" "A full system inventory report has been generated on $(hostname) at $report_file."
    else
        echo -e "${RED}ERROR: Failed to generate full inventory report.${NC}"
        log_message "ERROR" "Failed to generate full report."
        send_email_alert "System Inventory Report FAILED" "Failed to generate full system inventory report on $(hostname). See logs for details."
    fi
    pause_script
}

main_loop() {
    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) get_os_info; pause_script ;;
            2) get_cpu_info; pause_script ;;
            3) get_memory_info; pause_script ;;
            4) get_disk_info; pause_script ;;
            5) get_network_info; pause_script ;;
            6) get_pci_info; pause_script ;;
            7) get_usb_info; pause_script ;;
            8) get_bios_motherboard_info; pause_script ;;
            9) get_installed_packages ;; # This function already pauses
            S|s) get_running_services; pause_script ;;
            V|v) get_software_versions; pause_script ;;
            E|e) get_environment_vars; pause_script ;;
            F|f) generate_full_report ;;
            0)
                echo -e "${CYAN}Exiting System Inventory. Goodbye!${NC}"
                log_message "INFO" "System inventory script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a valid option.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main() {
    # Ensure log directory and report directory exist
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi
    mkdir -p "$REPORT_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create report directory $REPORT_DIR. Exiting.${NC}"
        log_message "ERROR" "Failed to create report directory: $REPORT_DIR"
        exit 1
    fi

    log_message "INFO" "System inventory script started."
    check_root # Check for root, but allow non-root to run with warnings.

    main_loop
}

main
