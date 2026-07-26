#!/bin/bash
# Phase 01 - Step 11


#!/bin/bash

# Script to add useful aliases to ~/.bashrc

BASHRC="$HOME/.bashrc"

# Check if aliases already exist to avoid duplicates
if grep -q "# Useful aliases" "$BASHRC"; then
    echo "Aliases already exist in ~/.bashrc"
    echo "Do you want to overwrite them? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "Exiting without changes."
        exit 0
    fi
    # Remove existing alias block
    sed -i '/# Useful aliases/,/# End aliases/d' "$BASHRC"
fi

# Append aliases to ~/.bashrc
cat >> "$BASHRC" << 'EOF'

# Useful aliases
alias ll='ls -lah'
alias update='sudo apt update && sudo apt upgrade -y'
alias dc='docker compose'
alias dps='docker ps'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
# End aliases
EOF

echo "Aliases added to ~/.bashrc"

# Reload the bashrc file
echo "Reloading ~/.bashrc..."
source "$BASHRC"

echo "Done! Aliases are now available."
echo "Available aliases:"
echo "  ll      - List files with details"
echo "  update  - Update and upgrade system"
echo "  dc      - Docker compose"
echo "  dps     - Docker ps"
echo "  dcu     - Docker compose up -d"
echo "  dcd     - Docker compose down"