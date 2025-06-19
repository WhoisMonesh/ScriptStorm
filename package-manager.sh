#!/bin/bash

# package-manager.sh - Unified Package Management Wrapper
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides a unified interface for common package management
#              tasks across different Linux distributions (Debian/Ubuntu, RHEL/Fedora,
#              Arch, openSUSE). It detects the native package manager and executes
#              the corresponding commands.

# --- Configuration ---
LOG_FILE="/var/log/package-manager.log" # Log file for script actions and errors
DATE_FORMAT="+%Y-%m-%d_%H-%M-%S"

# --- Colors for better readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Global Variables for Detected Package Manager ---
PKG_MANAGER=""          # e.g., "apt", "dnf", "yum", "pacman", "zypper"
PKG_UPDATE_CMD=""       # Command to update package lists
PKG_UPGRADE_CMD=""      # Command to upgrade installed packages
PKG_INSTALL_CMD=""      # Command to install packages
PKG_REMOVE_CMD=""       # Command to remove packages
PKG_SEARCH_CMD=""       # Command to search for packages
PKG_CLEAN_CMD=""        # Command to clean package cache
PKG_AUTOREMOVE_CMD=""   # Command to autoremove dependencies (if available)

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
        echo -e "${RED}ERROR: This script must be run as root to perform package management operations.${NC}"
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

# --- Package Manager Detection ---

detect_package_manager() {
    log_message "INFO" "Detecting package manager..."

    if check_command "apt"; then
        PKG_MANAGER="apt"
        PKG_UPDATE_CMD="sudo apt update"
        PKG_UPGRADE_CMD="sudo apt upgrade"
        PKG_INSTALL_CMD="sudo apt install -y"
        PKG_REMOVE_CMD="sudo apt remove -y"
        PKG_SEARCH_CMD="apt search"
        PKG_CLEAN_CMD="sudo apt clean"
        PKG_AUTOREMOVE_CMD="sudo apt autoremove -y"
        echo -e "${GREEN}Detected package manager: APT (Debian/Ubuntu based system)${NC}"
    elif check_command "dnf"; then
        PKG_MANAGER="dnf"
        PKG_UPDATE_CMD="sudo dnf check-update" # dnf update implies upgrade
        PKG_UPGRADE_CMD="sudo dnf upgrade -y"
        PKG_INSTALL_CMD="sudo dnf install -y"
        PKG_REMOVE_CMD="sudo dnf remove -y"
        PKG_SEARCH_CMD="dnf search"
        PKG_CLEAN_CMD="sudo dnf clean all"
        PKG_AUTOREMOVE_CMD="sudo dnf autoremove -y"
        echo -e "${GREEN}Detected package manager: DNF (Fedora/RHEL 8+ based system)${NC}"
    elif check_command "yum"; then
        PKG_MANAGER="yum"
        PKG_UPDATE_CMD="sudo yum check-update"
        PKG_UPGRADE_CMD="sudo yum update -y"
        PKG_INSTALL_CMD="sudo yum install -y"
        PKG_REMOVE_CMD="sudo yum remove -y"
        PKG_SEARCH_CMD="yum search"
        PKG_CLEAN_CMD="sudo yum clean all"
        # yum does not have a direct 'autoremove' like apt/dnf, rather 'yum autoremove' (which is just 'remove')
        # We'll omit PKG_AUTOREMOVE_CMD for yum to avoid confusion.
        echo -e "${GREEN}Detected package manager: YUM (Older CentOS/RHEL 7- based system)${NC}"
    elif check_command "pacman"; then
        PKG_MANAGER="pacman"
        PKG_UPDATE_CMD="sudo pacman -Sy"
        PKG_UPGRADE_CMD="sudo pacman -Syu"
        PKG_INSTALL_CMD="sudo pacman -S --noconfirm"
        PKG_REMOVE_CMD="sudo pacman -Rns --noconfirm" # Removes dependencies not used by other packages
        PKG_SEARCH_CMD="pacman -Ss"
        PKG_CLEAN_CMD="sudo pacman -Scc --noconfirm" # Cleans all cached packages
        PKG_AUTOREMOVE_CMD="" # Pacman -Rns handles autoremove on package removal
        echo -e "${GREEN}Detected package manager: Pacman (Arch Linux based system)${NC}"
    elif check_command "zypper"; then
        PKG_MANAGER="zypper"
        PKG_UPDATE_CMD="sudo zypper refresh"
        PKG_UPGRADE_CMD="sudo zypper update -y"
        PKG_INSTALL_CMD="sudo zypper install -y"
        PKG_REMOVE_CMD="sudo zypper remove -y"
        PKG_SEARCH_CMD="zypper search"
        PKG_CLEAN_CMD="sudo zypper clean"
        PKG_AUTOREMOVE_CMD="sudo zypper remove --clean-deps -y" # Remove unused dependencies
        echo -e "${GREEN}Detected package manager: Zypper (openSUSE/SLES based system)${NC}"
    else
        echo -e "${RED}ERROR: No supported package manager (apt, dnf, yum, pacman, zypper) detected.${NC}"
        log_message "ERROR" "No supported package manager detected."
        exit 1
    fi
    log_message "SUCCESS" "Package manager '$PKG_MANAGER' detected."
    pause_script
}

# --- Package Management Operations ---

pm_update_lists() {
    print_subsection "Update Package Lists"
    echo -e "${CYAN}Running $PKG_MANAGER update...${NC}"
    log_message "INFO" "Running '$PKG_UPDATE_CMD'."
    eval "$PKG_UPDATE_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Package lists updated successfully.${NC}"
        log_message "SUCCESS" "Package lists updated."
    else
        echo -e "${RED}ERROR: Failed to update package lists.${NC}"
        log_message "ERROR" "Failed to update package lists."
    fi
    pause_script
}

pm_upgrade_system() {
    print_subsection "Upgrade Installed Packages"
    echo -e "${CYAN}Running $PKG_MANAGER upgrade...${NC}"
    log_message "INFO" "Running '$PKG_UPGRADE_CMD'."
    eval "$PKG_UPGRADE_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}System upgraded successfully.${NC}"
        log_message "SUCCESS" "System upgraded."
    else
        echo -e "${RED}ERROR: Failed to upgrade system.${NC}"
        log_message "ERROR" "Failed to upgrade system."
    fi
    pause_script
}

pm_install_package() {
    print_subsection "Install Package(s)"
    local package_names=$(read_user_input "Enter package name(s) to install (space-separated)" "")
    if [ -z "$package_names" ]; then
        echo -e "${YELLOW}No packages specified for installation.${NC}"
        log_message "WARN" "Install package skipped: no packages specified."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Installing '$package_names' using $PKG_MANAGER...${NC}"
    log_message "INFO" "Running '$PKG_INSTALL_CMD $package_names'."
    eval "$PKG_INSTALL_CMD $package_names"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Package(s) '$package_names' installed successfully.${NC}"
        log_message "SUCCESS" "Package(s) '$package_names' installed."
    else
        echo -e "${RED}ERROR: Failed to install package(s) '$package_names'.${NC}"
        log_message "ERROR" "Failed to install package(s) '$package_names'."
    fi
    pause_script
}

pm_remove_package() {
    print_subsection "Remove Package(s)"
    local package_names=$(read_user_input "Enter package name(s) to remove (space-separated)" "")
    if [ -z "$package_names" ]; then
        echo -e "${YELLOW}No packages specified for removal.${NC}"
        log_message "WARN" "Remove package skipped: no packages specified."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Removing '$package_names' using $PKG_MANAGER...${NC}"
    log_message "INFO" "Running '$PKG_REMOVE_CMD $package_names'."
    eval "$PKG_REMOVE_CMD $package_names"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Package(s) '$package_names' removed successfully.${NC}"
        log_message "SUCCESS" "Package(s) '$package_names' removed."
    else
        echo -e "${RED}ERROR: Failed to remove package(s) '$package_names'.${NC}"
        log_message "ERROR" "Failed to remove package(s) '$package_names'."
    fi
    pause_script
}

pm_search_package() {
    print_subsection "Search for Package(s)"
    local search_term=$(read_user_input "Enter package search term" "")
    if [ -z "$search_term" ]; then
        echo -e "${YELLOW}No search term specified.${NC}"
        log_message "WARN" "Package search skipped: no term specified."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Searching for '$search_term' using $PKG_MANAGER...${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Running '$PKG_SEARCH_CMD $search_term'."
    eval "$PKG_SEARCH_CMD $search_term"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Search completed.${NC}"
        log_message "SUCCESS" "Package search for '$search_term' completed."
    else
        echo -e "${RED}ERROR: Search failed.${NC}"
        log_message "ERROR" "Package search for '$search_term' failed."
    fi
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    pause_script
}

pm_clean_cache() {
    print_subsection "Clean Package Cache"
    if [ -z "$PKG_CLEAN_CMD" ]; then
        echo -e "${YELLOW}WARNING: '$PKG_MANAGER' does not have a direct cache clean command in this script's configuration.${NC}"
        log_message "WARN" "Package manager '$PKG_MANAGER' does not have a direct cache clean command configured."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Cleaning $PKG_MANAGER cache...${NC}"
    log_message "INFO" "Running '$PKG_CLEAN_CMD'."
    eval "$PKG_CLEAN_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Package cache cleaned successfully.${NC}"
        log_message "SUCCESS" "Package cache cleaned."
    else
        echo -e "${RED}ERROR: Failed to clean package cache.${NC}"
        log_message "ERROR" "Failed to clean package cache."
    fi
    pause_script
}

pm_autoremove_dependencies() {
    print_subsection "Autoremove Unused Dependencies"
    if [ -z "$PKG_AUTOREMOVE_CMD" ]; then
        echo -e "${YELLOW}WARNING: '$PKG_MANAGER' does not have an autoremove command or it's handled differently.${NC}"
        log_message "WARN" "Package manager '$PKG_MANAGER' does not have an autoremove command configured."
        pause_script
        return 0
    fi

    echo -e "${CYAN}Running $PKG_MANAGER autoremove...${NC}"
    log_message "INFO" "Running '$PKG_AUTOREMOVE_CMD'."
    eval "$PKG_AUTOREMOVE_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Unused dependencies autoremoved successfully.${NC}"
        log_message "SUCCESS" "Unused dependencies autoremoved."
    else
        echo -e "${RED}ERROR: Failed to autoremove unused dependencies.${NC}"
        log_message "ERROR" "Failed to autoremove unused dependencies."
    fi
    pause_script
}

# --- Main Script Logic ---

display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> Unified Package Manager (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${MAGENTA}Detected Manager: ${PKG_MANAGER^}${NC}" # Capitalize first letter
    echo -e "${BLUE}-----------------------------------------------------${NC}"
    echo -e "${GREEN}1. Update Package Lists${NC}"
    echo -e "${GREEN}2. Upgrade Installed Packages${NC}"
    echo -e "${GREEN}3. Install Package(s)${NC}"
    echo -e "${GREEN}4. Remove Package(s)${NC}"
    echo -e "${GREEN}5. Search Package(s)${NC}"
    echo -e "${GREEN}6. Clean Package Cache${NC}"
    if [ -n "$PKG_AUTOREMOVE_CMD" ]; then # Only show if command exists
        echo -e "${GREEN}7. Autoremove Unused Dependencies${NC}"
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

    log_message "INFO" "Package manager script started."
    check_root # This script requires root for operations.
    detect_package_manager

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) pm_update_lists ;;
            2) pm_upgrade_system ;;
            3) pm_install_package ;;
            4) pm_remove_package ;;
            5) pm_search_package ;;
            6) pm_clean_cache ;;
            7)
                if [ -n "$PKG_AUTOREMOVE_CMD" ]; then
                    pm_autoremove_dependencies
                else
                    echo -e "${RED}Invalid choice. Option 7 is not available for $PKG_MANAGER.${NC}"
                    log_message "WARN" "Invalid menu choice: '$choice' (autoremove not available)."
                    pause_script
                fi
                ;;
            0)
                echo -e "${CYAN}Exiting Unified Package Manager. Goodbye!${NC}"
                log_message "INFO" "Package manager script exited."
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
