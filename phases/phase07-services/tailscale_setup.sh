#!/bin/bash

# Tailscale Setup Script for Ubuntu Server
# This script automates the installation and configuration of Tailscale
# Run as a user with sudo privileges

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
ENABLE_MAGICDNS=true
ENABLE_SSH=true
ENABLE_HTTPS=false
ADVERTISE_ROUTES=false
SUBNET_CIDR="192.168.1.0/24"
USE_PIHOLE_DNS=false
PIHOLE_IP=""

# Function to print colored output
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

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# Function to prompt yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    
    if [ "$default" = "Y" ]; then
        local options="[Y/n]"
    else
        local options="[y/N]"
    fi
    
    read -p "$prompt $options: " response
    response=${response:-$default}
    
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if running as root or with sudo
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script requires sudo privileges"
        echo "Please run with: sudo $0"
        exit 1
    fi
}

# Function to wait for Tailscale to come online
wait_for_tailscale() {
    local max_attempts=30
    local attempt=1
    
    print_info "Waiting for Tailscale authentication to complete..."
    print_info "This may take a few moments. Please authenticate in your browser."
    echo ""
    
    while [ $attempt -le $max_attempts ]; do
        if tailscale status >/dev/null 2>&1; then
            # Check if we have an IP address
            if tailscale ip -4 >/dev/null 2>&1; then
                return 0
            fi
        fi
        
        # Show progress
        echo -ne "Waiting... (attempt $attempt/$max_attempts)\r"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo ""  # New line after progress
    return 1
}

# Phase 1: Account Creation Reminder
remind_account_creation() {
    print_status "Phase 1: Tailscale Account"
    echo ""
    print_warning "Before proceeding, ensure you have:"
    echo "  1. Created a Tailscale account at https://tailscale.com"
    echo "  2. Signed in using Google, Microsoft, GitHub, Apple, or Passkey"
    echo "  3. Have access to your account for device approval"
    echo ""
    
    if ! prompt_yes_no "Have you created your Tailscale account?" "N"; then
        echo ""
        echo "Please create your account at https://tailscale.com and run this script again."
        exit 1
    fi
    print_success "Account creation confirmed"
}

# Phase 2: Install Tailscale on Ubuntu
install_tailscale() {
    print_status "Phase 2: Installing Tailscale on Ubuntu"
    
    # Check if Tailscale is already installed
    if command -v tailscale >/dev/null 2>&1; then
        print_warning "Tailscale is already installed"
        tailscale version
        if ! prompt_yes_no "Do you want to reinstall/update?" "N"; then
            return 0
        fi
    fi
    
    # Update package list
    print_status "Updating package list..."
    apt update
    
    # Install Tailscale
    print_status "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    
    # Verify installation
    if command -v tailscale >/dev/null 2>&1; then
        print_success "Tailscale installed successfully"
        tailscale version
    else
        print_error "Tailscale installation failed"
        exit 1
    fi
}

# Phase 3: Connect the server
connect_server() {
    print_status "Phase 3: Connecting server to Tailscale"
    
    # Check if already connected
    if tailscale status >/dev/null 2>&1 && tailscale ip -4 >/dev/null 2>&1; then
        print_warning "Tailscale is already connected"
        tailscale status
        if ! prompt_yes_no "Do you want to reconnect?" "N"; then
            return 0
        fi
    fi
    
    # Build the tailscale up command with options
    local up_cmd="tailscale up"
    
    # Add options based on configuration
    if [ "$ENABLE_SSH" = true ]; then
        up_cmd="$up_cmd --ssh"
    fi
    
    if [ "$ADVERTISE_ROUTES" = true ]; then
        # Enable IP forwarding first
        print_status "Enabling IP forwarding for subnet routing..."
        echo 'net.ipv4.ip_forward = 1' | tee /etc/sysctl.d/99-tailscale.conf
        echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
        sysctl --system
        print_success "IP forwarding enabled"
        
        up_cmd="$up_cmd --advertise-routes=$SUBNET_CIDR"
    fi
    
    echo ""
    print_info "Running: $up_cmd"
    echo ""
    print_warning "A browser authentication URL will appear. Please complete these steps:"
    echo "  1. Open the URL in your browser"
    echo "  2. Log into your Tailscale account if prompted"
    echo "  3. Approve the device when prompted"
    echo "  4. Return here and press Enter once authenticated"
    echo ""
    
    # Start tailscale up in the background
    print_status "Starting Tailscale authentication..."
    $up_cmd &
    local tailscale_pid=$!
    
    # Wait for user to complete authentication
    print_info "Please authenticate in your browser now..."
    print_info "After authentication is complete, press Enter to continue..."
    read -p ""
    
    # Kill the background process if it's still running
    if kill -0 $tailscale_pid 2>/dev/null; then
        print_info "Stopping authentication process..."
        kill $tailscale_pid 2>/dev/null || true
    fi
    
    # Wait for Tailscale to be fully connected
    sleep 2
    
    if wait_for_tailscale; then
        print_success "Server successfully connected to Tailscale!"
    else
        print_warning "Timed out waiting for connection. Let's check the status manually..."
        echo ""
        
        # Try running it again directly if needed
        if ! tailscale status >/dev/null 2>&1; then
            print_info "Retrying connection..."
            tailscale up --ssh &
            sleep 5
            kill %1 2>/dev/null || true
            
            if ! wait_for_tailscale; then
                print_error "Failed to connect to Tailscale. Please run manually:"
                echo "  sudo $up_cmd"
                exit 1
            fi
        fi
    fi
    
    # Show status
    echo ""
    print_status "Connection Status:"
    tailscale status
    
    # Show IP
    echo ""
    print_status "Your Tailscale IP:"
    tailscale ip -4
    
    if [ "$ADVERTISE_ROUTES" = true ]; then
        echo ""
        print_warning "IMPORTANT: Don't forget to approve the advertised routes!"
        echo "  1. Go to https://login.tailscale.com/admin/machines"
        echo "  2. Find your server"
        echo "  3. Click '...' > 'Edit route settings'"
        echo "  4. Approve the $SUBNET_CIDR route"
    fi
}

# Phase 11: Configure Pi-hole DNS FIRST (before MagicDNS!)
configure_pihole_dns() {
    if [ "$USE_PIHOLE_DNS" != true ]; then
        return 0
    fi
    
    print_status "Phase 11: Configuring Pi-hole as Tailscale DNS (BEFORE MagicDNS)"
    
    print_warning "This requires Pi-hole to be installed and accessible"
    echo ""
    
    # Try to detect Pi-hole IP
    if command -v pihole >/dev/null 2>&1; then
        PIHOLE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        print_info "Pi-hole detected on this server (Tailscale IP: $PIHOLE_IP)"
    else
        read -p "Enter your Pi-hole's Tailscale IP (100.x.x.x): " PIHOLE_IP
    fi
    
    echo ""
    print_status "IMPORTANT: Configure Pi-hole DNS BEFORE enabling MagicDNS!"
    echo "  1. Go to https://login.tailscale.com/admin/dns"
    echo "  2. Under 'Nameservers', add your Pi-hole: $PIHOLE_IP"
    echo "  3. Enable 'Override local DNS'"
    echo ""
    print_warning "DO NOT enable MagicDNS yet! We'll do that in the next step."
    echo ""
    
    if prompt_yes_no "Have you added Pi-hole as a nameserver in the admin console?" "N"; then
        print_success "Pi-hole DNS configuration completed"
        
        # Also configure Pi-hole locally if installed on this server
        if command -v pihole >/dev/null 2>&1; then
            print_status "Configuring local Pi-hole to listen on Tailscale interface..."
            
            # Create/update Pi-hole custom config for Tailscale
            cat > /etc/dnsmasq.d/02-tailscale.conf <<EOF
# Listen on Tailscale interface
interface=tailscale0
# Bind to Tailscale IP
listen-address=$PIHOLE_IP
# Allow Tailscale network
except-interface=lo
EOF
            
            # Restart Pi-hole's DNS service
            systemctl restart pihole-FTL
            print_success "Pi-hole configured to listen on Tailscale interface"
        fi
    else
        print_warning "Please configure Pi-hole DNS before enabling MagicDNS"
        echo "You can do this later from the admin console"
    fi
}

# Phase 7: Configure MagicDNS (AFTER Pi-hole DNS!)
configure_magicdns() {
    if [ "$ENABLE_MAGICDNS" != true ]; then
        return 0
    fi
    
    print_status "Phase 7: MagicDNS Configuration (AFTER Pi-hole DNS)"
    echo ""
    
    if [ "$USE_PIHOLE_DNS" = true ]; then
        print_info "Since you're using Pi-hole DNS, MagicDNS will work alongside it."
        echo ""
        print_status "Now you can enable MagicDNS in the admin console:"
        echo "  1. Go to https://login.tailscale.com/admin/dns"
        echo "  2. Enable 'MagicDNS'"
        echo ""
        print_warning "IMPORTANT: Make sure Pi-hole nameserver is already configured!"
        echo "  Your Pi-hole ($PIHOLE_IP) should already be listed under 'Nameservers'"
        echo "  before you enable MagicDNS."
        echo ""
    else
        print_status "Enable MagicDNS in the Tailscale admin console:"
        echo "  1. Go to https://login.tailscale.com/admin/dns"
        echo "  2. Enable 'MagicDNS'"
        echo "  3. This allows you to access devices by hostname (e.g., homeserver)"
        echo ""
    fi
    
    if prompt_yes_no "Have you enabled MagicDNS in the admin console?" "N"; then
        print_success "MagicDNS enabled"
        
        if [ "$USE_PIHOLE_DNS" = true ]; then
            print_success "MagicDNS and Pi-hole DNS are now working together!"
            echo ""
            print_info "You can test it:"
            echo "  - DNS resolution with ad blocking: nslookup doubleclick.net"
            echo "  - MagicDNS hostname resolution: ping homeserver"
        fi
    else
        echo "You can enable MagicDNS later from the admin console"
    fi
}

# Phase 9: Configure Tailscale SSH
configure_ssh() {
    print_status "Phase 9: Tailscale SSH Configuration"
    
    if tailscale status | grep -q "offers SSH"; then
        print_success "Tailscale SSH is already enabled"
    elif [ "$ENABLE_SSH" = true ]; then
        print_status "Enabling Tailscale SSH..."
        tailscale up --ssh
        print_success "Tailscale SSH enabled"
        print_info "Now only authenticated Tailscale devices can SSH to this server"
        echo "You no longer need to forward port 22 on your router"
    else
        print_info "Tailscale SSH not enabled (set ENABLE_SSH=true to enable)"
    fi
}

# Phase 12: Configure Firewall
configure_firewall() {
    print_status "Phase 12: Firewall Configuration"
    
    # Check if UFW is installed and active
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "active"; then
            print_status "UFW is active. Configuring Tailscale rules..."
            
            # Allow Tailscale interface
            ufw allow in on tailscale0 2>/dev/null || true
            ufw allow out on tailscale0 2>/dev/null || true
            
            print_success "UFW rules added for Tailscale interface"
            
            echo ""
            print_status "Current UFW status:"
            ufw status | grep -A 10 "tailscale" || true
        else
            print_info "UFW is installed but not active"
            if prompt_yes_no "Do you want to activate UFW now?" "N"; then
                print_warning "Make sure you've allowed SSH access before enabling!"
                if prompt_yes_no "Have you allowed SSH access in UFW?" "N"; then
                    ufw enable
                    ufw allow in on tailscale0 2>/dev/null || true
                    ufw allow out on tailscale0 2>/dev/null || true
                    print_success "UFW enabled with Tailscale rules"
                fi
            fi
        fi
    else
        print_info "UFW not installed (consider installing for additional security)"
    fi
}

# Phase 13: Verify everything
verify_installation() {
    print_status "Phase 13: Verifying Tailscale Installation"
    echo ""
    
    # Run verification commands
    echo "=== Tailscale Status ==="
    tailscale status
    echo ""
    
    echo "=== Tailscale IP ==="
    tailscale ip -4 || echo "Not available"
    echo ""
    
    echo "=== Tailscale Network Check ==="
    tailscale netcheck
    echo ""
    
    # Try to ping if hostname is available
    local hostname=$(hostname)
    echo "=== Ping Test ==="
    if tailscale ping -c 3 "$hostname" 2>/dev/null; then
        print_success "Ping test successful"
    else
        print_info "Ping test failed (this is normal if MagicDNS isn't enabled yet)"
    fi
    
    # Test Pi-hole DNS if configured
    if [ "$USE_PIHOLE_DNS" = true ] && [ ! -z "$PIHOLE_IP" ]; then
        echo ""
        echo "=== Pi-hole DNS Test ==="
        if nslookup google.com $PIHOLE_IP >/dev/null 2>&1; then
            print_success "Pi-hole DNS is responding"
        else
            print_warning "Pi-hole DNS not responding - check configuration"
        fi
    fi
    
    echo ""
    print_success "Verification complete!"
}

# Print final instructions
print_final_instructions() {
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "100.x.x.x")
    local hostname=$(hostname)
    
    echo ""
    echo "========================================="
    echo "  Tailscale Setup Complete!"
    echo "========================================="
    echo ""
    echo "Your server details:"
    echo "  Hostname: $hostname"
    echo "  Tailscale IP: $ts_ip"
    echo ""
    echo "Access your services:"
    echo "  SSH:               ssh user@$ts_ip"
    echo "  Home Assistant:    http://$ts_ip:8123"
    echo "  Pi-hole:           http://$ts_ip/admin"
    echo "  Portainer:         http://$ts_ip:9000"
    echo "  Plex:              http://$ts_ip:32400/web"
    echo ""
    
    if [ "$ENABLE_MAGICDNS" = true ]; then
        echo "With MagicDNS (once enabled):"
        echo "  SSH:               ssh user@$hostname"
        echo "  Home Assistant:    http://$hostname:8123"
        echo "  Pi-hole:           http://$hostname/admin"
        echo "  Portainer:         http://$hostname:9000"
        echo "  Plex:              http://$hostname:32400/web"
        echo ""
    fi
    
    if [ "$USE_PIHOLE_DNS" = true ] && [ ! -z "$PIHOLE_IP" ]; then
        echo "Pi-hole DNS Configuration:"
        echo "  Pi-hole IP (Tailscale): $PIHOLE_IP"
        echo "  Ad blocking is active over Tailscale"
        echo "  Combined with MagicDNS for seamless access"
        echo ""
    fi
    
    if [ "$ADVERTISE_ROUTES" = true ]; then
        echo "Subnet routing enabled for: $SUBNET_CIDR"
        echo "You can now access devices on your home network through this server"
        echo "Remember to approve the routes in the admin console!"
        echo ""
    fi
    
    echo "Next steps:"
    echo "  1. Install Tailscale on your other devices"
    echo "  2. Test connectivity from outside your network"
    echo "  3. Verify Pi-hole ad blocking is working"
    echo ""
    echo "Admin console: https://login.tailscale.com/admin/machines"
    echo ""
}

# Main function
main() {
    clear
    echo "========================================="
    echo "  Tailscale Setup Script for Ubuntu"
    echo "========================================="
    echo ""
    
    # Configuration prompts
    print_status "Configuration Options:"
    echo ""
    
    if prompt_yes_no "Configure Pi-hole as DNS over Tailscale? (IMPORTANT: Do this before enabling MagicDNS)" "N"; then
        USE_PIHOLE_DNS=true
    fi
    
    if prompt_yes_no "Enable MagicDNS? (Recommended: Makes devices reachable by name. If using Pi-hole, configure Pi-hole DNS first!)" "Y"; then
        ENABLE_MAGICDNS=true
    else
        ENABLE_MAGICDNS=false
    fi
    
    if prompt_yes_no "Enable Tailscale SSH? (Recommended: Lets you SSH securely over Tailscale without exposing port 22.)" "Y"; then
        ENABLE_SSH=true
    else
        ENABLE_SSH=false
    fi
    
    if prompt_yes_no "Advertise LAN routes for subnet routing? (Only needed if you want access to other devices on your home LAN)" "N"; then
        ADVERTISE_ROUTES=true
        read -p "Enter your LAN subnet CIDR [192.168.1.0/24]: " input
        SUBNET_CIDR=${input:-"192.168.1.0/24"}
    fi
    
    echo ""
    print_status "Starting Tailscale setup..."
    echo ""
    
    # Execute phases in CORRECT ORDER:
    # 1. Install and connect first
    # 2. Configure Pi-hole DNS (BEFORE MagicDNS!)
    # 3. Then enable MagicDNS
    # 4. Configure other features
    
    check_privileges
    remind_account_creation
    install_tailscale
    connect_server
    configure_ssh
    configure_firewall
    
    # IMPORTANT: Configure Pi-hole DNS BEFORE MagicDNS!
    configure_pihole_dns
    
    # Now enable MagicDNS (after Pi-hole DNS is configured)
    configure_magicdns
    
    verify_installation
    print_final_instructions
    
    print_success "Setup completed successfully!"
    
    if [ "$USE_PIHOLE_DNS" = true ] && [ "$ENABLE_MAGICDNS" = true ]; then
        echo ""
        print_success "Pi-hole DNS + MagicDNS are now configured together!"
        print_info "Your devices will use Pi-hole for ad blocking while enjoying MagicDNS hostnames."
    fi
}

# Run main function
main "$@"