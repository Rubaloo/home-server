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
