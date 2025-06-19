#!/bin/bash

# firewall-setup.sh - Basic Firewall Configuration
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides a menu-driven interface for basic firewall
#              configuration. It automatically detects and uses ufw, firewall-cmd,
#              or falls back to direct iptables for common rules.
#              It helps to open/close ports, enable/disable firewall, and reset rules.

# --- Configuration ---
LOG_FILE="/var/log/firewall-setup.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="firewall-manager@yourdomain.com" # Sender email for alerts

# --- Colors for better readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Global Variables for Detected Firewall Manager ---
FIREWALL_MANAGER="" # e.g., "ufw", "firewalld", "iptables"

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
        echo -e "${RED}ERROR: This script must be run as root to configure firewall rules.${NC}"
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

# --- Firewall Detection ---

detect_firewall_manager() {
    log_message "INFO" "Detecting firewall manager..."
    if check_command "ufw"; then
        FIREWALL_MANAGER="ufw"
        echo -e "${GREEN}Detected firewall manager: UFW (Uncomplicated Firewall)${NC}"
    elif check_command "firewall-cmd"; then
        FIREWALL_MANAGER="firewalld"
        echo -e "${GREEN}Detected firewall manager: FirewallD${NC}"
    elif check_command "iptables"; then
        FIREWALL_MANAGER="iptables"
        echo -e "${YELLOW}Detected firewall manager: IPTables (Fallback). Configuration will be basic and more manual.${NC}"
        echo -e "${YELLOW}It is recommended to use UFW or FirewallD if available for easier management.${NC}"
    else
        echo -e "${RED}ERROR: No supported firewall manager (ufw, firewall-cmd, iptables) found.${NC}"
        log_message "ERROR" "No supported firewall manager detected."
        exit 1
    fi
    log_message "SUCCESS" "Firewall manager '$FIREWALL_MANAGER' detected."
}

# --- Generic Firewall Functions (Wrapper) ---

fw_enable() {
    print_subsection "Enabling Firewall"
    if confirm_action "Are you sure you want to enable the firewall? This might block connections if not configured properly."; then
        case "$FIREWALL_MANAGER" in
            "ufw") sudo ufw enable --force ;;
            "firewalld") sudo systemctl start firewalld && sudo systemctl enable firewalld ;;
            "iptables") _iptables_default_setup && _iptables_save ;;
        esac
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Firewall enabled successfully.${NC}"
            log_message "SUCCESS" "Firewall enabled."
            send_email_alert "Firewall Status: Enabled" "Firewall enabled on $(hostname)."
        else
            echo -e "${RED}ERROR: Failed to enable firewall.${NC}"
            log_message "ERROR" "Failed to enable firewall."
            send_email_alert "Firewall Status: Enable Failed" "Firewall enable FAILED on $(hostname)."
        fi
    fi
    pause_script
}

fw_disable() {
    print_subsection "Disabling Firewall"
    if confirm_action "Are you sure you want to disable the firewall? This will open up all connections."; then
        case "$FIREWALL_MANAGER" in
            "ufw") sudo ufw disable ;;
            "firewalld") sudo systemctl stop firewalld && sudo systemctl disable firewalld ;;
            "iptables") _iptables_flush_rules && _iptables_save ;;
        esac
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Firewall disabled successfully.${NC}"
            log_message "SUCCESS" "Firewall disabled."
            send_email_alert "Firewall Status: Disabled" "Firewall disabled on $(hostname)."
        else
            echo -e "${RED}ERROR: Failed to disable firewall.${NC}"
            log_message "ERROR" "Failed to disable firewall."
            send_email_alert "Firewall Status: Disable Failed" "Firewall disable FAILED on $(hostname)."
        fi
    fi
    pause_script
}

fw_status() {
    print_subsection "Firewall Status"
    echo -e "${CYAN}Current firewall status:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    case "$FIREWALL_MANAGER" in
        "ufw") sudo ufw status verbose ;;
        "firewalld") sudo firewall-cmd --state && sudo firewall-cmd --list-all ;;
        "iptables") sudo iptables -L -n -v && echo "" && sudo iptables -S ;;
    esac
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Firewall status checked."
    pause_script
}

fw_reset() {
    print_subsection "Reset Firewall Rules"
    echo -e "${RED}WARNING: This will delete ALL existing firewall rules and set to defaults!${NC}"
    echo -e "${RED}You will need to re-add any necessary rules (e.g., SSH) after reset.${NC}"
    if confirm_action "Are you absolutely sure you want to reset the firewall?"; then
        case "$FIREWALL_MANAGER" in
            "ufw") sudo ufw reset --force ;;
            "firewalld") sudo firewall-cmd --zone=public --remove-service=ssh --permanent 2>/dev/null; sudo firewall-cmd --zone=public --remove-service=http --permanent 2>/dev/null; sudo firewall-cmd --zone=public --remove-service=https --permanent 2>/dev/null; sudo firewall-cmd --reload; _firewalld_set_default_policy ;;
            "iptables") _iptables_flush_rules && _iptables_default_setup && _iptables_save ;;
        esac
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Firewall rules reset successfully.${NC}"
            log_message "SUCCESS" "Firewall rules reset."
            send_email_alert "Firewall Status: Reset" "Firewall rules reset on $(hostname)."
        else
            echo -e "${RED}ERROR: Failed to reset firewall rules.${NC}"
            log_message "ERROR" "Failed to reset firewall rules."
            send_email_alert "Firewall Status: Reset Failed" "Firewall rules reset FAILED on $(hostname)."
        fi
    fi
    pause_script
}

fw_allow_port() {
    local port_num=$(read_user_input "Enter port number to allow (e.g., 8080)" "")
    local protocol=$(read_user_input "Enter protocol (tcp/udp/all, default: tcp)" "tcp")
    local persistence="--permanent" # For firewalld, ufw does it automatically
    if [ -z "$port_num" ]; then echo "${RED}Port cannot be empty.${NC}"; pause_script; return 1; fi

    print_subsection "Allow Port $port_num/$protocol"
    case "$FIREWALL_MANAGER" in
        "ufw") sudo ufw allow "$port_num/$protocol" ;;
        "firewalld") sudo firewall-cmd --zone=public --add-port="$port_num/$protocol" $persistence && sudo firewall-cmd --reload ;;
        "iptables") sudo iptables -A INPUT -p "$protocol" --dport "$port_num" -m state --state NEW,ESTABLISHED -j ACCEPT && _iptables_save ;;
    esac
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Port $port_num/$protocol allowed successfully.${NC}"
        log_message "SUCCESS" "Port $port_num/$protocol allowed."
    else
        echo -e "${RED}ERROR: Failed to allow port $port_num/$protocol.${NC}"
        log_message "ERROR" "Failed to allow port $port_num/$protocol."
    fi
    pause_script
}

fw_deny_port() {
    local port_num=$(read_user_input "Enter port number to deny (e.g., 8080)" "")
    local protocol=$(read_user_input "Enter protocol (tcp/udp/all, default: tcp)" "tcp")
    local persistence="--permanent" # For firewalld
    if [ -z "$port_num" ]; then echo "${RED}Port cannot be empty.${NC}"; pause_script; return 1; fi

    print_subsection "Deny Port $port_num/$protocol"
    case "$FIREWALL_MANAGER" in
        "ufw") sudo ufw deny "$port_num/$protocol" ;;
        "firewalld") sudo firewall-cmd --zone=public --remove-port="$port_num/$protocol" $persistence && sudo firewall-cmd --reload ;;
        "iptables") sudo iptables -D INPUT -p "$protocol" --dport "$port_num" -j ACCEPT && _iptables_save ;; # Try to remove existing ACCEPT rule
    esac
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Port $port_num/$protocol denied/removed successfully.${NC}"
        log_message "SUCCESS" "Port $port_num/$protocol denied/removed."
    else
        echo -e "${YELLOW}WARNING: Rule to deny/remove port $port_num/$protocol failed or didn't exist.${NC}"
        log_message "WARN" "Failed to deny/remove port $port_num/$protocol."
    fi
    pause_script
}

fw_allow_service() {
    local service_name=$(read_user_input "Enter common service name to allow (e.g., ssh, http, https, ftp)" "")
    if [ -z "$service_name" ]; then echo "${RED}Service name cannot be empty.${NC}"; pause_script; return 1; fi

    print_subsection "Allow Service: $service_name"
    case "$FIREWALL_MANAGER" in
        "ufw") sudo ufw allow "$service_name" ;;
        "firewalld") sudo firewall-cmd --zone=public --add-service="$service_name" --permanent && sudo firewall-cmd --reload ;;
        "iptables")
            # IPTables does not have built-in service names; requires manual port mapping
            echo -e "${YELLOW}IPTables does not support service names directly. Please use 'Allow Port' option instead (e.g., 22 for ssh, 80 for http).${NC}"
            log_message "WARN" "IPTables does not support service names directly for allow_service."
            pause_script
            return 1
            ;;
    esac
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service '$service_name' allowed successfully.${NC}"
        log_message "SUCCESS" "Service '$service_name' allowed."
    else
        echo -e "${RED}ERROR: Failed to allow service '$service_name'.${NC}"
        log_message "ERROR" "Failed to allow service '$service_name'."
    fi
    pause_script
}

fw_deny_service() {
    local service_name=$(read_user_input "Enter common service name to deny (e.g., ssh, http, https, ftp)" "")
    if [ -z "$service_name" ]; then echo "${RED}Service name cannot be empty.${NC}"; pause_script; return 1; fi

    print_subsection "Deny Service: $service_name"
    case "$FIREWALL_MANAGER" in
        "ufw") sudo ufw deny "$service_name" ;;
        "firewalld") sudo firewall-cmd --zone=public --remove-service="$service_name" --permanent && sudo firewall-cmd --reload ;;
        "iptables")
            echo -e "${YELLOW}IPTables does not support service names directly. Please remove rules for specific ports if needed.${NC}"
            log_message "WARN" "IPTables does not support service names directly for deny_service."
            pause_script
            return 1
            ;;
    esac
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service '$service_name' denied/removed successfully.${NC}"
        log_message "SUCCESS" "Service '$service_name' denied/removed."
    else
        echo -e "${YELLOW}WARNING: Rule to deny/remove service '$service_name' failed or didn't exist.${NC}"
        log_message "WARN" "Failed to deny/remove service '$service_name'."
    fi
    pause_script
}

# --- IPTables Specific Internal Functions ---
_iptables_flush_rules() {
    echo -e "${CYAN}Flushing existing IPTables rules...${NC}"
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -F
    sudo iptables -X
    sudo iptables -Z
    sudo iptables -t nat -F
    sudo iptables -t nat -X
    sudo iptables -t mangle -F
    sudo iptables -t mangle -X
    sudo iptables -t raw -F
    sudo iptables -t raw -X
    log_message "INFO" "IPTables rules flushed."
}

_iptables_default_setup() {
    echo -e "${CYAN}Setting up basic IPTables defaults (allow loopback, established, default deny incoming)...${NC}"
    # Allow all loopback (internal) traffic
    sudo iptables -A INPUT -i lo -j ACCEPT
    # Allow established and related incoming connections
    sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Drop all other incoming traffic by default
    sudo iptables -P INPUT DROP
    # Allow all outgoing traffic
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -P FORWARD DROP # Usually deny forwarding
    log_message "INFO" "IPTables default policy set to DROP INPUT, ACCEPT OUTPUT."
}

_iptables_save() {
    # This requires 'iptables-persistent' (Debian/Ubuntu) or 'iptables-services' (RHEL/CentOS)
    # Be aware that these might not be installed by default.
    echo -e "${CYAN}Saving IPTables rules for persistence...${NC}"
    if check_command "netfilter-persistent"; then # Debian/Ubuntu
        sudo netfilter-persistent save
    elif check_command "iptables-save"; then # Generic, but needs service to load on boot
        # Try to find a way to save rules for persistence. This varies greatly by distro.
        # Common locations: /etc/sysconfig/iptables (RHEL), /etc/iptables/rules.v4 (Debian)
        local save_path="/etc/sysconfig/iptables" # RHEL/CentOS
        if [ -f "/etc/iptables/rules.v4" ]; then # Debian/Ubuntu (if iptables-persistent is installed)
            save_path="/etc/iptables/rules.v4"
        fi
        if [ -w "$save_path" ]; then
            sudo iptables-save > "$save_path"
        else
            echo -e "${YELLOW}WARNING: Could not find writable default path to save IPTables rules. Rules might not persist after reboot.${NC}"
            log_message "WARN" "IPTables rules not saved for persistence."
        fi
    else
        echo -e "${RED}ERROR: No IPTables persistence mechanism found. Rules may not survive reboot.${NC}"
        log_message "ERROR" "No IPTables persistence mechanism found."
    fi
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Basic Firewall Configuration (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}Detected Manager: ${FIREWALL_MANAGER^}${NC}" # Capitalize first letter
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Check Firewall Status${NC}"
    echo -e "${GREEN}2. Enable Firewall (with default policies)${NC}"
    echo -e "${GREEN}3. Disable Firewall${NC}"
    echo -e "${GREEN}4. Reset All Firewall Rules (DANGEROUS!)${NC}"
    echo -e "${GREEN}5. Allow a Specific Port/Protocol${NC}"
    echo -e "${GREEN}6. Deny/Remove a Specific Port/Protocol${NC}"
    if [[ "$FIREWALL_MANAGER" == "ufw" || "$FIREWALL_MANAGER" == "firewalld" ]]; then
        echo -e "${GREEN}7. Allow a Common Service (e.g., ssh, http, https)${NC}"
        echo -e "${GREEN}8. Deny/Remove a Common Service${NC}"
    fi
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

    log_message "INFO" "Firewall setup script started."
    check_root # This script *requires* root for all operations.
    detect_firewall_manager

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) fw_status ;;
            2) fw_enable ;;
            3) fw_disable ;;
            4) fw_reset ;;
            5) fw_allow_port ;;
            6) fw_deny_port ;;
            7)
                if [[ "$FIREWALL_MANAGER" == "ufw" || "$FIREWALL_MANAGER" == "firewalld" ]]; then
                    fw_allow_service
                else
                    echo -e "${RED}Invalid choice. Option not supported by IPTables.${NC}"
                    log_message "WARN" "Invalid menu choice: '$choice' (service rules not supported)."
                    pause_script
                fi
                ;;
            8)
                if [[ "$FIREWALL_MANAGER" == "ufw" || "$FIREWALL_MANAGER" == "firewalld" ]]; then
                    fw_deny_service
                else
                    echo -e "${RED}Invalid choice. Option not supported by IPTables.${NC}"
                    log_message "WARN" "Invalid menu choice: '$choice' (service rules not supported)."
                    pause_script
                fi
                ;;
            0)
                echo -e "${CYAN}Exiting Basic Firewall Configuration. Goodbye!${NC}"
                log_message "INFO" "Firewall setup script exited."
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
main
