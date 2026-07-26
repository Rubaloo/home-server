#!/bin/bash
# Phase 01 - Step 07
set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Use: sudo $0"
    exit 1
fi

# Check if system is Debian/Ubuntu based
if ! command -v apt &> /dev/null; then
    error "This script requires apt package manager (Debian/Ubuntu)"
    exit 1
fi

# Main installation function
install_unattended_upgrades() {
    log "Starting unattended-upgrades installation..."
    
    # Update package lists
    log "Updating package lists..."
    apt update -qq || {
        error "Failed to update package lists"
        exit 1
    }
    
    # Install unattended-upgrades
    log "Installing unattended-upgrades package..."
    apt install -y unattended-upgrades || {
        error "Failed to install unattended-upgrades"
        exit 1
    }
    
    log "Package installed successfully"
}

# Configuration function
configure_unattended_upgrades() {
    log "Configuring unattended-upgrades..."
    
    # Create backup of existing config
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        cp /etc/apt/apt.conf.d/50unattended-upgrades \
           /etc/apt/apt.conf.d/50unattended-upgrades.bak.$(date +%Y%m%d_%H%M%S)
        warn "Backup created of existing configuration"
    fi
    
    # Create custom configuration
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
# Unattended-Upgrades configuration
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

# Automatically reboot if needed (optional - set to true to enable)
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

# Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

# Send email notifications (optional)
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailOnlyOnError "true";

# Verbose logging
Unattended-Upgrade::Verbose "true";

# Allow updates for specific packages (example: "nginx;")
Unattended-Upgrade::Package-Blacklist {
    // "nginx";
};

# Download updates in the background
Unattended-Upgrade::Download-Upgradeable-Packages "true";

# Automatically fix broken packages
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";

# Wait 10 minutes after boot before running upgrades
Unattended-Upgrade::AutoAdjustTime "true";
EOF
    
    log "Configuration file created"
    
    # Set up automatic daily updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    
    log "Automatic updates configured"
}

# Restart service function
restart_service() {
    log "Restarting unattended-upgrades service..."
    systemctl restart unattended-upgrades || {
        warn "Failed to restart service, attempting alternative..."
        service unattended-upgrades restart || {
            warn "Unable to restart service, but configuration is complete"
        }
    }
}

# Verification function
verify_setup() {
    log "Verifying installation..."
    
    if dpkg -l | grep -q unattended-upgrades; then
        echo -e "${GREEN}✓${NC} Package installed"
    else
        echo -e "${RED}✗${NC} Package not found"
    fi
    
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        echo -e "${GREEN}✓${NC} Configuration file exists"
    else
        echo -e "${RED}✗${NC} Configuration file missing"
    fi
    
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        echo -e "${GREEN}✓${NC} Auto-upgrades configured"
    else
        echo -e "${RED}✗${NC} Auto-upgrades missing"
    fi
    
    # Show current configuration
    echo -e "\n${YELLOW}Current configuration summary:${NC}"
    echo "----------------------------------------"
    grep -E "^(Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Automatic-Reboot|Unattended-Upgrade::Remove-Unused-Dependencies)" \
        /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || echo "Could not read configuration"
}

# Main execution
main() {
    log "=== Unattended Upgrades Setup ==="
    echo "This script will install and configure automatic security updates"
    echo
    
    # Interactive confirmation (with timeout)
    if [[ -z "${FORCE:-}" ]]; then
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Setup cancelled by user"
            exit 0
        fi
    fi
    
    install_unattended_upgrades
    configure_unattended_upgrades
    restart_service
    verify_setup
    
    log "=== Setup Complete ==="
    echo
    echo "To test the configuration, run:"
    echo "  sudo unattended-upgrades --dry-run"
    echo
    echo "To view logs:"
    echo "  sudo journalctl -u unattended-upgrades -f"
}

# Run main function
main "$@"