#!/bin/bash
# Phase 01 - Step 05

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_error() { echo -e "${RED}✗ ERROR:${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✓ SUCCESS:${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ INFO:${NC} $1"; }

# Function to validate timezone
validate_timezone() {
    local tz="$1"
    if timedatectl list-timezones | grep -Fxq "$tz"; then
        return 0
    else
        return 1
    fi
}

# Function to list available timezones
list_timezones() {
    print_info "Available timezones:"
    timedatectl list-timezones | grep -E "^(America|Europe|Asia|Australia|Africa)" | head -20
    echo ""
    print_info "Use 'timedatectl list-timezones' to see all available timezones"
}

# Function to show current timezone
show_current() {
    echo "─────────────────────────────────────────"
    echo "Current system timezone:"
    timedatectl show --property=Timezone --value
    echo ""
    echo "Full system time details:"
    timedatectl status
    echo "─────────────────────────────────────────"
}

# Function to set timezone
set_timezone() {
    local tz="$1"
    
    # Check if running with sudo
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Please run with sudo."
        return 1
    fi
    
    # Validate timezone
    if ! validate_timezone "$tz"; then
        print_error "Invalid timezone: $tz"
        print_info "Use 'timedatectl list-timezones' to see valid timezones"
        return 1
    fi
    
    # Show current timezone
    print_info "Current timezone: $(timedatectl show --property=Timezone --value)"
    
    # Set timezone
    print_info "Setting timezone to: $tz"
    if timedatectl set-timezone "$tz"; then
        print_success "Timezone successfully changed to: $tz"
        
        # Show updated status
        echo ""
        print_info "Updated system time:"
        timedatectl status | grep -E "Time zone|Local time|Universal time|RTC time"
        return 0
    else
        print_error "Failed to set timezone"
        return 1
    fi
}

# Function to handle interactive mode
interactive_mode() {
    print_info "Interactive mode:"
    echo ""
    show_current
    echo ""
    
    read -p "Enter new timezone (or press Enter to list options): " user_input
    
    if [[ -z "$user_input" ]]; then
        list_timezones
        echo ""
        read -p "Enter timezone: " user_input
    fi
    
    if [[ -n "$user_input" ]]; then
        if [[ "$user_input" == "cancel" ]]; then
            print_info "Operation cancelled"
            return 0
        fi
        set_timezone "$user_input"
    else
        print_error "No timezone provided"
        return 1
    fi
}

# Main script execution
main() {
    case "${1:-}" in
        -h|--help)
            cat << EOF
Timezone Set Script

USAGE:
    $(basename "$0") [OPTIONS] [TIMEZONE]

OPTIONS:
    -h, --help          Show this help message
    -i, --interactive   Interactive mode (guided setup)
    -l, --list         List available timezones
    -s, --status       Show current timezone status
    -v, --verbose      Verbose output

EXAMPLES:
    $(basename "$0") Europe/Madrid
    $(basename "$0") America/New_York
    $(basename "$0") -i
    $(basename "$0") -l

REQUIREMENTS:
    - Root/sudo privileges
    - systemd (timedatectl)
EOF
            exit 0
            ;;
        -i|--interactive)
            interactive_mode
            ;;
        -l|--list)
            list_timezones
            ;;
        -s|--status)
            show_current
            ;;
        -v|--verbose)
            set -x
            shift
            if [[ -n "${1:-}" ]]; then
                set_timezone "$1"
            else
                print_error "No timezone specified for verbose mode"
                exit 1
            fi
            ;;
        "")
            interactive_mode
            ;;
        *)
            set_timezone "$1"
            ;;
    esac
}

# Run main function with all arguments
main "$@"