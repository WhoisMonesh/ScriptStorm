#!/bin/bash
# kernel-modules.sh - Kernel module manager
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides an interactive way to manage Linux kernel modules.
#              It can list loaded modules, display module information, load modules,
#              and unload modules.

# --- Configuration ---
LOG_FILE="/var/log/kernel-modules.log" # Log file for script actions and errors
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

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root.${NC}"
        echo -e "${RED}Please run with 'sudo ./kernel-modules.sh'.${NC}"
        log_message "ERROR" "Script not run as root."
        exit 1
    fi
    log_message "INFO" "Script is running as root."
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

# --- Module Management Functions ---
check_module_tools() {
    local all_found=true
    if ! check_command "lsmod"; then
        echo -e "${RED}ERROR: 'lsmod' command not found. Cannot list modules.${NC}"
        log_message "ERROR" "'lsmod' command not found."
        all_found=false
    fi
    if ! check_command "modinfo"; then
        echo -e "${RED}ERROR: 'modinfo' command not found. Cannot get module info.${NC}"
        log_message "ERROR" "'modinfo' command not found."
        all_found=false
    fi
    if ! check_command "modprobe"; then
        echo -e "${RED}ERROR: 'modprobe' command not found. Cannot load modules.${NC}"
        log_message "ERROR" "'modprobe' command not found."
        all_found=false
    fi
    if ! check_command "rmmod"; then
        echo -e "${RED}ERROR: 'rmmod' command not found. Cannot unload modules.${NC}"
        log_message "ERROR" "'rmmod' command not found."
        all_found=false
    fi

    if [ "$all_found" = false ]; then
        echo -e "${RED}Please install 'kmod' package or ensure your system has standard module utilities.${NC}"
        return 1
    fi
    log_message "INFO" "All module tools found."
    return 0
}

list_loaded_modules() {
    print_subsection "Loaded Kernel Modules"
    if ! check_module_tools; then
        return 1
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    lsmod | less -R # Use less for pagination
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Listed loaded kernel modules using 'lsmod'."
    pause_script
}

get_module_info() {
    print_subsection "Get Module Information"
    if ! check_module_tools; then
        return 1
    fi

    local module_name=$(read_user_input "Enter the module name (e.g., 'usbhid', 'ext4')")

    if [ -z "$module_name" ]; then
        echo -e "${RED}Module name cannot be empty. Aborting.${NC}"
        log_message "WARN" "Module name empty during modinfo attempt."
        return 1
    fi

    echo -e "${CYAN}Retrieving information for module '${module_name}'...${NC}"
    log_message "INFO" "Getting info for module '$module_name'."
    if ! modinfo "$module_name"; then
        echo -e "${RED}ERROR: Module '${module_name}' not found or no info available.${NC}"
        log_message "ERROR" "Module '$module_name' not found or info failed."
        return 1
    fi
    log_message "SUCCESS" "Info retrieved for module '$module_name'."
    return 0
}

load_module() {
    print_subsection "Load Kernel Module"
    if ! check_module_tools; then
        return 1
    fi

    local module_name=$(read_user_input "Enter the module name to load (e.g., 'nfs', 'vboxdrv')")
    local module_options=$(read_user_input "Enter module options (optional, e.g., 'debug=1')")

    if [ -z "$module_name" ]; then
        echo -e "${RED}Module name cannot be empty. Aborting.${NC}"
        log_message "WARN" "Module name empty during load attempt."
        return 1
    fi

    echo -e "${YELLOW}WARNING: Loading incorrect modules or modules with bad options can destabilize your system.${NC}"
    read -r -p "Are you sure you want to load module '${module_name}'? (y/N): " confirm_load
    if [[ ! "$confirm_load" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Aborting module load.${NC}"
        log_message "INFO" "Aborted module load for '$module_name' (user choice)."
        return 1
    fi

    echo -e "${CYAN}Loading module '${module_name}' with options '${module_options}'...${NC}"
    log_message "INFO" "Loading module '$module_name' with options '$module_options'."

    sudo modprobe "$module_name" $module_options
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Module '${module_name}' loaded successfully!${NC}"
        log_message "SUCCESS" "Module '$module_name' loaded successfully."
    else
        echo -e "${RED}ERROR: Failed to load module '${module_name}'. It might not exist, already be loaded, or have unmet dependencies.${NC}"
        log_message "ERROR" "Failed to load module '$module_name'."
        return 1
    fi
    display_loaded_modules # Show updated list
    return 0
}

unload_module() {
    print_subsection "Unload Kernel Module"
    if ! check_module_tools; then
        return 1
    fi

    list_loaded_modules # Show current loaded modules
    local module_name=$(read_user_input "Enter the module name to unload (e.g., 'usbhid', 'nf_conntrack')")

    if [ -z "$module_name" ]; then
        echo -e "${RED}Module name cannot be empty. Aborting.${NC}"
        log_message "WARN" "Module name empty during unload attempt."
        return 1
    fi

    # Check if module is actually loaded
    if ! lsmod | grep -q "^$module_name "; then
        echo -e "${YELLOW}Module '${module_name}' is not currently loaded. Nothing to unload.${NC}"
        log_message "WARN" "Attempted to unload non-loaded module '$module_name'."
        return 0
    fi

    echo -e "${YELLOW}WARNING: Unloading critical modules can crash your system or lose functionality!${NC}"
    read -r -p "Are you sure you want to unload module '${module_name}'? (y/N): " confirm_unload
    if [[ ! "$confirm_unload" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Aborting module unload.${NC}"
        log_message "INFO" "Aborted module unload for '$module_name' (user choice)."
        return 1
    fi

    echo -e "${CYAN}Unloading module '${module_name}'...${NC}"
    log_message "INFO" "Unloading module '$module_name'."

    sudo rmmod "$module_name"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Module '${module_name}' unloaded successfully!${NC}"
        log_message "SUCCESS" "Module '$module_name' unloaded successfully."
    else
        echo -e "${RED}ERROR: Failed to unload module '${module_name}'. It might be in use or have dependencies.${NC}"
        echo -e "${RED}You may need to unload its dependent modules first. Use 'modinfo -r ${module_name}' to see dependencies.${NC}"
        log_message "ERROR" "Failed to unload module '$module_name'."
        return 1
    fi
    display_loaded_modules # Show updated list
    return 0
}

explain_kernel_modules() {
    print_subsection "About Kernel Modules"
    echo -e "${CYAN}What are Kernel Modules?${NC}"
    echo "  - Kernel modules (often `.ko` files) are pieces of code that can be loaded"
    echo "    and unloaded into the kernel upon demand. They extend the functionality"
    echo "    of the kernel without requiring a system reboot."
    echo "  - They are typically used for device drivers (e.g., for network cards, USB devices),"
    echo "    filesystem drivers (e.g., NFS, EXT4), and other system functionalities."
    echo ""
    echo -e "${CYAN}Common Use Cases:${NC}"
    echo "  - ${GREEN}Hardware Support:${NC} Loading drivers for new hardware."
    echo "  - ${YELLOW}Troubleshooting:${NC} Unloading/reloading modules to resolve issues."
    echo "  - ${RED}Performance/Security:${NC} Removing unused modules to reduce kernel footprint"
    echo "    or potential attack surface (though modern kernels manage this well)."
    echo ""
    echo -e "${CYAN}Key Commands Used:${NC}"
    echo "  - ${MAGENTA}lsmod:${NC} Lists currently loaded kernel modules."
    echo "  - ${MAGENTA}modinfo:${NC} Displays information about a kernel module (author, description, parameters, dependencies)."
    echo "  - ${MAGENTA}modprobe:${NC} Adds or removes a module from the Linux kernel. It intelligently handles"
    echo "    dependencies, loading any required modules first. Preferred over `insmod`."
    echo "  - ${MAGENTA}rmmod:${NC} Removes a module from the Linux kernel. Only removes a module if it's not in use"
    echo "    and has no dependent modules loaded."
    echo ""
    echo -e "${CYAN}Important Warnings:${NC}"
    echo "  - ${RED}CAUTION:${NC} Incorrectly loading/unloading modules can cause system instability or crashes."
    echo "    Always know what a module does before manipulating it."
    echo "  - Changes made with `modprobe` or `rmmod` are temporary and will not persist"
    echo "    across reboots unless configured via files like `/etc/modules-load.d/*.conf`"
    echo "    or blacklisted in `/etc/modprobe.d/*.conf`."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Kernel modules explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Kernel Module Manager (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. List Loaded Modules${NC}"
    echo -e "${GREEN}2. Get Module Information${NC}"
    echo -e "${GREEN}3. Load Kernel Module${NC}"
    echo -e "${GREEN}4. Unload Kernel Module${NC}"
    echo -e "${GREEN}5. About Kernel Modules & Commands${NC}"
    echo -e "${YELLOW}0. Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -n "Enter your choice: "
}

main() {
    check_root

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Could not create log directory $(dirname "$LOG_FILE"). Exiting.${NC}"
        exit 1
    fi

    log_message "INFO" "Kernel module manager script started."

    # Pre-check essential module tools
    if ! check_module_tools; then
        log_message "ERROR" "Required kernel module tools not found. Exiting."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) list_loaded_modules ;;
            2) get_module_info; pause_script ;;
            3) load_module; pause_script ;;
            4) unload_module; pause_script ;;
            5) explain_kernel_modules; pause_script ;;
            0)
                echo -e "${CYAN}Exiting Kernel Module Manager. Goodbye!${NC}"
                log_message "INFO" "Kernel module manager script exited."
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
