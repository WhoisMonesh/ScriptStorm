#!/bin/bash
# locale-setter.sh - System locale configuration
# Version: 1.0
# Author: WhoisMonesh - Github: https://github.com/WhoisMonesh/ScriptStorm
# Date: June 19, 2025
# Description: This script provides an interactive way to manage system locale settings.
#              It can display current locale, list available locales, and set a new one.

# --- Configuration ---
LOG_FILE="/var/log/locale-setter.log" # Log file for script actions and errors
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
    local type="$1" # INFO, WARN, ERROR, SUCCESS, ALERT
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
        echo -e "${RED}Please run with 'sudo ./locale-setter.sh'.${NC}"
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

# --- Locale Configuration Functions ---
check_locale_tools() {
    local all_found=true
    if ! check_command "locale"; then
        echo -e "${RED}ERROR: 'locale' command not found. Cannot display or manage locales.${NC}"
        log_message "ERROR" "'locale' command not found."
        all_found=false
    fi
    # Check for locale-gen on Debian/Ubuntu or localectl on systemd systems
    if ! check_command "locale-gen" && ! check_command "localectl"; then
        echo -e "${RED}ERROR: Neither 'locale-gen' nor 'localectl' found. Cannot generate/set locales.${NC}"
        log_message "ERROR" "Neither 'locale-gen' nor 'localectl' found."
        all_found=false
    fi
    if [ "$all_found" = false ]; then
        return 1
    fi
    log_message "INFO" "Locale tools found."
    return 0
}

display_current_locale() {
    print_subsection "Current System Locale"
    if ! check_locale_tools; then
        return 1
    fi

    echo -e "${CYAN}-----------------------------------------------------${NC}"
    if check_command "localectl"; then
        localectl status
        log_message "INFO" "Displayed localectl status."
    elif check_command "locale"; then
        locale
        log_message "INFO" "Displayed locale command output."
    else
        echo -e "${RED}Cannot determine current locale. Missing 'localectl' or 'locale' command.${NC}"
        log_message "ERROR" "No command found to display current locale."
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Current locale display completed."
}

list_available_locales() {
    print_subsection "Available Locales"
    if ! check_locale_tools; then
        return 1
    fi

    echo -e "${CYAN}Listing all installed and available locales. This may take a moment...${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    if check_command "localectl"; then
        localectl list-locales | nl | less -R # For systemd systems
        log_message "INFO" "Listed locales using 'localectl list-locales'."
    elif [ -f "/etc/locale.gen" ]; then # For older Debian/Ubuntu
        grep -vE '^(#|$)' /etc/locale.gen | nl | less -R
        log_message "INFO" "Listed locales from /etc/locale.gen."
    else
        echo -e "${RED}Cannot list available locales. Neither 'localectl' nor '/etc/locale.gen' found.${NC}"
        log_message "ERROR" "Cannot list available locales."
        return 1
    fi
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    log_message "INFO" "Available locales display completed."
    pause_script
}

set_system_locale() {
    print_subsection "Set System Locale"
    if ! check_locale_tools; then
        return 1
    fi

    echo -e "${YELLOW}It is highly recommended to view the list of available locales (Option 2) first.${NC}"
    local desired_locale=$(read_user_input "Enter the desired locale (e.g., 'en_US.UTF-8', 'de_DE.UTF-8')")

    if [ -z "$desired_locale" ]; then
        echo -e "${RED}Locale cannot be empty. Aborting.${NC}"
        log_message "WARN" "Locale input was empty. Aborted setting locale."
        return 1
    fi

    echo -e "${CYAN}Attempting to set system locale to: ${desired_locale}${NC}"
    log_message "INFO" "Attempting to set system locale to '$desired_locale'."

    local locale_set_success=false

    if check_command "localectl"; then
        sudo localectl set-locale LANG="$desired_locale"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Locale set successfully using 'localectl'!${NC}"
            locale_set_success=true
            log_message "SUCCESS" "Locale successfully set to '$desired_locale' using localectl."
        else
            echo -e "${RED}ERROR: Failed to set locale using 'localectl'. Ensure locale is valid.${NC}"
            log_message "ERROR" "Failed to set locale '$desired_locale' using localectl."
        fi
    elif check_command "locale-gen" && [ -f "/etc/locale.gen" ]; then
        echo -e "${CYAN}Adding/uncommenting '$desired_locale' in /etc/locale.gen...${NC}"
        # Ensure the locale is uncommented or added
        if ! grep -q "^$desired_locale" /etc/locale.gen; then
            echo "$desired_locale" | sudo tee -a /etc/locale.gen >/dev/null
            log_message "INFO" "Added '$desired_locale' to /etc/locale.gen."
        else
            sudo sed -i "/^#\s*${desired_locale}/s/^#\s*//g" /etc/locale.gen
            log_message "INFO" "Uncommented '$desired_locale' in /etc/locale.gen."
        fi

        echo -e "${CYAN}Generating locales...${NC}"
        sudo locale-gen
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Locales generated successfully!${NC}"
            log_message "SUCCESS" "Locales generated."
            # Set the default locale in /etc/default/locale
            echo "LANG=\"$desired_locale\"" | sudo tee /etc/default/locale >/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Default locale set in /etc/default/locale.${NC}"
                locale_set_success=true
                log_message "SUCCESS" "Default locale set in /etc/default/locale."
            else
                echo -e "${RED}ERROR: Failed to set default locale in /etc/default/locale.${NC}"
                log_message "ERROR" "Failed to set default locale in /etc/default/locale."
            fi
        else
            echo -e "${RED}ERROR: Failed to generate locales. Ensure '$desired_locale' is a valid entry.${NC}"
            log_message "ERROR" "Failed to generate locales for '$desired_locale'."
        fi
    else
        echo -e "${RED}ERROR: No suitable tool found to set locale. (Neither localectl nor locale-gen/etc/locale.gen combo).${NC}"
        log_message "ERROR" "No suitable tool found to set locale."
    fi

    if [ "$locale_set_success" = true ]; then
        echo -e "${YELLOW}NOTE: For the changes to fully take effect, you may need to log out and log back in, or reboot.${NC}"
        log_message "INFO" "Advised user to re-login or reboot for full locale change effect."
        display_current_locale # Show new current locale settings
    else
        echo -e "${RED}Locale setting failed. Please review error messages and logs.${NC}"
        log_message "ERROR" "Locale setting process failed."
    fi
    return 0
}

explain_locale() {
    print_subsection "About System Locales"
    echo -e "${CYAN}What is a System Locale?${NC}"
    echo "  - A system locale defines language, character encoding, and regional"
    echo "    settings for your operating system and applications."
    echo "  - It influences how dates, times, currencies, and numbers are formatted,"
    echo "    what language messages are displayed in, and character set handling."
    echo ""
    echo -e "${CYAN}Components of a Locale:${NC}"
    echo "  - ${MAGENTA}Language Code:${NC} (e.g., 'en' for English, 'de' for German)"
    echo "  - ${MAGENTA}Country Code:${NC} (e.g., 'US' for United States, 'GB' for Great Britain, 'IN' for India)"
    echo "  - ${MAGENTA}Character Set:${NC} (e.g., 'UTF-8' for Unicode, 'ISO-8859-1')"
    echo "  - ${GREEN}Example:${NC} 'en_US.UTF-8' represents English, as used in the United States, with UTF-8 encoding."
    echo ""
    echo -e "${CYAN}Why configure Locales?${NC}"
    echo "  - Ensures applications display text and format data correctly."
    echo "  - Essential for correct display of special characters and symbols."
    echo "  - Prevents 'locale not set' warnings or errors in some shell environments."
    echo "  - Important for consistent behavior across different user accounts."
    echo ""
    echo -e "${CYAN}How Changes Take Effect:${NC}"
    echo "  - Changes to the system-wide locale typically require a user to log out"
    echo "    and log back in, or a full system reboot, to ensure all processes"
    echo "    inherit the new locale environment variables."
    echo -e "${CYAN}-------------------------------------------------------------------${NC}"
    log_message "INFO" "Locale explanation displayed."
    pause_script
}

# --- Main Script Logic ---
display_main_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}>>> System Locale Configuration (WhoisMonesh) <<<${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}1. Display Current Locale Settings${NC}"
    echo -e "${GREEN}2. List Available Locales${NC}"
    echo -e "${GREEN}3. Set New System Locale${NC}"
    echo -e "${GREEN}4. About System Locales${NC}"
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

    log_message "INFO" "Locale setter script started."

    # Pre-check essential locale tools
    if ! check_locale_tools; then
        log_message "ERROR" "Required locale tools not found. Exiting."
        exit 1
    fi

    local choice
    while true; do
        display_main_menu
        read -r choice

        case "$choice" in
            1) display_current_locale; pause_script ;;
            2) list_available_locales ;;
            3) set_system_locale; pause_script ;;
            4) explain_locale; pause_script ;;
            0)
                echo -e "${CYAN}Exiting System Locale Configuration. Goodbye!${NC}"
                log_message "INFO" "Locale setter script exited."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 0 and 4.${NC}"
                log_message "WARN" "Invalid menu choice: '$choice'."
                pause_script
                ;;
        esac
    done
}

# --- Script Entry Point ---
main
