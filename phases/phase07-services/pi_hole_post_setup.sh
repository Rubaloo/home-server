#!/bin/bash

# Pi-hole Post-Installation Management Script
# Handles configuration, updates, backups, and maintenance

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
PIHOLE_DIR="/srv/docker/pihole"
BACKUP_DIR="/srv/docker/backups/pihole"
PIHOLE_CONTAINER="pihole"
PIHOLE_IP=""
PIHOLE_PASSWORD=""

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}=== $1 ===${NC}"
    echo ""
}

# Function to prompt yes/no
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# Function to prompt for input with default value
ask_input() {
    local prompt="$1"
    local default="$2"
    local response

    read -p "$prompt [$default]: " response
    echo "${response:-$default}"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Check if Pi-hole is running
check_pihole_status() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PIHOLE_CONTAINER}$"; then
        return 0
    else
        return 1
    fi
}

# Get Pi-hole configuration
get_pihole_config() {
    # Try to get IP from running container
    if check_pihole_status; then
        PIHOLE_IP=$(docker inspect pihole 2>/dev/null | grep -o '"FTLCONF_LOCAL_IPV4=[^"]*"' | cut -d'=' -f2 | tr -d '"' || echo "")
        PIHOLE_PASSWORD=$(docker inspect pihole 2>/dev/null | grep -o '"WEBPASSWORD=[^"]*"' | cut -d'=' -f2 | tr -d '"' || echo "")
    fi
    
    # If not found, try compose file
    if [ -z "$PIHOLE_IP" ]; then
        if [ -f "$PIHOLE_DIR/compose.yaml" ]; then
            PIHOLE_IP=$(grep FTLCONF_LOCAL_IPV4 "$PIHOLE_DIR/compose.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
            PIHOLE_PASSWORD=$(grep WEBPASSWORD "$PIHOLE_DIR/compose.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
        elif [ -f "$PIHOLE_DIR/docker-compose.yml" ]; then
            PIHOLE_IP=$(grep FTLCONF_LOCAL_IPV4 "$PIHOLE_DIR/docker-compose.yml" 2>/dev/null | cut -d'"' -f2 || echo "")
            PIHOLE_PASSWORD=$(grep WEBPASSWORD "$PIHOLE_DIR/docker-compose.yml" 2>/dev/null | cut -d'"' -f2 || echo "")
        fi
    fi
    
    # Set defaults if still empty
    [ -z "$PIHOLE_IP" ] && PIHOLE_IP="192.168.1.50"
    [ -z "$PIHOLE_PASSWORD" ] && PIHOLE_PASSWORD="admin"
}

# Configure static IP for Pi-hole server using Netplan
configure_static_ip() {
    clear
    print_header "Configure Static IP for Pi-hole Server (Netplan)"
    
    echo "A static IP address is essential for Pi-hole to work reliably."
    echo "This ensures your DNS server address never changes."
    echo ""
    
    # Check if Netplan is available
    if ! command -v netplan &> /dev/null; then
        print_error "Netplan is not installed on this system"
        echo ""
        echo "Netplan is required for this configuration."
        echo "Install it with: sudo apt install netplan.io"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    # Detect current network configuration
    print_status "Detecting current network configuration..."
    echo ""
    
    # List available network interfaces
    echo -e "${BOLD}Available network interfaces:${NC}"
    ip -br addr show | grep -v "lo" | awk '{print "  " $1 " - " $3}'
    echo ""
    
    # Detect primary interface
    local default_interface=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    local current_ip=$(ip -4 addr show "$default_interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local current_cidr=$(ip -4 addr show "$default_interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    local current_gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    # Find existing Netplan configuration files
    local existing_netplan_files=()
    if ls /etc/netplan/*.yaml 1> /dev/null 2>&1; then
        while IFS= read -r file; do
            existing_netplan_files+=("$file")
        done < <(ls /etc/netplan/*.yaml 2>/dev/null)
    fi
    
    echo -e "${BOLD}Current configuration for $default_interface:${NC}"
    echo "  Interface: $default_interface"
    echo "  IP Address: ${current_cidr:-Not set}"
    echo "  Gateway: ${current_gateway:-Not detected}"
    echo ""
    
    if [ ${#existing_netplan_files[@]} -gt 0 ]; then
        echo -e "${BOLD}Existing Netplan configuration files:${NC}"
        for file in "${existing_netplan_files[@]}"; do
            echo "  • $(basename "$file")"
        done
        echo ""
    fi
    
    # Get user input for static IP configuration
    echo -e "${BOLD}Configure static IP for Pi-hole:${NC}"
    echo ""
    echo "Recommended settings for Pi-hole server:"
    echo "  IP: 192.168.1.50/24"
    echo "  Gateway: 192.168.1.1"
    echo "  DNS: 192.168.1.50 (Pi-hole will use itself)"
    echo ""
    
    local interface=$(ask_input "Network interface" "$default_interface")
    local static_ip=$(ask_input "Static IP address with CIDR" "192.168.1.50/24")
    local gateway=$(ask_input "Gateway IP" "${current_gateway:-192.168.1.1}")
    local dns_ip=$(ask_input "DNS server (Pi-hole IP)" "192.168.1.50")
    
    echo ""
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "  Interface: $interface"
    echo "  Static IP: $static_ip"
    echo "  Gateway: $gateway"
    echo "  DNS Server: $dns_ip (Pi-hole itself)"
    echo ""
    
    if ! ask_yes_no "Apply this configuration?" "y"; then
        print_warning "Static IP configuration cancelled"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Determine which Netplan file to modify
    local target_netplan_file=""
    
    if [ ${#existing_netplan_files[@]} -eq 0 ]; then
        # No existing files, create new one with original-style name
        target_netplan_file="/etc/netplan/00-installer-config.yaml"
        print_status "No existing Netplan configuration found"
        print_status "Creating new configuration: $(basename "$target_netplan_file")"
    elif [ ${#existing_netplan_files[@]} -eq 1 ]; then
        # One existing file, use it
        target_netplan_file="${existing_netplan_files[0]}"
        print_status "Using existing configuration file: $(basename "$target_netplan_file")"
    else
        # Multiple files exist, let user choose or use the first one
        echo -e "${BOLD}Multiple Netplan configuration files found:${NC}"
        for i in "${!existing_netplan_files[@]}"; do
            echo "  $((i+1))) $(basename "${existing_netplan_files[$i]}")"
        done
        echo ""
        
        local file_choice=$(ask_input "Which file to modify? (1-${#existing_netplan_files[@]})" "1")
        if [ "$file_choice" -ge 1 ] && [ "$file_choice" -le "${#existing_netplan_files[@]}" ]; then
            target_netplan_file="${existing_netplan_files[$((file_choice-1))]}"
        else
            target_netplan_file="${existing_netplan_files[0]}"
        fi
        print_status "Using: $(basename "$target_netplan_file")"
    fi
    
    # Create backup of the target file with timestamp
    local backup_file="${target_netplan_file}.backup.$(date +%Y%m%d_%H%M%S)"
    print_status "Creating backup..."
    sudo cp "$target_netplan_file" "$backup_file" 2>/dev/null
    print_success "Backup created: $(basename "$backup_file")"
    
    # Verify variables before writing
    echo ""
    print_status "Debug - Variables to be written:"
    echo "  interface: $interface"
    echo "  static_ip: $static_ip"
    echo "  gateway: $gateway"
    echo "  dns_ip: $dns_ip"
    echo ""
    
    # Create the new Netplan configuration
    print_status "Updating Netplan configuration..."
    
    # Use a temporary file to avoid issues with sudo and variable expansion
    local temp_file=$(mktemp)
    
    cat > "$temp_file" << EOF
# Pi-hole Static IP Configuration
# Original file backed up to: $(basename "$backup_file")
# Modified: $(date)
network:
  version: 2
  ethernets:
    $interface:
      dhcp4: false
      dhcp6: false
      addresses:
        - $static_ip
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses:
          - $dns_ip
EOF
    
    # Copy the temp file to the target location with sudo
    sudo cp "$temp_file" "$target_netplan_file"
    rm "$temp_file"
    
    if [ -f "$target_netplan_file" ]; then
        print_success "Configuration updated: $(basename "$target_netplan_file")"
        
        # Set proper permissions
        sudo chmod 600 "$target_netplan_file"
        
        # Show the configuration
        echo ""
        echo -e "${CYAN}Updated Netplan configuration:${NC}"
        echo "----------------------------------------"
        cat "$target_netplan_file"
        echo "----------------------------------------"
        echo ""
        
        # Apply the configuration
        echo -e "${YELLOW}${BOLD}WARNING: Applying this will change your network configuration!${NC}"
        echo "If you're connected via SSH, you might lose connection."
        echo "Make sure you can access the server at the new IP: $dns_ip"
        echo ""
        
        if ask_yes_no "Apply Netplan configuration now?" "y"; then
            print_status "Applying network configuration..."
            
            if sudo netplan apply 2>&1; then
                print_success "Network configuration applied successfully!"
                echo ""
                
                # Update Pi-hole IP in script
                PIHOLE_IP="$dns_ip"
                
                # Verify the new configuration
                print_status "Verifying new network configuration..."
                echo ""
                
                echo -e "${BOLD}Interface Configuration:${NC}"
                ip -br addr show "$interface" 2>/dev/null || true
                echo ""
                
                echo -e "${BOLD}DNS Configuration:${NC}"
                resolvectl status 2>/dev/null | grep -A 5 "DNS Servers" || true
                echo ""
                
                echo -e "${BOLD}Default Route:${NC}"
                ip route | grep default || true
                echo ""
                
                print_success "Static IP configuration complete!"
                echo ""
                echo -e "${BOLD}Next steps:${NC}"
                echo "1. Update Pi-hole compose.yaml with new IP if needed:"
                echo "   FTLCONF_LOCAL_IPV4: $dns_ip"
                echo ""
                echo "2. Restart Pi-hole to apply changes:"
                echo "   cd $PIHOLE_DIR && docker compose up -d"
                echo ""
                echo "3. Configure your router to use this Pi-hole as DNS:"
                echo "   Primary DNS: $dns_ip"
                
            else
                print_error "Failed to apply Netplan configuration"
                echo ""
                echo "Troubleshooting:"
                echo "  1. Check configuration syntax:"
                echo "     sudo netplan try"
                echo ""
                echo "  2. Restore from backup:"
                echo "     sudo cp $backup_file $target_netplan_file"
                echo "     sudo netplan apply"
                echo ""
                echo "  3. Check system logs:"
                echo "     journalctl -xe | grep netplan"
            fi
        else
            print_status "Configuration created but not applied"
            echo ""
            echo "To apply manually:"
            echo "  sudo netplan apply"
            echo ""
            echo "To test configuration first:"
            echo "  sudo netplan try"
            echo ""
            echo "To restore original configuration:"
            echo "  sudo cp $backup_file $target_netplan_file"
        fi
    else
        print_error "Failed to update Netplan configuration file"
        echo "Check if you have write permissions to /etc/netplan/"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Phase 7: Router Configuration Guide (Option 1)
configure_router() {
    clear
    print_header "Phase 7: Router DNS Configuration (Option 1 - Recommended)"
    
    get_pihole_config
    
    echo "This option will make ALL devices on your network use Pi-hole automatically."
    echo ""
    
    local pi_hole_ip=$(ask_input "Your Pi-hole server IP address" "${PIHOLE_IP}")
    
    clear
    print_header "Router Configuration Guide"
    
    echo -e "${BOLD}Step 1: Access your router's admin panel${NC}"
    echo "  • Usually at: http://192.168.0.1 or http://192.168.1.1"
    echo "  • Common credentials: admin/admin, admin/password"
    echo "  • Check your router's manual if unsure"
    echo ""
    
    echo -e "${BOLD}Step 2: Find DNS settings${NC}"
    echo "  Look for one of these:"
    echo "  • DNS Server Settings"
    echo "  • WAN DNS Settings"
    echo "  • Internet Connection Settings"
    echo "  • DHCP Server Settings"
    echo ""
    
    echo -e "${BOLD}Step 3: Replace ISP DNS servers${NC}"
    echo -e "  Primary DNS:   ${GREEN}${pi_hole_ip}${NC}"
    echo -e "  Secondary DNS: ${GREEN}${pi_hole_ip}${NC} (or leave blank)"
    echo ""
    
    echo -e "${BOLD}Step 4: Apply and test${NC}"
    echo "  • Save/Apply settings"
    echo "  • Router may need to reboot"
    echo "  • Devices may need to reconnect to Wi-Fi"
    echo ""
    
    echo -e "${CYAN}${BOLD}Popular Router Instructions:${NC}"
    echo ""
    echo "ASUS:  WAN → Internet Connection → WAN DNS Setting → No"
    echo "TP-Link: Network → WAN → Advanced → Use These DNS Servers"
    echo "Netgear: Internet → Domain Name Server → Use These DNS Servers"
    echo "Linksys: Connectivity → Internet Settings → Edit → Manual DNS"
    echo "Fritz!Box: Internet → Account Information → DNS Servers"
    echo ""
    
    echo -e "${YELLOW}Note: Some ISPs lock DNS settings. If so, use Option 2 instead.${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
}

# Phase 7: Individual Device Configuration (Option 2)
configure_individual_devices() {
    clear
    print_header "Phase 7: Individual Device Configuration (Option 2)"
    
    get_pihole_config
    local pi_hole_ip="${PIHOLE_IP}"
    
    echo -e "Configure devices to use Pi-hole DNS: ${GREEN}${pi_hole_ip}${NC}"
    echo ""
    
    echo -e "${CYAN}Windows 10/11:${NC}"
    echo "  Settings → Network & Internet → Advanced → More adapter options"
    echo "  Right-click adapter → Properties → IPv4 → Use the following DNS server"
    echo "  Preferred DNS: ${pi_hole_ip}"
    echo ""
    
    echo -e "${CYAN}Linux (Ubuntu/Debian):${NC}"
    echo "  Settings → Network → Gear icon → IPv4 → Manual"
    echo "  DNS: ${pi_hole_ip}"
    echo "  Or terminal: sudo nmcli con mod \"YourConnection\" ipv4.dns \"${pi_hole_ip}\""
    echo ""
    
    echo -e "${CYAN}macOS:${NC}"
    echo "  System Preferences → Network → Advanced → DNS"
    echo "  Add: ${pi_hole_ip}"
    echo ""
    
    echo -e "${CYAN}Android:${NC}"
    echo "  Settings → Wi-Fi → Long press network → Modify network"
    echo "  Advanced → IP settings → Static"
    echo "  DNS 1: ${pi_hole_ip}"
    echo ""
    
    echo -e "${CYAN}iPhone/iPad:${NC}"
    echo "  Settings → Wi-Fi → (i) icon → Configure DNS → Manual"
    echo "  Add server: ${pi_hole_ip}"
    echo ""
    
    read -p "Press Enter to continue..."
}

# Phase 8: Update Blocklists
update_blocklists() {
    clear
    print_header "Phase 8: Blocklist Management"
    
    get_pihole_config
    
    echo "Pi-hole comes with a default blocklist, but you can add more."
    echo ""
    
    echo -e "${BOLD}Popular Blocklist Sources:${NC}"
    echo ""
    echo "1) Firebog (https://firebog.net)"
    echo "   • Green: Safe lists, low false positives"
    echo "   • Blue: More aggressive"
    echo "   • Red: Very aggressive"
    echo ""
    echo "2) OISD (https://oisd.nl)"
    echo "   • Single comprehensive list: https://big.oisd.nl"
    echo ""
    echo "3) StevenBlack (https://github.com/StevenBlack/hosts)"
    echo "   • Unified hosts file with multiple variants"
    echo ""
    
    echo -e "${BOLD}How to add blocklists:${NC}"
    echo ""
    echo "Via Web Interface:"
    echo "  1. Go to: http://${PIHOLE_IP}/admin"
    echo "  2. Login → Group Management → Adlists"
    echo "  3. Paste the list URL and add a comment"
    echo "  4. Update Gravity when done"
    echo ""
    echo "Via Command Line:"
    echo "  docker exec pihole pihole -a adlist add <URL> \"<Comment>\""
    echo ""
    
    if check_pihole_status; then
        if ask_yes_no "Would you like to add a blocklist now?" "n"; then
            echo ""
            while true; do
                local list_url=$(ask_input "Blocklist URL (empty to finish)" "")
                [ -z "$list_url" ] && break
                local list_comment=$(ask_input "Comment/Description" "Custom list")
                
                print_status "Adding list: $list_comment"
                if docker exec pihole pihole -a adlist add "$list_url" "$list_comment" 2>/dev/null; then
                    print_success "List added successfully"
                else
                    print_error "Failed to add list"
                fi
            done
            
            if ask_yes_no "Update Gravity now?" "y"; then
                update_gravity
            fi
        fi
    else
        print_warning "Pi-hole is not running. Start it first to add blocklists."
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Phase 9: Update Gravity
update_gravity() {
    clear
    print_header "Phase 9: Update Gravity Database"
    
    if ! check_pihole_status; then
        print_error "Pi-hole container is not running"
        echo "Start it with: cd $PIHOLE_DIR && docker compose up -d"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_status "Updating Gravity (blocklist database)..."
    echo "This may take a few minutes depending on blocklist size."
    echo ""
    
    if docker exec pihole pihole -g; then
        print_success "Gravity update completed successfully!"
        echo ""
        docker exec pihole pihole -c 2>/dev/null || true
    else
        print_error "Gravity update failed"
        echo "Check logs: docker logs pihole"
    fi
    
    echo ""
    if ask_yes_no "Would you like to schedule automatic updates?" "n"; then
        local schedule=$(ask_input "Schedule (daily/weekly/monthly)" "weekly")
        case "$schedule" in
            daily)  CRON_TIME="0 3 * * *" ;;
            weekly) CRON_TIME="0 3 * * 0" ;;
            monthly) CRON_TIME="0 3 1 * *" ;;
            *) CRON_TIME="0 3 * * 0" ;;
        esac
        
        local CRON_CMD="$CRON_TIME cd $PIHOLE_DIR && docker exec pihole pihole -g >> /var/log/pihole-gravity.log 2>&1"
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        print_success "Gravity update scheduled ($schedule at 3 AM)"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Phase 10: Check Statistics
check_statistics() {
    clear
    print_header "Phase 10: Pi-hole Statistics"
    
    if ! check_pihole_status; then
        print_error "Pi-hole container is not running"
        read -p "Press Enter to continue..."
        return
    fi
    
    get_pihole_config
    
    echo -e "${BOLD}Quick Statistics:${NC}"
    echo ""
    docker exec pihole pihole -c 2>/dev/null || echo "Could not fetch statistics"
    
    echo ""
    echo -e "${BOLD}Web Dashboard:${NC}"
    echo -e "  URL: ${GREEN}http://${PIHOLE_IP}/admin${NC}"
    echo ""
    
    echo -e "${BOLD}Dashboard Shows:${NC}"
    echo "  • Total Queries & Queries Blocked"
    echo "  • Percentage Blocked"
    echo "  • Top Clients & Domains"
    echo "  • Query Types Distribution"
    
    echo ""
    if ask_yes_no "View live query log? (CTRL+C to stop)" "n"; then
        docker exec pihole pihole -t
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Phase 11: Automatic Updates
automatic_updates() {
    clear
    print_header "Phase 11: Update Pi-hole Container"
    
    if ! check_pihole_status; then
        print_error "Pi-hole container is not running"
        echo "Start it with: cd $PIHOLE_DIR && docker compose up -d"
        read -p "Press Enter to continue..."
        return
    fi
    
    cd "$PIHOLE_DIR" 2>/dev/null || {
        print_error "Cannot access $PIHOLE_DIR"
        read -p "Press Enter to continue..."
        return
    }
    
    print_status "Pulling latest Pi-hole image..."
    if docker compose pull; then
        print_success "Latest image pulled"
    else
        print_error "Failed to pull image"
        read -p "Press Enter to continue..."
        return
    fi
    
    if ask_yes_no "Recreate container with new image?" "y"; then
        print_status "Updating Pi-hole..."
        if docker compose up -d; then
            print_success "Pi-hole updated successfully!"
            echo ""
            echo "Your configuration is preserved in:"
            echo "  $PIHOLE_DIR/etc-pihole"
            echo "  $PIHOLE_DIR/etc-dnsmasq.d"
        else
            print_error "Update failed"
            echo "Check logs: docker compose logs"
        fi
    fi
    
    echo ""
    if ask_yes_no "Schedule automatic updates?" "n"; then
        local schedule=$(ask_input "Schedule (weekly/monthly)" "monthly")
        case "$schedule" in
            weekly) CRON_TIME="0 4 * * 0" ;;
            monthly) CRON_TIME="0 4 1 * *" ;;
            *) CRON_TIME="0 4 1 * *" ;;
        esac
        
        local CRON_CMD="$CRON_TIME cd $PIHOLE_DIR && docker compose pull && docker compose up -d >> /var/log/pihole-update.log 2>&1"
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        print_success "Updates scheduled ($schedule at 4 AM)"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Phase 12: Backup
backup_configuration() {
    clear
    print_header "Phase 12: Backup Pi-hole Configuration"
    
    echo "What gets backed up:"
    echo "  • Configuration files"
    echo "  • DNS records"
    echo "  • Blocklists & whitelist"
    echo "  • Custom rules"
    echo "  • DHCP settings"
    echo ""
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="pihole_backup_${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    echo "Backup options:"
    echo "1) Full compressed backup (.tar.gz)"
    echo "2) Quick copy backup"
    echo ""
    read -p "Choose option [1-2]: " backup_choice
    
    case $backup_choice in
        1)
            print_status "Creating compressed backup..."
            if tar -czf "${backup_path}.tar.gz" -C /srv/docker pihole/ 2>/dev/null; then
                local size=$(du -h "${backup_path}.tar.gz" | cut -f1)
                print_success "Backup created: ${backup_path}.tar.gz (${size})"
            else
                print_error "Backup failed"
            fi
            ;;
        2)
            print_status "Creating quick backup..."
            mkdir -p "$backup_path"
            if cp -r "$PIHOLE_DIR"/* "$backup_path/" 2>/dev/null; then
                print_success "Backup created: $backup_path"
            else
                print_error "Backup failed"
            fi
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
    
    echo ""
    if ask_yes_no "Schedule automatic daily backups?" "y"; then
        local CRON_CMD="0 2 * * * tar -czf $BACKUP_DIR/pihole_backup_\$(date +\%Y\%m\%d_\%H\%M\%S).tar.gz -C /srv/docker pihole/"
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        print_success "Daily backups scheduled at 2 AM"
    fi
    
    echo ""
    echo "Restore command:"
    echo "  tar -xzf backup.tar.gz -C /srv/docker/"
    
    echo ""
    read -p "Press Enter to continue..."
}

# Additional Tools
additional_tools() {
    while true; do
        clear
        print_header "Additional Tools"
        
        echo "1) Flush Pi-hole logs"
        echo "2) Restart Pi-hole"
        echo "3) View Pi-hole logs"
        echo "4) Update admin password"
        echo "5) Whitelist a domain"
        echo "6) Blacklist a domain"
        echo "7) Check DNS resolution"
        echo "8) Return to main menu"
        echo ""
        read -p "Select option [1-8]: " choice
        
        case $choice in
            1)
                if check_pihole_status; then
                    docker exec pihole pihole flush
                    print_success "Logs flushed"
                fi
                ;;
            2)
                if check_pihole_status; then
                    cd "$PIHOLE_DIR" && docker compose restart
                    print_success "Pi-hole restarted"
                fi
                ;;
            3)
                if check_pihole_status; then
                    docker logs --tail 50 pihole
                fi
                ;;
            4)
                local pass=$(ask_input "New password" "")
                [ -n "$pass" ] && docker exec pihole pihole -a -p "$pass" && print_success "Password updated"
                ;;
            5)
                local domain=$(ask_input "Domain to whitelist" "")
                [ -n "$domain" ] && docker exec pihole pihole -w "$domain" && print_success "Whitelisted $domain"
                ;;
            6)
                local domain=$(ask_input "Domain to blacklist" "")
                [ -n "$domain" ] && docker exec pihole pihole -b "$domain" && print_success "Blacklisted $domain"
                ;;
            7)
                if command -v resolvectl &> /dev/null; then
                    resolvectl status
                elif command -v systemd-resolve &> /dev/null; then
                    systemd-resolve --status
                else
                    cat /etc/resolv.conf
                fi
                ;;
            8)
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Main menu
main_menu() {
    # Check Docker first
    if ! check_docker; then
        echo "Docker is required but not found."
        exit 1
    fi
    
    # Get initial configuration
    get_pihole_config
    
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "╔══════════════════════════════════════╗"
        echo "║  Pi-hole Post-Installation Manager  ║"
        echo "╚══════════════════════════════════════╝"
        echo -e "${NC}"
        
        # Show status
        if check_pihole_status; then
            echo -e "Status: ${GREEN}Running${NC} | Web: ${GREEN}http://${PIHOLE_IP}/admin${NC}"
        else
            echo -e "Status: ${RED}Not Running${NC}"
        fi
        echo ""
        
        echo -e "${BOLD}Server Setup:${NC}"
        echo "  0) Configure static IP (Netplan)"
        echo ""
        echo -e "${BOLD}Phase 7 - Network Setup:${NC}"
        echo "  1) Configure router DNS (Recommended)"
        echo "  2) Configure individual devices"
        echo ""
        echo -e "${BOLD}Phase 8-9 - Blocklists:${NC}"
        echo "  3) Manage blocklists"
        echo "  4) Update Gravity"
        echo ""
        echo -e "${BOLD}Phase 10-12 - Maintenance:${NC}"
        echo "  5) View statistics"
        echo "  6) Update Pi-hole"
        echo "  7) Backup configuration"
        echo ""
        echo "  8) Additional tools"
        echo "  9) Exit"
        echo ""
        read -p "Select option [0-9]: " choice
        
        case $choice in
            0) configure_static_ip ;;
            1) configure_router ;;
            2) configure_individual_devices ;;
            3) update_blocklists ;;
            4) update_gravity ;;
            5) check_statistics ;;
            6) automatic_updates ;;
            7) backup_configuration ;;
            8) additional_tools ;;
            9) 
                echo ""
                echo "Goodbye!"
                exit 0 
                ;;
            *) 
                print_error "Invalid option" 
                sleep 1
                ;;
        esac
    done
}

# Start the script
main_menu