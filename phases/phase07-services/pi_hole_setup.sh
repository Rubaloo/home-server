#!/bin/bash

# Pi-hole Docker Installation Script
# Interactive setup wizard for Pi-hole on Docker

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default values
PIHOLE_DIR="/srv/docker/pihole"
DEFAULT_PASSWORD="admin"
TIMEZONE="Europe/Madrid"
DETECTED_IP=""

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
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect system IP
detect_ip() {
    DETECTED_IP=$(ip route get 1 2>/dev/null | awk '{print $7;exit}' || \
                  hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$DETECTED_IP" ]; then
        DETECTED_IP="192.168.1.10"
        print_warning "Could not detect IP address, using default: $DETECTED_IP"
    else
        print_success "Detected IP address: $DETECTED_IP"
    fi
}

# Function to check if systemd-resolved is active
check_systemd_resolved() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        return 0  # Active
    else
        return 1  # Not active
    fi
}

# Function to disable systemd-resolved DNS stub listener
disable_dns_stub_listener() {
    print_header "Disabling systemd-resolved DNS Stub Listener"
    
    print_status "This will disable only the DNS stub listener while keeping"
    print_status "systemd-resolved running for other DNS management functions."
    echo ""
    
    if ! check_systemd_resolved; then
        print_warning "systemd-resolved is not active - no changes needed"
        return
    fi
    
    # Backup original configuration
    if [ -f /etc/systemd/resolved.conf ]; then
        sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup.$(date +%Y%m%d_%H%M%S)
        print_success "Backup created: /etc/systemd/resolved.conf.backup.*"
    fi
    
    # Check if DNSStubListener is already set to no
    if grep -q "^DNSStubListener=no" /etc/systemd/resolved.conf 2>/dev/null; then
        print_status "DNS stub listener already disabled in configuration"
    else
        # Remove existing DNSStubListener line if present
        sudo sed -i '/^DNSStubListener=/d' /etc/systemd/resolved.conf
        
        # Add DNSStubListener=no under [Resolve] section
        if grep -q "^\[Resolve\]" /etc/systemd/resolved.conf; then
            # Add after [Resolve] section header
            sudo sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
        else
            # Add [Resolve] section with DNSStubListener=no
            echo "" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
            echo "[Resolve]" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
            echo "DNSStubListener=no" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
        fi
        print_success "DNSStubListener set to 'no' in /etc/systemd/resolved.conf"
    fi
    
    # Restart systemd-resolved to apply changes
    print_status "Restarting systemd-resolved..."
    sudo systemctl restart systemd-resolved
    print_success "systemd-resolved restarted"
    
    # Update /etc/resolv.conf symlink if needed
    print_status "Updating /etc/resolv.conf..."
    if [ -L /etc/resolv.conf ]; then
        CURRENT_LINK=$(readlink /etc/resolv.conf)
        if [ "$CURRENT_LINK" = "/run/systemd/resolve/stub-resolv.conf" ]; then
            print_warning "resolv.conf points to stub resolver, updating..."
            sudo rm /etc/resolv.conf
            sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
            print_success "resolv.conf now points to /run/systemd/resolve/resolv.conf"
        elif [ "$CURRENT_LINK" = "/run/systemd/resolve/resolv.conf" ]; then
            print_success "resolv.conf already properly configured"
        else
            print_warning "resolv.conf has unexpected symlink: $CURRENT_LINK"
            if ask_yes_no "Update resolv.conf to use systemd-resolved's resolver?" "y"; then
                sudo rm /etc/resolv.conf
                sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
                print_success "resolv.conf updated"
            fi
        fi
    else
        print_warning "resolv.conf is not a symlink"
        if ask_yes_no "Replace resolv.conf with symlink to systemd-resolved?" "y"; then
            sudo mv /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
            sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
            print_success "resolv.conf updated with backup created"
        fi
    fi
    
    # Verify port 53 is now free
    echo ""
    print_status "Verifying port 53 availability..."
    if sudo ss -tulpn | grep -q ":53 "; then
        print_warning "Port 53 is still in use:"
        sudo ss -tulpn | grep ":53 "
        print_error "Unable to free port 53 automatically"
        return 1
    else
        print_success "Port 53 is now free for Pi-hole"
        return 0
    fi
}

# Function to handle port 53 conflicts
handle_port_53_conflict() {
    print_warning "Port 53 is currently in use:"
    sudo ss -tulpn | grep ":53 "
    echo ""
    
    # Check if systemd-resolved is the culprit
    if sudo ss -tulpn | grep ":53 " | grep -q "systemd-resolve"; then
        print_status "Port 53 is being used by systemd-resolved"
        
        echo ""
        echo "Options to resolve this:"
        echo "  1) Disable systemd-resolved DNS stub listener (recommended)"
        echo "     This keeps systemd-resolved active but frees port 53"
        echo "  2) Stop and disable systemd-resolved entirely"
        echo "  3) Skip and exit (resolve manually)"
        echo ""
        
        read -p "Choose an option [1-3]: " port_choice
        
        case $port_choice in
            1)
                if disable_dns_stub_listener; then
                    return 0
                else
                    print_error "Failed to free port 53"
                    return 1
                fi
                ;;
            2)
                print_warning "Disabling systemd-resolved entirely..."
                sudo systemctl disable --now systemd-resolved
                sudo rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
                print_success "systemd-resolved disabled"
                return 0
                ;;
            3)
                print_warning "Please resolve port 53 conflict manually before continuing"
                return 1
                ;;
            *)
                print_error "Invalid option"
                return 1
                ;;
        esac
    else
        print_status "Another service is using port 53"
        if ask_yes_no "Do you want to attempt to stop the conflicting service?" "n"; then
            # Try to identify and stop the service
            SERVICE_NAME=$(sudo ss -tulpn | grep ":53 " | grep -oP '(?<=users:\(\(")[^"]+' | head -1)
            if [ -n "$SERVICE_NAME" ]; then
                print_status "Attempting to stop $SERVICE_NAME..."
                sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || sudo killall "$SERVICE_NAME" 2>/dev/null || true
                if ! sudo ss -tulpn | grep -q ":53 "; then
                    print_success "Port 53 is now free"
                    return 0
                fi
            fi
        fi
        print_error "Unable to free port 53 automatically"
        return 1
    fi
}

# Phase 1: Check requirements
check_requirements() {
    print_header "Phase 1: Checking Requirements"
    
    # Check Docker
    print_status "Checking Docker installation..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//')
        print_success "Docker version: $DOCKER_VERSION"
    else
        print_error "Docker is not installed"
        echo "Please install Docker first: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    # Check Docker Compose
    print_status "Checking Docker Compose..."
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null)
        print_success "Docker Compose version: $COMPOSE_VERSION"
    else
        print_error "Docker Compose plugin is not installed"
        echo "Please install Docker Compose plugin: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check ports
    print_status "Checking port 53 availability..."
    if sudo ss -tulpn 2>/dev/null | grep -q ":53 "; then
        if ! handle_port_53_conflict; then
            print_error "Cannot proceed without port 53 available"
            exit 1
        fi
    else
        print_success "Port 53 is available"
    fi
}

# Phase 2: Setup directory structure
setup_directories() {
    print_header "Phase 2: Setting Up Directory Structure"
    
    print_status "Creating directories at $PIHOLE_DIR"
    sudo mkdir -p "$PIHOLE_DIR"
    cd "$PIHOLE_DIR"
    
    print_status "Creating persistent data directories"
    mkdir -p etc-pihole
    mkdir -p etc-dnsmasq.d
    
    print_success "Directory structure created:"
    echo "$PIHOLE_DIR/"
    echo "├── etc-pihole/"
    echo "└── etc-dnsmasq.d/"
}

# Phase 3: Create docker-compose.yml
create_compose_file() {
    print_header "Phase 3: Creating Docker Compose Configuration"
    
    # Get user preferences
    print_status "Configuration settings:"
    echo ""
    
    local ip_address=$(ask_input "Pi-hole server IP address" "$DETECTED_IP")
    local password=$(ask_input "Web interface admin password" "$DEFAULT_PASSWORD")
    local timezone=$(ask_input "Timezone" "$TIMEZONE")
    
    echo ""
    print_status "Upstream DNS servers (optional, leave empty to skip):"
    echo "Popular choices: Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9)"
    local dns1=$(ask_input "Primary upstream DNS" "1.1.1.1")
    local dns2=$(ask_input "Secondary upstream DNS" "1.0.0.1")
    
    print_status "Creating compose.yaml..."
    
    cat > compose.yaml << EOF
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    hostname: pihole
    restart: unless-stopped
    
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "443:443/tcp"
    
    environment:
      TZ: "$timezone"
      WEBPASSWORD: "$password"
      PIHOLE_DNS_: "$dns1;$dns2"
      FTLCONF_LOCAL_IPV4: "$ip_address"
    
    volumes:
      - ./etc-pihole:/etc/pihole
      - ./etc-dnsmasq.d:/etc/dnsmasq.d
    
    cap_add:
      - NET_ADMIN
    
    dns:
      - 127.0.0.1
      - 1.1.1.1
EOF
    
    print_success "compose.yaml created successfully"
    
    # Show configuration summary
    echo ""
    print_header "Configuration Summary"
    echo -e "Server IP:        ${GREEN}$ip_address${NC}"
    echo -e "Web Password:     ${GREEN}$password${NC}"
    echo -e "Timezone:         ${GREEN}$timezone${NC}"
    echo -e "Primary DNS:      ${GREEN}$dns1${NC}"
    echo -e "Secondary DNS:    ${GREEN}$dns2${NC}"
    echo ""
    
    if ! ask_yes_no "Proceed with installation?" "y"; then
        print_warning "Installation cancelled. Configuration files remain in $PIHOLE_DIR"
        exit 0
    fi
}

# Phase 4: Start Pi-hole
start_pihole() {
    print_header "Phase 4: Starting Pi-hole Container"
    
    cd "$PIHOLE_DIR"
    
    print_status "Pulling Pi-hole Docker image..."
    docker compose pull
    
    print_status "Starting Pi-hole container..."
    docker compose up -d
    
    # Wait for container to be ready
    print_status "Waiting for container to initialize..."
    sleep 5
    
    if docker ps | grep -q pihole; then
        print_success "Pi-hole container is running"
        docker ps --filter "name=pihole" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_error "Pi-hole container failed to start"
        print_status "Checking logs:"
        docker compose logs
        exit 1
    fi
}

# Phase 5: Verification and final steps
verify_installation() {
    print_header "Phase 5: Verifying Installation"
    
    cd "$PIHOLE_DIR"
    
    # Get the server IP from compose file
    local server_ip=$(grep FTLCONF_LOCAL_IPV4 compose.yaml | cut -d'"' -f2)
    
    print_success "Installation complete!"
    echo ""
    echo -e "${BOLD}Access your Pi-hole administration panel:${NC}"
    echo -e "  URL: ${GREEN}http://${server_ip}/admin${NC}"
    echo ""
    
    # Test DNS if possible
    print_status "Testing DNS resolution..."
    if command -v nslookup &> /dev/null; then
        if nslookup google.com "$server_ip" &> /dev/null; then
            print_success "DNS resolution working correctly"
        else
            print_warning "DNS test failed - this may be normal if Pi-hole is still initializing"
        fi
    else
        print_status "nslookup not available, skipping DNS test"
    fi
    
    echo ""
    print_header "Next Steps"
    echo -e "${BOLD}1. Access the web interface:${NC}"
    echo -e "   ${CYAN}http://${server_ip}/admin${NC}"
    echo ""
    echo -e "${BOLD}2. Configure your router or devices:${NC}"
    echo -e "   Set DNS server to: ${GREEN}${server_ip}${NC}"
    echo ""
    echo -e "${BOLD}3. Update blocklists:${NC}"
    echo -e "   Web: Settings → Update Gravity"
    echo -e "   CLI: ${CYAN}docker exec pihole pihole -g${NC}"
    echo ""
    echo -e "${BOLD}4. Backup your configuration:${NC}"
    echo -e "   Backup directory: ${CYAN}${PIHOLE_DIR}${NC}"
    echo ""
    echo -e "${BOLD}5. Common commands:${NC}"
    echo -e "   View logs:    ${CYAN}docker logs pihole${NC}"
    echo -e "   Restart:      ${CYAN}docker compose restart${NC}"
    echo -e "   Stop:         ${CYAN}docker compose down${NC}"
    echo -e "   Update:       ${CYAN}docker compose pull && docker compose up -d${NC}"
    echo ""
}

# Main execution
main() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║     Pi-hole Docker Installation Script    ║"
    echo "║           Interactive Setup Wizard        ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_status "This script will guide you through installing Pi-hole using Docker"
    echo ""
    
    # Check if Pi-hole is already installed
    if docker ps -a --format '{{.Names}}' | grep -q '^pihole$'; then
        print_warning "Existing Pi-hole container detected!"
        if ! ask_yes_no "Do you want to continue? (Existing container will be replaced)" "n"; then
            echo "Exiting..."
            exit 0
        fi
        print_status "Stopping existing container..."
        docker compose -f "$PIHOLE_DIR/compose.yaml" down 2>/dev/null || docker stop pihole 2>/dev/null || true
        docker rm pihole 2>/dev/null || true
    fi
    
    echo ""
    
    # Run phases
    check_root
    detect_ip
    check_requirements
    
    if ask_yes_no "Ready to proceed with installation?" "y"; then
        setup_directories
        create_compose_file
        start_pihole
        verify_installation
        
        print_success "Pi-hole installation completed successfully! 🎉"
    else
        print_warning "Installation cancelled by user"
        exit 0
    fi
}

# Run main function
main "$@"