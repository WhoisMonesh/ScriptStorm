#!/bin/bash

# zombie-killer.sh - Cleans Up Zombie Processes
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script identifies zombie (defunct) processes and their parent processes.
#              It provides information about zombies and a HIGHLY CAUTIOUS option to send
#              a signal to the parent process, which is the only way to clear a zombie.
#              Directly killing a zombie process is not possible.

# --- Configuration ---
LOG_FILE="/var/log/zombie-killer.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# Threshold for alerting if more than this many zombies are found
ZOMBIE_ALERT_THRESHOLD=10

# Notification Settings
NOTIFICATION_EMAIL="your_email@example.com" # Email address to send alerts
SENDER_EMAIL="zombie-monitor@yourdomain.com" # Sender email for alerts

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

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root to manage processes.${NC}"
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

# --- Zombie Process Management Functions ---

find_and_list_zombies() {
    print_subsection "Finding Zombie Processes"
    echo -e "${CYAN}Searching for zombie processes and their parent PIDs...${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    # Get zombie processes: State 'Z' (zombie)
    # ps -eo pid,ppid,user,stat,cmd --forest : PID, PPID, USER, STAT, CMD (with tree view)
    # awk '{if ($4 == "Z") print $0}' : Filter for State 'Z'
    # tail -n +2 : Skip header (if ps gives one)
    local zombies_raw=$(ps -eo pid,ppid,user,stat,cmd | awk '{if ($4 == "Z") print $0}')
    local zombie_count=0
    
    if [ -z "$zombies_raw" ]; then
        echo -e "${GREEN}No zombie processes found! System is clean.${NC}"
        log_message "INFO" "No zombie processes found."
    else
        echo -e "${MAGENTA}  PID    PPID   USER    STAT  COMMAND${NC}"
        echo -e "${MAGENTA}-------------------------------------------------------------------${NC}"
        echo "$zombies_raw" | while read -r pid ppid user stat cmd; do
            zombie_count=$((zombie_count + 1))
            printf "%6s %7s %-8s %-5s %s\n" "$pid" "$ppid" "$user" "$stat" "$cmd"
        done
        echo -e "${CYAN}-------------------------------------------------------------------${NC}"
        echo -e "${CYAN}Total zombie processes found: $zombie_count${NC}"
        log_message "INFO" "Found $zombie_count zombie processes."

        if (( zombie_count > ZOMBIE_ALERT_THRESHOLD )); then
            log_message "ALERT" "High number of zombie processes detected: $zombie_count. Threshold: $ZOMBIE_ALERT_THRESHOLD."
            send_email_alert "SYSTEM ALERT: High Zombie Process Count on $(hostname)" \
                             "A high number of zombie processes ($zombie_count) has been detected on $(hostname).\n\n" \
                             "Summary:\n$zombies_raw\n\n" \
                             "Please investigate the parent processes."
        fi
    fi
    pause_script
    return "$zombie_count" # Return number of zombies found
}

kill_parent_of_zombie() {
    print_subsection "Attempt to Clean Up Zombie Process (via Parent)"
    echo -e "${RED}WARNING: You CANNOT directly kill a zombie process.${NC}"
    echo -e "${RED}To clear a zombie, its PARENT process must reap it.${NC}"
    echo -e "${RED}Attempting to kill or signal a parent process can lead to data loss or system instability!${NC}"
    echo -e "${RED}ONLY PROCEED IF YOU UNDERSTAND THE RISKS!${NC}"

    local zombies_found
    zombies_found=$(ps -eo pid,ppid,user,stat,cmd | awk '{if ($4 == "Z") print $0}')

    if [ -z "$zombies_found" ]; then
        echo -e "${GREEN}No zombie processes found to attempt cleanup.${NC}"
        log_message "INFO" "No zombies found for parent kill attempt."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Found these zombie processes:${NC}"
    echo -e "${MAGENTA}  NUM  PID    PPID   USER    STAT  COMMAND${NC}"
    echo -e "${MAGENTA}-------------------------------------------------------------------${NC}"
    local count=1
    local zombie_map=() # Array to map user choice to zombie details
    echo "$zombies_found" | while read -r pid ppid user stat cmd; do
        printf "%5s %6s %7s %-8s %-5s %s\n" "$count" "$pid" "$ppid" "$user" "$stat" "$cmd"
        zombie_map+=("$pid $ppid $user $cmd") # Store relevant details
        count=$((count+1))
    done
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"

    local choice=$(read_user_input "Enter the number of the zombie whose parent you want to signal (0 to cancel)" "")
    if [[ "$choice" -eq 0 ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        log_message "INFO" "Zombie parent kill attempt cancelled."
        pause_script
        return 0
    fi

    if [[ "$choice" -ge 1 && "$choice" -le ${#zombie_map[@]} ]]; then
        local selected_zombie_info="${zombie_map[$((choice-1))]}"
        local zombie_pid=$(echo "$selected_zombie_info" | awk '{print $1}')
        local parent_pid=$(echo "$selected_zombie_info" | awk '{print $2}')
        local parent_user=$(echo "$selected_zombie_info" | awk '{print $3}')
        local zombie_cmd=$(echo "$selected_zombie_info" | cut -d' ' -f4-)

        echo -e "${CYAN}Selected Zombie: PID=$zombie_pid, CMD='$zombie_cmd'${NC}"
        echo -e "${CYAN}Parent Process: PID=$parent_pid, User=$parent_user${NC}"
        if [ "$parent_pid" -eq 1 ]; then
            echo -e "${YELLOW}WARNING: Parent PID is 1 (init/systemd). These zombies should be reaped automatically.${NC}"
            echo -e "${YELLOW}If they persist, it indicates a deeper issue or systemd bug. Signaling PID 1 is NOT recommended.${NC}"
            log_message "WARN" "Attempted to signal PID 1 parent of zombie $zombie_pid."
            pause_script
            return 1
        fi

        local signal_type=$(read_user_input "Enter signal to send to parent (e.g., SIGCHLD, SIGTERM, SIGKILL, default: SIGCHLD)" "SIGCHLD")

        echo -e "${RED}CRITICAL WARNING: Sending $signal_type to PID $parent_pid (parent of zombie $zombie_pid). This can disrupt the parent process!${NC}"
        if confirm_action "Are you absolutely sure you want to send $signal_type to PID $parent_pid?"; then
            sudo kill -s "$signal_type" "$parent_pid"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Signal '$signal_type' sent to parent PID $parent_pid. Monitor for zombie removal.${NC}"
                log_message "SUCCESS" "Sent signal '$signal_type' to parent $parent_pid of zombie $zombie_pid."
                send_email_alert "Zombie Cleanup Action: Parent Signaled" "Sent signal '$signal_type' to parent PID $parent_pid (user: $parent_user, zombie cmd: $zombie_cmd) on $(hostname). Please verify zombie removal."
            else
                echo -e "${RED}ERROR: Failed to send signal to parent PID $parent_pid.${NC}"
                log_message "ERROR" "Failed to send signal '$signal_type' to parent $parent_pid."
            fi
        else
            log_message "INFO" "Signaling parent of zombie $zombie_pid cancelled."
        fi
    else
        echo -e "${RED}Invalid choice.${NC}"
    fi
    pause_script
}

explain_zombies() {
    print_subsection "Understanding Zombie Processes"
    echo -e "${CYAN}What is a Zombie Process (Defunct Process)?${NC}"
    echo "  A zombie process is a process that has completed its execution but still has an"
    echo "  entry in the process table. This happens because its parent process has not yet"
    echo "  'reaped' it, meaning it hasn't called the 'wait()' system call to read its exit status."
    echo ""
    echo -e "${CYAN}Why do they occur?${NC}"
    echo "  They are usually temporary. A normal parent process will eventually call 'wait()'"
    echo "  and clear the zombie. Problems arise when:"
    echo "  - The parent process is buggy and never calls 'wait()'."
    echo "  - The parent process itself crashes or terminates before reaping its child."
    echo "    In this case, the zombie child is 'reparented' to the 'init' process (PID 1) or"
    echo "    'systemd' on modern Linux systems. PID 1 is specially designed to reap orphan"
    echo "    processes, including zombies. Persistent zombies with PID 1 as parent might"
    echo "    indicate a bug in the init system or unusual kernel state."
    echo ""
    echo -e "${CYAN}Do Zombies consume resources?${NC}"
    echo "  Zombies consume very minimal resources: just an entry in the process table (PID)."
    echo "  They don't run, execute code, or consume CPU/memory. However, a large number of"
    echo "  zombies can exhaust the PID limit, preventing new processes from starting."
    echo ""
    echo -e "${CYAN}How to 'kill' a Zombie?${NC}"
    echo "  You CANNOT kill a zombie process directly using 'kill -9 <PID>'. It's already 'dead'."
    echo "  The ONLY way to remove a zombie is for its parent process to reap it."
    echo "  - If the parent is still running and misbehaving, you might try to signal the parent"
    echo "    process (e.g., SIGCHLD, SIGTERM) to encourage it to reap its child. Killing the"
    echo "    parent process will also orphan the zombie, and PID 1 will usually reap it."
    echo "  - If the parent is PID 1, and the zombie persists, a system reboot is usually the"
    echo "    only practical way to clear them, as it indicates a deeper issue."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Zombie explanation displayed."
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Zombie Process Killer (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}Zombie Alert Threshold: ${ZOMBIE_ALERT_THRESHOLD} processes${NC}"
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Find and List Zombie Processes${NC}"
    echo -e "${RED}2. Attempt to Clean Up Zombie (Signal Parent) - DANGEROUS!${NC}"
    echo -e "${GREEN}3. Explain Zombie Processes${NC}"
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

    log_message "INFO" "Zombie killer script started."
    check_root # This script *requires* root.

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) find_and_list_zombies ;;
            2) kill_parent_of_zombie ;;
            3) explain_zombies ;;
            0)
                echo -e "${CYAN}Exiting Zombie Process Killer. Goodbye!${NC}"
                log_message "INFO" "Zombie killer script exited."
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
