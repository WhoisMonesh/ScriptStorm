#!/bin/bash

# service-deps.sh - Maps Service Dependencies
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script leverages systemd to map service dependencies.
#              It allows you to view what a service requires (forward dependencies)
#              and what services require it (reverse dependencies), as well as
#              detailed dependency properties.

# --- Configuration ---
LOG_FILE="/var/log/service-deps.log" # Log file for script actions and errors
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

check_systemd() {
    if ! check_command "systemctl"; then
        echo -e "${RED}ERROR: 'systemctl' command not found. This script requires systemd.${NC}"
        log_message "ERROR" "'systemctl' not found. Systemd is required."
        exit 1
    fi
    log_message "INFO" "systemctl detected."
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

# --- Service Dependency Mapping Functions ---

list_all_services() {
    print_subsection "List All Available Services"
    echo -e "${CYAN}Listing all loaded service units (may be long). Use 'q' to quit 'less' or 'Space' to page.${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    sudo systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null | less -F -R -X \
    || log_message "ERROR" "Failed to list services."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed all services."
    pause_script
}

search_services() {
    print_subsection "Search for a Service"
    local search_term=$(read_user_input "Enter a search term for service units (e.g., 'ssh', 'apache')" "")
    if [ -z "$search_term" ]; then
        echo -e "${YELLOW}Search term cannot be empty. Operation cancelled.${NC}"
        pause_script
        return 0
    fi

    echo -e "${CYAN}Searching for services matching '$search_term':${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    sudo systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | grep -i "$search_term" \
    || echo -e "${YELLOW}No services found matching '$search_term'.${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Searched for services matching '$search_term'."
    pause_script
}


get_service_name() {
    local prompt_msg="$1"
    local service_name=$(read_user_input "$prompt_msg (e.g., sshd.service, apache2.service)" "")
    if [ -z "$service_name" ]; then
        echo -e "${RED}Service name cannot be empty. Operation cancelled.${NC}"
        pause_script
        return 1
    fi
    # Ensure it ends with .service if not already
    if [[ ! "$service_name" =~ \.service$ ]]; then
        service_name="${service_name}.service"
    fi

    # Basic check if unit exists (systemctl status returns 0 if found)
    sudo systemctl status "$service_name" &>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Service unit '$service_name' not found or is invalid.${NC}"
        log_message "ERROR" "Service '$service_name' not found for dependency check."
        pause_script
        return 1
    fi
    echo "$service_name" # Return the validated service name
}


show_forward_dependencies() {
    print_subsection "Forward Dependencies (Requires/Wants/After)"
    local service=$(get_service_name "Enter service unit to show its forward dependencies")
    if [ $? -ne 0 ]; then return; fi

    echo -e "${CYAN}Dependencies for $service (what it requires/wants):${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    sudo systemctl list-dependencies "$service" --all --full --no-pager 2>/dev/null \
    || log_message "ERROR" "Failed to list forward dependencies for $service."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed forward dependencies for $service."
    pause_script
}

show_reverse_dependencies() {
    print_subsection "Reverse Dependencies (Required-By/Wanted-By/Before)"
    local service=$(get_service_name "Enter service unit to show its reverse dependencies")
    if [ $? -ne 0 ]; then return; fi

    echo -e "${CYAN}Reverse dependencies for $service (what requires/wants it):${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    sudo systemctl list-dependencies "$service" --all --full --reverse --no-pager 2>/dev/null \
    || log_message "ERROR" "Failed to list reverse dependencies for $service."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Listed reverse dependencies for $service."
    pause_script
}

show_detailed_dependencies() {
    print_subsection "Detailed Dependency Properties"
    local service=$(get_service_name "Enter service unit for detailed dependency properties")
    if [ $? -ne 0 ]; then return; fi

    echo -e "${CYAN}Detailed properties for $service:${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    # Filter for common dependency properties from systemctl show
    sudo systemctl show "$service" --property=Requires \
                            --property=Requisite \
                            --property=Wants \
                            --property=BindsTo \
                            --property=PartOf \
                            --property=Conflicts \
                            --property=Before \
                            --property=After \
                            --property=OnFailure \
                            --property=OnSuccess \
                            --property=Triggers \
                            --property=TriggeredBy \
                            --property=Consumes \
                            --property=RequiresMountsFor \
                            --property=Asserts \
                            --property=Conditions \
                            --property=Description \
                            --property=LoadState \
                            --property=ActiveState \
                            --property=SubState \
                            --property=UnitFileState \
                            --property=ExecStart \
                            --property=ExecStartPre \
                            --property=ExecStartPost \
                            --property=ExecReload \
                            --property=ExecStop \
                            --property=ExecStopPost \
                            --property=Restart \
                            --property=RestartSec \
                            --property=TimeoutStartUSec \
                            --property=TimeoutStopUSec \
                            --property=PIDFile \
                            --property=BusName \
                            --property=RemainAfterExit \
                            --property=Type \
                            --property=StartLimitBurst \
                            --property=StartLimitIntervalSec \
                            --property=CPUAccounting \
                            --property=MemoryAccounting \
                            --property=BlockIOAccounting \
                            --property=TasksAccounting \
                            --property=LimitNOFILE \
                            --property=Delegate \
                            --property=PrivateTmp \
                            --property=ProtectSystem \
                            --property=ProtectHome \
                            --no-pager 2>/dev/null \
    || log_message "ERROR" "Failed to show detailed properties for $service."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Showed detailed properties for $service."
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Service Dependency Mapper (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. List All Available Services${NC}"
    echo -e "${GREEN}2. Search for a Service${NC}"
    echo -e "${GREEN}3. Show Forward Dependencies (What a service needs)${NC}"
    echo -e "${GREEN}4. Show Reverse Dependencies (What needs a service)${NC}"
    echo -e "${GREEN}5. Show Detailed Dependency Properties${NC}"
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

    log_message "INFO" "Service dependency script started."
    check_systemd # Ensure systemd is available

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) list_all_services ;;
            2) search_services ;;
            3) show_forward_dependencies ;;
            4) show_reverse_dependencies ;;
            5) show_detailed_dependencies ;;
            0)
                echo -e "${CYAN}Exiting Service Dependency Mapper. Goodbye!${NC}"
                log_message "INFO" "Service dependency script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 5.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
