#!/bin/bash
# =============================================================================
# fail2ban-post-install.sh
# Automated post-installation configuration script for Fail2ban
# Compatible with Fail2ban v0.11+ (2021 and newer)
# Run with: sudo bash fail2ban-post-install.sh
# =============================================================================
#
# WHAT THIS SCRIPT DOES
# =============================================================================
#
# Step 1: Checks prerequisites
#         Verifies Fail2ban is installed and you're running as root
#
# Step 2: Backs up existing config
#         Creates a dated backup of any existing jail.local
#
# Step 3: Creates comprehensive jail.local
#         Enables common jails that are guaranteed to exist in modern Fail2ban
#         (SSH, Nginx-auth, Apache-auth, FTP, Postfix, Dovecot, Recidive)
#
# Step 4: Creates missing filter files if needed
#         Automatically creates nginx-badbots and other missing filters
#
# Step 5: Creates custom filter example
#         Shows you how to add protection for custom applications
#
# Step 6: Adds helper script
#         Creates fail2ban-status command for quick status checks
#
# Step 7: Validates config
#         Runs fail2ban-client -t to catch any errors before restarting
#
# Step 8: Enables and starts service
#         Uses systemctl enable --now to activate the service
#
# Step 9: Shows summary
#         Displays enabled jails, helpful commands, and next steps
#
# =============================================================================
# IMPORTANT NOTES
# =============================================================================
#
# SSH SAFETY:
#   The script enables SSH protection with stricter rules
#   (3 failures = 1-hour ban). ALWAYS keep another terminal open when
#   first testing to avoid locking yourself out.
#
# IGNORE IPS:
#   You should edit jail.local and add your trusted IPs to ignoreip
#   if you have static IPs.
#
# JAIL SELECTION:
#   The script only enables jails that are guaranteed to exist in
#   standard Fail2ban installations. Missing filters are auto-created.
#
# LOG FILES:
#   Ensure the log paths specified in the jails actually exist on your
#   system. Adjust them if your distribution uses different paths.
#
# =============================================================================

set -e  # Exit on any error

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (sudo)"
    exit 1
fi

# Check if Fail2ban is installed
if ! command -v fail2ban-client &> /dev/null; then
    print_error "Fail2ban is not installed. Please install it first:"
    echo "  sudo apt install fail2ban  # Debian/Ubuntu"
    echo "  sudo yum install fail2ban  # RHEL/CentOS"
    echo "  sudo dnf install fail2ban  # Fedora"
    exit 1
fi

# Detect Fail2ban version
F2B_VERSION=$(fail2ban-client --version | head -n1 | awk '{print $2}')
print_status "Detected Fail2ban version: $F2B_VERSION"

print_status "Starting Fail2ban post-installation configuration..."
echo ""

# 1. Backup existing configuration
print_status "Backing up existing configuration..."
BACKUP_DIR="/etc/fail2ban/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [[ -f /etc/fail2ban/jail.local ]]; then
    cp /etc/fail2ban/jail.local "$BACKUP_DIR/"
    print_success "Existing jail.local backed up to $BACKUP_DIR"
fi

# 2. Create missing filter files
print_status "Creating any missing filter files..."

# Create nginx-badbots filter if it doesn't exist
if [[ ! -f /etc/fail2ban/filter.d/nginx-badbots.conf ]]; then
    print_status "Creating nginx-badbots filter..."
    cat > /etc/fail2ban/filter.d/nginx-badbots.conf << 'EOF'
# Fail2ban filter for nginx bad bots

[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*"(?:Mozilla|Opera|MSIE).*$
            ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*"(?:bot|crawler|spider|scanner).*$
ignoreregex =

[Init]
datepattern = ^[^\[]*\[
EOF
    print_success "Created nginx-badbots filter"
fi

# Create apache-badbots filter if it doesn't exist
if [[ ! -f /etc/fail2ban/filter.d/apache-badbots.conf ]]; then
    print_status "Creating apache-badbots filter..."
    cat > /etc/fail2ban/filter.d/apache-badbots.conf << 'EOF'
# Fail2ban filter for apache bad bots

[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*HTTP.*"(?:Mozilla|Opera|MSIE).*$
            ^<HOST> .* "(GET|POST|HEAD).*HTTP.*"(?:bot|crawler|spider|scanner).*$
ignoreregex =

[Init]
datepattern = ^[^\[]*\[
EOF
    print_success "Created apache-badbots filter"
fi

# Create recidive filter if it doesn't exist
if [[ ! -f /etc/fail2ban/filter.d/recidive.conf ]]; then
    print_status "Creating recidive filter..."
    cat > /etc/fail2ban/filter.d/recidive.conf << 'EOF'
# Fail2ban filter for recidive (repeat offenders)

[Definition]
failregex = ^.*\[.*\] NOTICE  \[.*\] Ban <HOST>$
ignoreregex =

[Init]
datepattern = ^[^\[]*\[
EOF
    print_success "Created recidive filter"
fi

# 3. Create jail.local configuration (with only guaranteed existing filters)
print_status "Creating jail.local configuration..."

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban time: how long to ban an IP (default: 10m)
bantime = 10m

# Find time: the time window for counting failures (default: 10m)
findtime = 10m

# Max retries: number of failures before banning (default: 5)
maxretry = 5

# Log level (INFO, WARNING, DEBUG, etc.)
loglevel = INFO

# Log target (SYSLOG, STDOUT, file path)
logtarget = /var/log/fail2ban.log

# Ignore self IP (localhost)
ignoreip = 127.0.0.1/8 ::1

# Custom ignore IPs (uncomment and modify for trusted IPs)
# ignoreip = 192.168.1.0/24 10.0.0.0/8

# Email notifications (optional)
# destemail = root@localhost
# sender = root@localhost
# mta = sendmail
# action = %(action_mwl)s

# Enable all jails by default? 
# Set to false to enable only specific jails listed below
enabled = false

# =================================================
# JAIL CONFIGURATIONS (COMMON SERVICES)
# =================================================

[sshd]
# SSH server protection - Most common and important jail
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
backend = systemd
maxretry = 3
bantime = 1h
findtime = 10m

[nginx-http-auth]
# Nginx HTTP basic authentication protection
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
backend = systemd
maxretry = 5
bantime = 1h

[nginx-badbots]
# Block bad bots from Nginx (filter auto-created if missing)
enabled = false  # Disabled by default - enable if you have Nginx
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
backend = systemd
bantime = 48h
maxretry = 1

[apache-auth]
# Apache HTTP basic authentication protection
enabled = false  # Disabled by default - enable if you have Apache
port = http,https
filter = apache-auth
logpath = /var/log/apache*/*error.log
backend = systemd
maxretry = 5
bantime = 1h

[apache-badbots]
# Block bad bots from Apache (filter auto-created if missing)
enabled = false  # Disabled by default - enable if you have Apache
port = http,https
filter = apache-badbots
logpath = /var/log/apache*/*access.log
backend = systemd
bantime = 48h
maxretry = 1

[proftpd]
# FTP server protection (ProFTPd)
enabled = false  # Disabled by default - enable if you use ProFTPd
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
backend = systemd
maxretry = 5
bantime = 1h

[vsftpd]
# FTP server protection (vsFTPd)
enabled = false  # Disabled by default - enable if you use vsFTPd
port = ftp,ftp-data,ftps,ftps-data
filter = vsftpd
logpath = /var/log/vsftpd.log
backend = systemd
maxretry = 5
bantime = 1h

[postfix]
# Mail server protection (Postfix)
enabled = false  # Disabled by default - enable if you run a mail server
port = smtp,ssmtp,submission
filter = postfix
logpath = /var/log/mail.log
backend = systemd
maxretry = 5
bantime = 1h

[dovecot]
# Email IMAP/POP3 server protection
enabled = false  # Disabled by default - enable if you use Dovecot
port = pop3,pop3s,imap,imaps,submission,smtp
filter = dovecot
logpath = /var/log/mail.log
backend = systemd
maxretry = 5
bantime = 1h

[recidive]
# Recidive jail - catches repeat offenders (filter auto-created if missing)
enabled = true
logpath = /var/log/fail2ban.log
filter = recidive
backend = systemd
bantime = 1w
maxretry = 5
findtime = 1d

# =================================================
# ADDITIONAL CUSTOM JAILS (UNCOMMENT TO ENABLE)
# =================================================

#[asterisk]
#enabled = true
#port = sip,5060,5061
#filter = asterisk
#logpath = /var/log/asterisk/security
#backend = systemd
#maxretry = 10
#bantime = 1h

#[roundcube]
#enabled = true
#port = http,https
#filter = roundcube
#logpath = /var/log/roundcube/errors.log
#backend = systemd
#maxretry = 5
#bantime = 1h

#[wordpress]
#enabled = true
#port = http,https
#filter = wordpress
#logpath = /var/log/nginx/access.log
#backend = systemd
#maxretry = 5
#bantime = 1h

#[custom-app]
#enabled = true
#port = http,https
#filter = custom-auth
#logpath = /var/log/myapp/auth.log
#backend = systemd
#maxretry = 5
#bantime = 1h
EOF

print_success "jail.local configuration created"

# 4. Create custom filter file (example)
print_status "Creating example custom filter file..."
mkdir -p /etc/fail2ban/filter.d

cat > /etc/fail2ban/filter.d/custom-auth.conf << 'EOF'
# Fail2ban filter for custom application authentication failures
# To use, create a log file with failed attempts containing "Authentication failed for user"
# and enable a jail that uses this filter

[Definition]
failregex = ^.*Authentication failed for user .* from <HOST>.*$
ignoreregex = 

# Example usage in jail.local:
# [custom-app]
# enabled = true
# port = http,https
# filter = custom-auth
# logpath = /var/log/myapp/auth.log
# backend = systemd
# maxretry = 5
# bantime = 1h
EOF

print_success "Custom filter file created"

# 5. Create a script to view banned IPs
print_status "Creating helper script to view banned IPs..."

cat > /usr/local/bin/fail2ban-status << 'EOF'
#!/bin/bash
# Helper script to view Fail2ban status and banned IPs

echo "=== Fail2ban Status ==="
echo ""

# Show active jails
echo "Active Jails:"
fail2ban-client status | grep "Jail list" | sed 's/^[[:space:]]*//'
echo ""

# Show status for each jail
for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://' | tr ',' ' '); do
    jail=$(echo $jail | xargs)  # Trim whitespace
    if [[ -n "$jail" ]]; then
        echo "--- $jail ---"
        fail2ban-client status "$jail"
        echo ""
    fi
done

echo "=== Active Firewall Bans ==="
if command -v iptables &> /dev/null; then
    echo "IPTables Fail2ban chains:"
    sudo iptables -L INPUT -n | grep -E "(fail2ban|Chain INPUT)" || echo "No fail2ban chains found"
else
    echo "IPTables not available"
fi
echo ""

echo "=== Recent Bans (last 20 entries) ==="
if [[ -f /var/log/fail2ban.log ]]; then
    tail -20 /var/log/fail2ban.log | grep -E "(Ban|Unban)" || echo "No recent bans found"
else
    echo "Log file not found"
fi
EOF

chmod +x /usr/local/bin/fail2ban-status
print_success "Helper script created: /usr/local/bin/fail2ban-status"

# 6. Validate configuration
print_status "Validating Fail2ban configuration..."
if fail2ban-client -t 2>&1 | grep -q "OK"; then
    print_success "Configuration is valid"
else
    print_error "Configuration validation failed!"
    echo ""
    echo "Error details:"
    fail2ban-client -t
    echo ""
    print_warning "If you see errors about missing filters, the script attempted to create them."
    print_warning "Check /etc/fail2ban/filter.d/ for the missing files."
    exit 1
fi

# 7. Enable and start the service
print_status "Enabling and starting Fail2ban service..."
systemctl enable fail2ban
systemctl restart fail2ban

# 8. Check service status
print_status "Checking service status..."
sleep 2  # Give the service a moment to start
if systemctl is-active --quiet fail2ban; then
    print_success "Fail2ban service is running"
    print_success "Service is enabled to start on boot"
else
    print_error "Fail2ban service failed to start!"
    systemctl status fail2ban
    exit 1
fi

# 9. Show summary
echo ""
echo "=================================================="
echo -e "${GREEN}✓ Fail2ban Post-Installation Complete!${NC}"
echo "=================================================="
echo ""
echo "Key Information:"
echo "  - Configuration: /etc/fail2ban/jail.local"
echo "  - Log file: /var/log/fail2ban.log"
echo "  - Helper script: /usr/local/bin/fail2ban-status"
echo "  - Backup location: $BACKUP_DIR"
echo "  - Fail2ban version: $F2B_VERSION"
echo ""
echo "Enabled Jails (SSH protection is active):"
fail2ban-client status | grep "Jail list" | sed 's/^[[:space:]]*//' || echo "  No jails enabled"
echo ""
echo "Quick Commands:"
echo "  - View overall status: sudo fail2ban-client status"
echo "  - View helper script: sudo fail2ban-status"
echo "  - View specific jail: sudo fail2ban-client status sshd"
echo "  - Unban an IP: sudo fail2ban-client set sshd unbanip <IP>"
echo "  - Check logs: tail -f /var/log/fail2ban.log"
echo ""
echo "Next Steps:"
echo "  1. Review and customize /etc/fail2ban/jail.local"
echo "  2. Add your own IPs to 'ignoreip' to avoid locking yourself out"
echo "  3. Enable additional jails by setting 'enabled = true'"
echo "  4. Test the configuration: sudo fail2ban-client -t"
echo ""
echo "Jails currently disabled but available (set enabled=true to activate):"
echo "  - nginx-badbots, apache-auth, apache-badbots"
echo "  - proftpd, vsftpd, postfix, dovecot"
echo ""
print_warning "IMPORTANT: If using SSH, keep another terminal open while testing!"
echo "=================================================="

# Optional: Show initial status
echo ""
print_status "Initial status of Fail2ban:"
/usr/local/bin/fail2ban-status