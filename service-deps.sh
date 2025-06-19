#!/bin/bash

# service-deps.sh - Visualize systemd service dependencies
# Version: 2.0
# Author: Your Name
# Description: Maps service dependencies with visualization, reverse lookup, and detailed analysis

# Configuration
LOG_FILE="/var/log/service-deps.log"
MAX_DEPTH=5
DEFAULT_DEPTH=3

# Color definitions
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE" >&2
}

# Check if systemd is available
check_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}ERROR: This script requires systemd/systemctl${NC}" >&2
        log "ERROR" "Systemd not found - script requires systemctl"
        exit 1
    fi
}

# Get service status with color coding
get_service_status() {
    local service="$1"
    if systemctl is-active "$service" >/dev/null 2>&1; then
        echo -e "${GREEN}active${NC}"
    elif systemctl is-enabled "$service" >/dev/null 2>&1; then
        echo -e "${YELLOW}enabled${NC}"
    else
        echo -e "${RED}inactive${NC}"
    fi
}

# Display service information
show_service_info() {
    local service="$1"
    
    echo -e "\n${CYAN}=== Service Information ===${NC}"
    echo -e "Name: ${BLUE}$service${NC}"
    echo -e "Status: $(get_service_status "$service")"
    
    # Show description if available
    local description=$(systemctl show -p Description --value "$service" 2>/dev/null)
    [ -n "$description" ] && echo -e "Description: ${MAGENTA}$description${NC}"
    
    # Show main PID if running
    local pid=$(systemctl show -p MainPID --value "$service" 2>/dev/null)
    if [ "$pid" -ne 0 ] 2>/dev/null; then
        echo -e "Main PID: ${YELLOW}$pid${NC} ($(ps -p "$pid" -o comm= 2>/dev/null))"
    fi
    
    # Show memory usage if available
    local memory=$(systemctl show -p MemoryCurrent --value "$service" 2>/dev/null)
    [ -n "$memory" ] && echo -e "Memory: ${GREEN}$((memory/1024)) MB${NC}"
}

# Recursive function to show dependencies
show_dependencies() {
    local service="$1"
    local level="$2"
    local max_level="$3"
    local reverse="$4"
    local indent="$5"
    local last="$6"
    
    # Stop if we've reached max depth
    [ "$level" -gt "$max_level" ] && return
    
    # Prepare tree symbols
    local connector="├── "
    [ "$last" = "true" ] && connector="└── "
    
    # Get service status
    local status=$(get_service_status "$service")
    
    # Print service with proper indentation
    echo -e "${indent}${connector}${BLUE}$service${NC} [$status]"
    
    # Get dependencies based on mode
    local deps
    if [ "$reverse" = "true" ]; then
        deps=$(systemctl list-dependencies --reverse --plain "$service" 2>/dev/null | grep -v "^$service$")
    else
        deps=$(systemctl list-dependencies --plain "$service" 2>/dev/null | grep -v "^$service$")
    fi
    
    # Count dependencies for proper tree display
    local count=$(echo "$deps" | wc -l)
    local new_indent="${indent}    "
    
    # Recursively process each dependency
    local i=1
    while read -r dep; do
        [ -z "$dep" ] && continue
        
        local is_last="false"
        [ "$i" -eq "$count" ] && is_last="true"
        
        show_dependencies "$dep" $((level + 1)) "$max_level" "$reverse" "$new_indent" "$is_last"
        i=$((i + 1))
    done <<< "$deps"
}

# Main function to analyze service
analyze_service() {
    local service="$1"
    local depth="$2"
    local reverse="$3"
    
    # Validate service exists
    if ! systemctl list-unit-files | grep -q "^$service"; then
        echo -e "${RED}Error: Service '$service' not found${NC}" >&2
        log "ERROR" "Service $service not found"
        return 1
    fi
    
    show_service_info "$service"
    
    echo -e "\n${CYAN}=== Dependency Tree ===${NC}"
    if [ "$reverse" = "true" ]; then
        echo -e "${YELLOW}(Showing what depends on $service)${NC}"
    else
        echo -e "${YELLOW}(Showing what $service depends on)${NC}"
    fi
    
    show_dependencies "$service" 1 "$depth" "$reverse" "" "true"
    
    # Show additional dependency information
    echo -e "\n${CYAN}=== Detailed Dependency Info ===${NC}"
    systemctl show "$service" --property=Requires --property=Wants --property=Requisite \
        --property=Conflicts --property=Before --property=After --property=OnFailure \
        --property=PartOf --property=ConsistsOf --property=RequiredBy --property=WantedBy \
        --property=BoundBy --property=RequiredByOverridable --property=RequiredBy= \
        --property=WantedBy= --property=RequiredBy= --property=Before= --property=After= \
        2>/dev/null | grep -v "^$" | sort | sed "s/=/ = /"
}

# List all services with status
list_all_services() {
    echo -e "${CYAN}Listing all services (systemd units):${NC}"
    systemctl list-units --type=service --all --no-pager --no-legend | \
        awk '{printf "%-40s %s\n", $1, $4}' | \
        while read -r line; do
            local service=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            case "$status" in
                active) echo -e "${BLUE}$service${NC} ${GREEN}$status${NC}" ;;
                enabled) echo -e "${BLUE}$service${NC} ${YELLOW}$status${NC}" ;;
                *) echo -e "${BLUE}$service${NC} ${RED}$status${NC}" ;;
            esac
        done | less -FRX
}

# Search for services by name
search_services() {
    local term="$1"
    echo -e "${CYAN}Searching for services matching: ${YELLOW}$term${NC}"
    systemctl list-unit-files --type=service --no-legend --no-pager | \
        grep -i "$term" | awk '{print $1}' | \
        while read -r service; do
            local status=$(systemctl is-active "$service" 2>/dev/null)
            case "$status" in
                active) echo -e "${BLUE}$service${NC} ${GREEN}$status${NC}" ;;
                *) echo -e "${BLUE}$service${NC} ${RED}inactive${NC}" ;;
            esac
        done
}

# Display help information
show_help() {
    echo -e "${CYAN}Usage: $0 [options] [service_name]${NC}"
    echo -e "Options:"
    echo -e "  -a, --all           List all available services"
    echo -e "  -s, --search TERM   Search for services matching TERM"
    echo -e "  -r, --reverse       Show reverse dependencies (what depends on this service)"
    echo -e "  -d, --depth NUM     Set maximum depth for dependency tree (default: $DEFAULT_DEPTH)"
    echo -e "  -h, --help          Show this help message"
    echo -e "\nExamples:"
    echo -e "  $0 nginx.service          # Show nginx service dependencies"
    echo -e "  $0 -r sshd.service        # Show what depends on sshd"
    echo -e "  $0 -d 5 docker.service    # Show docker dependencies with depth 5"
    echo -e "  $0 -a                     # List all services"
    echo -e "  $0 -s network             # Search for services with 'network' in name"
}

# Main script execution
main() {
    check_systemd
    
    local service=""
    local depth=$DEFAULT_DEPTH
    local reverse=false
    local action="analyze"
    local search_term=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                action="list_all"
                shift
                ;;
            -s|--search)
                action="search"
                search_term="$2"
                shift 2
                ;;
            -r|--reverse)
                reverse=true
                shift
                ;;
            -d|--depth)
                depth="$2"
                if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Error: Depth must be a number${NC}" >&2
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                show_help
                exit 1
                ;;
            *)
                if [ -z "$service" ]; then
                    service="$1"
                    # Add .service suffix if not present
                    [[ "$service" != *.* ]] && service="${service}.service"
                else
                    echo -e "${RED}Error: Only one service can be specified${NC}" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate depth
    if [ "$depth" -gt "$MAX_DEPTH" ]; then
        echo -e "${YELLOW}Warning: Depth too large, setting to max $MAX_DEPTH${NC}"
        depth=$MAX_DEPTH
    fi
    
    # Execute the requested action
    case "$action" in
        list_all)
            list_all_services
            ;;
        search)
            if [ -z "$search_term" ]; then
                echo -e "${RED}Error: Search term cannot be empty${NC}" >&2
                exit 1
            fi
            search_services "$search_term"
            ;;
        analyze)
            if [ -z "$service" ]; then
                echo -e "${CYAN}No service specified. Showing help:${NC}"
                show_help
                exit 0
            fi
            analyze_service "$service" "$depth" "$reverse"
            ;;
    esac
    
    log "INFO" "Script completed successfully"
}

# Run main function with all arguments
main "$@"
