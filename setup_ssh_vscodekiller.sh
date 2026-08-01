#!/bin/bash

# Complete setup script for VSCode Remote Killer
# This script sets up SSH config, SSH agent, and creates aliases

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REMOTE_USER="${1:-rubaloo}"
REMOTE_IP="${2:-192.168.1.50}"
REMOTE_PORT="${3:-2222}"
SSH_KEY="${4:-$HOME/.ssh/id_ed25519}"
HOST_ALIAS="${5:-homeserver}"

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KILL_SCRIPT="${SCRIPT_DIR}/kill_vscode_remote.sh"

echo "════════════════════════════════════════════════════════════"
echo -e "${BLUE}  🚀 VSCode Remote Killer - Setup Wizard${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Remote User:   $REMOTE_USER"
echo "  Remote IP:     $REMOTE_IP"
echo "  Remote Port:   $REMOTE_PORT"
echo "  SSH Key:       $SSH_KEY"
echo "  Host Alias:    $HOST_ALIAS"
echo ""

# Step 1: Check SSH key
echo -e "${BLUE}Step 1: Checking SSH Key${NC}"
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}❌ SSH key not found: $SSH_KEY${NC}"
    echo "   Creating a new SSH key without passphrase for automation..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "vscode-killer-automation"
    echo -e "${GREEN}✅ Created new SSH key: $SSH_KEY${NC}"
else
    echo -e "${GREEN}✅ SSH key found: $SSH_KEY${NC}"
fi
echo ""

# Step 2: Copy public key to remote
echo -e "${BLUE}Step 2: Copying Public Key to Remote Server${NC}"
echo "   This will require your remote password (if not already set up)"
read -p "   Press Enter to continue or Ctrl+C to cancel..."
ssh-copy-id -p "$REMOTE_PORT" -i "${SSH_KEY}.pub" "$REMOTE_USER@$REMOTE_IP"
echo -e "${GREEN}✅ Public key copied to remote server${NC}"
echo ""

# Step 3: Setup SSH Config
echo -e "${BLUE}Step 3: Setting up SSH Config${NC}"
SSH_CONFIG="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Check if host alias already exists
if grep -q "Host $HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Host '$HOST_ALIAS' already exists in SSH config${NC}"
    echo "   Removing existing entry..."
    # Backup config
    cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    # Remove existing host entry (simple approach - sed to delete between Host and next Host)
    sed -i "/^Host $HOST_ALIAS$/,/^Host /{/^Host $HOST_ALIAS$/d; /^Host /!d;}" "$SSH_CONFIG" 2>/dev/null || true
fi

# Add new host configuration
cat >> "$SSH_CONFIG" << EOF

# VSCode Remote Killer - Added $(date)
Host $HOST_ALIAS
    HostName $REMOTE_IP
    User $REMOTE_USER
    Port $REMOTE_PORT
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF

chmod 600 "$SSH_CONFIG"
echo -e "${GREEN}✅ SSH config updated for '$HOST_ALIAS'${NC}"
echo ""

# Step 4: Setup SSH Agent
echo -e "${BLUE}Step 4: Setting up SSH Agent${NC}"

# Create SSH agent helper script
AGENT_HELPER="$HOME/.ssh/ssh-agent-helper.sh"
cat > "$AGENT_HELPER" << 'EOF'
#!/bin/bash
# SSH Agent Helper - Auto-start and add keys

# Check if SSH agent is running
if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "🔑 Starting SSH agent..."
    eval "$(ssh-agent -s)" > /dev/null
fi

# Add keys if not already added
if ! ssh-add -l &>/dev/null; then
    echo "🔑 Adding SSH keys to agent..."
    # Add all id_* keys in .ssh directory
    for key in ~/.ssh/id_*; do
        if [ -f "$key" ] && [[ ! "$key" == *.pub ]]; then
            ssh-add "$key" 2>/dev/null && echo "   Added: $key"
        fi
    done
fi
EOF

chmod +x "$AGENT_HELPER"

# Add to .bashrc if not already there
if ! grep -q "source $AGENT_HELPER" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# SSH Agent Helper" >> "$HOME/.bashrc"
    echo "source $AGENT_HELPER" >> "$HOME/.bashrc"
    echo -e "${GREEN}✅ Added SSH agent helper to .bashrc${NC}"
fi

# Also add to .profile for non-interactive shells
if ! grep -q "source $AGENT_HELPER" "$HOME/.profile" 2>/dev/null; then
    echo "" >> "$HOME/.profile"
    echo "# SSH Agent Helper" >> "$HOME/.profile"
    echo "source $AGENT_HELPER" >> "$HOME/.profile"
    echo -e "${GREEN}✅ Added SSH agent helper to .profile${NC}"
fi

echo -e "${GREEN}✅ SSH agent setup complete${NC}"
echo ""

# Step 5: Create the kill script
echo -e "${BLUE}Step 5: Creating VSCode Kill Script${NC}"

cat > "$KILL_SCRIPT" << 'EOF'
#!/bin/bash

# Remote VSCode Killer
# Usage: ./kill_vscode_remote.sh [host_alias]

# Default host alias
HOST_ALIAS="${1:-homeserver}"
VERBOSE=0

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [host_alias] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed output"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Use default 'homeserver' alias"
            echo "  $0 myserver      # Use 'myserver' alias from SSH config"
            echo "  $0 -v            # Verbose mode"
            exit 0
            ;;
        *)
            HOST_ALIAS="$1"
            shift
            ;;
    esac
done

# Function to check if host exists in SSH config
check_host() {
    if ! grep -q "Host $HOST_ALIAS" ~/.ssh/config 2>/dev/null; then
        echo -e "${RED}❌ Host '$HOST_ALIAS' not found in SSH config${NC}"
        echo "   Available hosts:"
        grep "^Host " ~/.ssh/config | grep -v "Host \*" | sed 's/Host //' | sed 's/^/   - /'
        return 1
    fi
    return 0
}

# Function to ensure SSH agent is running
ensure_ssh_agent() {
    if [ -z "$SSH_AUTH_SOCK" ]; then
        eval "$(ssh-agent -s)" > /dev/null
    fi
}

# Main execution
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  🔧 VSCode Remote Killer${NC}"
echo "════════════════════════════════════════════════════════════"
echo "  Target: $HOST_ALIAS"
[ $VERBOSE -eq 1 ] && echo "  Mode: VERBOSE"
echo "════════════════════════════════════════════════════════════"

# Check host
if ! check_host; then
    exit 1
fi

# Ensure SSH agent is running
ensure_ssh_agent

# Test connection
echo -n "🔍 Testing SSH connection... "
if ssh -q -o ConnectTimeout=5 "$HOST_ALIAS" "exit" 2>/dev/null; then
    echo -e "${GREEN}✅ Connected${NC}"
else
    echo -e "${RED}❌ Failed to connect${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if remote is reachable"
    echo "  2. Run: ssh-add ~/.ssh/id_ed25519"
    echo "  3. Test manually: ssh $HOST_ALIAS"
    exit 1
fi

# Check for VSCode processes
echo -n "🔍 Checking for VSCode processes... "

if [ $VERBOSE -eq 1 ]; then
    echo ""
    ssh "$HOST_ALIAS" "ps aux | grep -E '[v]scode|[c]ode' | grep -v grep || echo '   (none)'"
else
    echo ""
fi

# Kill VSCode processes
echo -n "⚡ Killing VSCode processes... "
RESULT=$(ssh "$HOST_ALIAS" "pkill -f vscode 2>/dev/null && echo 'KILLED' || echo 'NONE'" 2>/dev/null)

if [ "$RESULT" = "KILLED" ]; then
    echo -e "${GREEN}✅ Killed successfully${NC}"
else
    echo -e "${YELLOW}ℹ️  No VSCode processes running${NC}"
fi

# Verify
sleep 1
REMAINING=$(ssh "$HOST_ALIAS" "ps aux | grep -E '[v]scode|[c]ode' | grep -v grep | wc -l" 2>/dev/null)

if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✅ Verification: No VSCode processes remaining${NC}"
else
    echo -e "${RED}⚠️  Warning: $REMAINING process(es) still running${NC}"
    if [ $VERBOSE -eq 1 ]; then
        ssh "$HOST_ALIAS" "ps aux | grep -E '[v]scode|[c]ode' | grep -v grep"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Operation completed!${NC}"
echo "════════════════════════════════════════════════════════════"
EOF

chmod +x "$KILL_SCRIPT"
echo -e "${GREEN}✅ Created kill script: $KILL_SCRIPT${NC}"
echo ""

# Step 6: Create aliases
echo -e "${BLUE}Step 6: Creating Aliases${NC}"

# Create bash aliases file if it doesn't exist
touch "$HOME/.bash_aliases"

# Add aliases if not already present
ALIASES_ADDED=0

if ! grep -q "alias kill-vscode=" "$HOME/.bash_aliases" 2>/dev/null; then
    echo "# VSCode Remote Killer Aliases" >> "$HOME/.bash_aliases"
    echo "alias kill-vscode='$KILL_SCRIPT'" >> "$HOME/.bash_aliases"
    echo "alias kill-vscode-verbose='$KILL_SCRIPT -v'" >> "$HOME/.bash_aliases"
    echo "alias kv='$KILL_SCRIPT'" >> "$HOME/.bash_aliases"
    ALIASES_ADDED=1
    echo -e "${GREEN}✅ Added aliases to .bash_aliases${NC}"
else
    echo -e "${YELLOW}⚠️  Aliases already exist in .bash_aliases${NC}"
fi

# Also add to .bashrc if .bash_aliases isn't sourced
if ! grep -q "~/.bash_aliases" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Alias definitions" >> "$HOME/.bashrc"
    echo "if [ -f ~/.bash_aliases ]; then" >> "$HOME/.bashrc"
    echo "    . ~/.bash_aliases" >> "$HOME/.bashrc"
    echo "fi" >> "$HOME/.bashrc"
    echo -e "${GREEN}✅ Added .bash_aliases sourcing to .bashrc${NC}"
fi

echo ""

# Step 7: Test everything
echo -e "${BLUE}Step 7: Testing Setup${NC}"

# Load SSH agent helper
source "$AGENT_HELPER"

# Test connection
echo -n "🔍 Testing connection to '$HOST_ALIAS'... "
if ssh -q -o ConnectTimeout=5 "$HOST_ALIAS" "echo 'Connected!'" 2>/dev/null; then
    echo -e "${GREEN}✅ Success!${NC}"
else
    echo -e "${RED}❌ Failed! Please check your configuration.${NC}"
fi

echo ""

# Step 8: Summary
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📋 What was installed:"
echo "  📁 SSH Config:      ~/.ssh/config (alias: $HOST_ALIAS)"
echo "  📁 SSH Agent:       ~/.ssh/ssh-agent-helper.sh"
echo "  📁 Kill Script:     $KILL_SCRIPT"
echo "  📁 Aliases:         Added to ~/.bash_aliases"
echo ""
echo "🚀 How to use:"
echo "  1. Load the new aliases:"
echo "     source ~/.bashrc"
echo ""
echo "  2. Use the commands (no passphrase needed after first time):"
echo "     kill-vscode              # Kill VSCode on remote"
echo "     kill-vscode-verbose      # With detailed output"
echo "     kv                       # Short version"
echo ""
echo "  3. Or run the script directly:"
echo "     $KILL_SCRIPT"
echo "     $KILL_SCRIPT -v          # Verbose mode"
echo "     $KILL_SCRIPT myserver    # Use different host alias"
echo ""
echo "  4. Manage SSH agent:"
echo "     ssh-add -l               # List loaded keys"
echo "     ssh-add ~/.ssh/id_ed25519 # Manually add key"
echo ""
echo "💡 Tip: You'll be prompted for your SSH key passphrase"
echo "   only once per login session when SSH agent starts."
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}🎉 Setup complete! Run 'source ~/.bashrc' to use the aliases.${NC}"
echo "════════════════════════════════════════════════════════════"