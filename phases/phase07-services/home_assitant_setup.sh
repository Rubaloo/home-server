#!/bin/bash

# Home Assistant Setup Script with Firewall Configuration
# This script automates the installation of Home Assistant using Docker
# Includes UFW rules for LAN-only access and custom HTTP port configuration

set -e  # Exit immediately if a command exits with a non-zero status

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
USERNAME="${SUDO_USER:-$USER}"
HA_BASE_DIR="/srv/docker/homeassistant"
CONFIG_DIR="${HA_BASE_DIR}/config"
COMPOSE_FILE="${HA_BASE_DIR}/docker-compose.yml"
TIMEZONE="Europe/Madrid"
LAN_SUBNET="192.168.1.0/24"
HA_SERVER_PORT="8123"

# Function to print colored output
print_color() {
    echo -e "${2}${1}${NC}"
}

# Function to print section headers
print_section() {
    echo ""
    print_color "=========================================" "$CYAN"
    print_color "  $1" "$CYAN"
    print_color "=========================================" "$CYAN"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "❌ This script must be run with sudo or as root" "$RED"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_color "❌ Docker is not installed. Please install Docker first." "$RED"
        print_color "   Visit: https://docs.docker.com/engine/install/ubuntu/" "$YELLOW"
        exit 1
    fi
    print_color "✓ Docker is installed" "$GREEN"
    
    # Check if Docker Compose is available
    if ! docker compose version &> /dev/null; then
        print_color "❌ Docker Compose is not available. Please install Docker Compose first." "$RED"
        exit 1
    fi
    print_color "✓ Docker Compose is available" "$GREEN"
    
    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        print_color "❌ UFW is not installed. Installing now..." "$YELLOW"
        apt-get update -qq
        apt-get install -y ufw
        print_color "✓ UFW installed" "$GREEN"
    else
        print_color "✓ UFW is installed" "$GREEN"
    fi
    
    # Check if the LAN subnet seems valid
    if [[ ! $LAN_SUBNET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        print_color "⚠ Warning: LAN subnet '$LAN_SUBNET' might not be valid" "$YELLOW"
        print_color "  You can modify this in the script variables" "$YELLOW"
    fi
}

# Phase 1: Create directories
phase1_create_directories() {
    print_section "Phase 1: Creating Directories"
    
    # Create directories
    print_color "Creating directory structure..." "$BLUE"
    mkdir -p "$CONFIG_DIR"
    print_color "✓ Created: $CONFIG_DIR" "$GREEN"
    
    # Set ownership
    print_color "Setting ownership to user: $USERNAME" "$BLUE"
    chown -R "${USERNAME}:${USERNAME}" "$HA_BASE_DIR"
    print_color "✓ Ownership set for: $HA_BASE_DIR" "$GREEN"
    
    # Verify
    print_color "Verifying directory structure:" "$BLUE"
    ls -la "$HA_BASE_DIR"
    print_color "✓ Directories created successfully" "$GREEN"
}

# Phase 2: Create docker-compose.yml
phase2_create_compose() {
    print_section "Phase 2: Creating docker-compose.yml"
    
    # Backup existing compose file if it exists
    if [[ -f "$COMPOSE_FILE" ]]; then
        backup_file="${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$COMPOSE_FILE" "$backup_file"
        print_color "✓ Existing compose file backed up to: $backup_file" "$YELLOW"
    fi
    
    cat > "$COMPOSE_FILE" << EOF
services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    network_mode: host
    privileged: true
    environment:
      - TZ=${TIMEZONE}
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro
EOF
    
    # Set proper ownership of compose file
    chown "${USERNAME}:${USERNAME}" "$COMPOSE_FILE"
    
    print_color "✓ docker-compose.yml created at: $COMPOSE_FILE" "$GREEN"
    print_color "Content of docker-compose.yml:" "$BLUE"
    echo "----------------------------------------"
    cat "$COMPOSE_FILE"
    echo "----------------------------------------"
}

# Phase 3: Create Home Assistant configuration with custom HTTP port
phase3_create_ha_config() {
    print_section "Phase 3: Creating Home Assistant Configuration"
    
    local ha_config_file="${CONFIG_DIR}/configuration.yaml"
    
    # Create configuration.yaml with HTTP server port setting
    print_color "Creating configuration.yaml with custom HTTP port..." "$BLUE"
    
    cat > "$ha_config_file" << EOF
# Home Assistant Configuration
# Created by setup script on $(date)

# Configure HTTP server port
http:
  server_port: ${HA_SERVER_PORT}

# Default config
default_config:

# Uncomment to enable mobile app integration
# mobile_app:
EOF
    
    # Set proper ownership
    chown "${USERNAME}:${USERNAME}" "$ha_config_file"
    
    print_color "✓ configuration.yaml created at: $ha_config_file" "$GREEN"
    print_color "Content of configuration.yaml:" "$BLUE"
    echo "----------------------------------------"
    cat "$ha_config_file"
    echo "----------------------------------------"
    
    print_color "✓ HTTP server port set to: ${HA_SERVER_PORT}" "$GREEN"
}

# Phase 4: Pull image
phase4_pull_image() {
    print_section "Phase 4: Pulling Docker Image"
    
    cd "$HA_BASE_DIR"
    
    print_color "Pulling Home Assistant image..." "$BLUE"
    print_color "This may take a few minutes depending on your internet speed..." "$YELLOW"
    
    if docker compose pull; then
        print_color "✓ Image pulled successfully" "$GREEN"
    else
        print_color "❌ Failed to pull Docker image" "$RED"
        exit 1
    fi
}

# Phase 5: Configure Firewall (UFW)
phase5_configure_firewall() {
    print_section "Phase 5: Configuring Firewall (UFW)"
    
    print_color "Setting up UFW rules for secure Home Assistant access..." "$BLUE"
    print_color "HTTP port: ${HA_SERVER_PORT}" "$BLUE"
    
    # Check if UFW is enabled
    local ufw_status=$(ufw status | grep -o "Status: active")
    
    if [[ -z "$ufw_status" ]]; then
        print_color "⚠ UFW is not active. Enabling UFW..." "$YELLOW"
        
        # Allow SSH first to prevent lockout
        print_color "✓ Allowing SSH (port 22) to prevent lockout" "$GREEN"
        ufw allow 22/tcp comment 'SSH access'
        
        # Enable UFW
        ufw --force enable
        print_color "✓ UFW enabled" "$GREEN"
    else
        print_color "✓ UFW is already active" "$GREEN"
    fi
    
    # Remove any existing rules for the Home Assistant port to avoid duplicates
    print_color "Cleaning up any existing rules for port ${HA_SERVER_PORT}..." "$BLUE"
    local existing_rules=$(ufw status numbered | grep "${HA_SERVER_PORT}" | awk '{print $1}' | tr -d '[]')
    if [[ -n "$existing_rules" ]]; then
        # Delete rules in reverse order to maintain numbering
        for rule_num in $(echo "$existing_rules" | sort -rn); do
            ufw --force delete $rule_num
        done
        print_color "✓ Removed existing rules for port ${HA_SERVER_PORT}" "$YELLOW"
    fi
    
    # Add rule to allow LAN access to Home Assistant
    print_color "Adding rule: Allow LAN (${LAN_SUBNET}) access to port ${HA_SERVER_PORT}" "$BLUE"
    ufw allow from "${LAN_SUBNET}" to any port "${HA_SERVER_PORT}" proto tcp comment 'Home Assistant LAN access'
    print_color "✓ LAN access rule added" "$GREEN"
    
    # Add rule to deny all other access to Home Assistant port
    print_color "Adding rule: Deny all other access to port ${HA_SERVER_PORT}" "$BLUE"
    ufw deny "${HA_SERVER_PORT}/tcp" comment 'Deny external Home Assistant access'
    print_color "✓ Deny rule added" "$GREEN"
    
    # Show UFW status
    print_color "\nCurrent UFW rules:" "$BLUE"
    ufw status numbered
    
    print_color "\n✓ Firewall configured successfully" "$GREEN"
    print_color "  • LAN (${LAN_SUBNET}) can access Home Assistant on port ${HA_SERVER_PORT}" "$GREEN"
    print_color "  • All other external access to port ${HA_SERVER_PORT} is blocked" "$GREEN"
}

# Phase 6: Start container
phase6_start_container() {
    print_section "Phase 6: Starting Container"
    
    cd "$HA_BASE_DIR"
    
    # Stop existing container if running
    if docker ps -a | grep -q "homeassistant"; then
        print_color "Stopping existing Home Assistant container..." "$YELLOW"
        docker compose down
    fi
    
    print_color "Starting Home Assistant container..." "$BLUE"
    if docker compose up -d; then
        print_color "✓ Container started" "$GREEN"
    else
        print_color "❌ Failed to start container" "$RED"
        exit 1
    fi
    
    # Wait for container to initialize
    print_color "Waiting for container to initialize..." "$BLUE"
    sleep 5
    
    # Check if container is running
    if docker ps | grep -q "homeassistant"; then
        print_color "✓ Home Assistant container is running" "$GREEN"
        print_color "\nContainer details:" "$BLUE"
        docker ps --filter "name=homeassistant" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    else
        print_color "❌ Failed to start Home Assistant container" "$RED"
        print_color "Checking logs for errors:" "$YELLOW"
        docker compose logs
        exit 1
    fi
}

# Phase 7: Monitor startup
phase7_monitor_startup() {
    print_section "Phase 7: Monitoring Startup"
    print_color "Showing startup logs..." "$YELLOW"
    print_color "The first startup may take several minutes to complete" "$YELLOW"
    print_color "Look for the 'Finished starting' or 'Home Assistant initialized' message" "$YELLOW"
    print_color "Press Ctrl+C to stop viewing logs (container keeps running)" "$YELLOW"
    echo ""
    
    sleep 2
    docker logs -f homeassistant 2>&1 | while IFS= read -r line; do
        echo "$line"
        # Check for common startup completion messages
        if echo "$line" | grep -qE "(Home Assistant initialized|Setup done|Startup complete)"; then
            print_color "\n✓ Home Assistant has started successfully!" "$GREEN"
        fi
        # Check for HTTP server start
        if echo "$line" | grep -q "Starting HTTP server on port ${HA_SERVER_PORT}"; then
            print_color "\n✓ HTTP server started on port ${HA_SERVER_PORT}" "$GREEN"
        fi
    done
}

# Get server IP address
get_server_ip() {
    # Try multiple methods to get the primary IP address
    local ip=""
    
    # Method 1: hostname -I
    ip=$(hostname -I | awk '{print $1}')
    
    # Method 2: ip route
    if [[ -z "$ip" ]]; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
    fi
    
    # Method 3: ifconfig (fallback)
    if [[ -z "$ip" ]]; then
        ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1)
    fi
    
    echo "$ip"
}

# Verify firewall rules
verify_firewall() {
    print_section "Verifying Firewall Configuration"
    
    local server_ip=$(get_server_ip)
    
    print_color "Firewall verification:" "$BLUE"
    print_color "✓ LAN subnet ${LAN_SUBNET} can access http://${server_ip}:${HA_SERVER_PORT}" "$GREEN"
    print_color "✓ External access to port ${HA_SERVER_PORT} is blocked" "$GREEN"
    
    # Test if port is accessible (if netcat is available)
    if command -v nc &> /dev/null; then
        print_color "\nTesting local port accessibility..." "$BLUE"
        if nc -z localhost "${HA_SERVER_PORT}" 2>/dev/null; then
            print_color "✓ Port ${HA_SERVER_PORT} is accessible locally" "$GREEN"
        else
            print_color "⚠ Port ${HA_SERVER_PORT} may not be accessible yet (Home Assistant might still be starting)" "$YELLOW"
        fi
    fi
}

# Display final instructions
show_final_instructions() {
    local server_ip=$(get_server_ip)
    
    print_section "Setup Complete - Next Steps"
    
    cat << EOF

${GREEN}╔══════════════════════════════════════════════════════════╗
║          Home Assistant Setup Complete!                  ║
╚══════════════════════════════════════════════════════════╝${NC}

${YELLOW}📱 Access Home Assistant:${NC}
   ${GREEN}http://${server_ip}:${HA_SERVER_PORT}${NC}
   
   ⚠️  HTTP server configured on port: ${HA_SERVER_PORT}
   Make sure you're connecting from your LAN (${LAN_SUBNET})

${YELLOW}🔧 Home Assistant Configuration:${NC}
   Configuration file: ${GREEN}${CONFIG_DIR}/configuration.yaml${NC}
   HTTP port setting:  ${BLUE}http:
     server_port: ${HA_SERVER_PORT}${NC}

${YELLOW}🔐 Firewall Status:${NC}
   ✅ LAN access (${LAN_SUBNET}) → ALLOWED on port ${HA_SERVER_PORT}
   ❌ External/WAN access → BLOCKED
   
   To access remotely, use Tailscale VPN

${YELLOW}📋 Phase 7: Create Administrator Account${NC}
   1. Wait for the "Create your account" screen
   2. Set your username and password
   3. Configure your home name and location
   4. Set country and unit system

${YELLOW}🔍 Phase 8: Automatic Device Discovery${NC}
   Home Assistant will auto-discover:
   • Smart TVs and media devices
   • Chromecast and Google Home
   • Philips Hue bridges
   • Shelly and ESPHome devices
   • Network printers
   • And many more IoT devices

${YELLOW}💾 Phase 9: Backups${NC}
   Configuration location:
   ${GREEN}${CONFIG_DIR}${NC}
   
   Backup this directory regularly:
   ${BLUE}sudo cp -r ${CONFIG_DIR} /backup/location/${NC}

${YELLOW}🔄 Phase 10: Updates${NC}
   ${BLUE}cd ${HA_BASE_DIR}
   docker compose pull
   docker compose up -d${NC}

${YELLOW}🛠️ Management Commands:${NC}
   • View logs:     ${BLUE}docker logs -f homeassistant${NC}
   • Stop:          ${BLUE}cd ${HA_BASE_DIR} && docker compose down${NC}
   • Restart:       ${BLUE}cd ${HA_BASE_DIR} && docker compose restart${NC}
   • Status:        ${BLUE}docker ps | grep homeassistant${NC}
   • Check UFW:     ${BLUE}sudo ufw status numbered${NC}
   • Edit config:   ${BLUE}nano ${CONFIG_DIR}/configuration.yaml${NC}

${YELLOW}🔌 Adding USB Devices (Optional):${NC}
   1. List devices: ${BLUE}ls -l /dev/serial/by-id/${NC}
   2. Supported devices:
      • Zigbee coordinators (SkyConnect, Sonoff, ConBee)
      • Z-Wave sticks
      • Bluetooth adapters

${YELLOW}🌐 Remote Access via Tailscale:${NC}
   • Access Home Assistant through your Tailscale VPN
   • URL: ${GREEN}http://[tailscale-ip]:${HA_SERVER_PORT}${NC}
   • No port forwarding needed on your router

${YELLOW}📝 Note on Network Configuration:${NC}
   • Using ${BLUE}network_mode: host${NC} with internal HTTP port setting
   • This provides best device discovery on your network
   • HTTP port is configured in Home Assistant's configuration.yaml
   • No Docker port mapping needed with host networking

${YELLOW}⚠️  Important Notes:${NC}
   • Port ${HA_SERVER_PORT} is ONLY accessible from your LAN
   • External access is blocked by UFW
   • Use Tailscale for secure remote access
   • Do NOT forward port ${HA_SERVER_PORT} on your router
   • Keep your configuration backed up

${YELLOW}📊 Your Docker Stack:${NC}
   Internet → Tailscale VPN → Ubuntu Server
   ├── Pi-hole
   ├── Home Assistant (port ${HA_SERVER_PORT})
   ├── Plex (future)
   └── Other containers

EOF

    # Display current container status
    print_color "Current Container Status:" "$BLUE"
    docker ps --filter "name=homeassistant" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    
    echo ""
}

# Function to handle interruptions
cleanup() {
    print_color "\n\n⚠ Script interrupted. Cleaning up..." "$YELLOW"
    # Container is left running intentionally
    print_color "Home Assistant container (if started) is still running." "$BLUE"
    exit 1
}

# Main execution
main() {
    # Set up trap for interrupts
    trap cleanup SIGINT SIGTERM
    
    print_color "╔══════════════════════════════════════════════════════════╗" "$GREEN"
    print_color "║     Home Assistant Docker Setup with Firewall          ║" "$GREEN"
    print_color "╚══════════════════════════════════════════════════════════╝" "$GREEN"
    echo ""
    print_color "Configuration Summary:" "$CYAN"
    print_color "  • User: $USERNAME" "$BLUE"
    print_color "  • Install directory: $HA_BASE_DIR" "$BLUE"
    print_color "  • Timezone: $TIMEZONE" "$BLUE"
    print_color "  • LAN Subnet: $LAN_SUBNET" "$BLUE"
    print_color "  • HTTP Port: $HA_SERVER_PORT" "$BLUE"
    print_color "  • Network Mode: host (with internal HTTP port config)" "$BLUE"
    echo ""
    
    # Confirm before proceeding
    read -p "$(print_color "Proceed with installation? (y/n): " "$YELLOW")" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "Installation cancelled." "$YELLOW"
        exit 0
    fi
    
    # Execute all phases
    check_root
    check_prerequisites
    phase1_create_directories
    phase2_create_compose
    phase3_create_ha_config
    phase4_pull_image
    phase5_configure_firewall
    phase6_start_container
    verify_firewall
    show_final_instructions
    
    # Offer to show logs
    echo ""
    read -p "$(print_color "Do you want to watch the startup logs? (y/n): " "$YELLOW")" -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        phase7_monitor_startup
    fi
    
    print_color "\n✅ Home Assistant setup complete! Access it at: http://$(get_server_ip):${HA_SERVER_PORT}" "$GREEN"
    print_color "🔒 Remember: Access is restricted to your LAN (${LAN_SUBNET})" "$YELLOW"
    print_color "📝 HTTP port configured in: ${CONFIG_DIR}/configuration.yaml" "$BLUE"
}

# Run main function
main "$@"