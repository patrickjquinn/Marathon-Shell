#!/bin/bash

# Install system apps to /usr/local/share/marathon-apps/ (user-writable on macOS)
# This script should be run after building the shell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use user-writable directory for development
INSTALL_DIR="$HOME/.local/share/marathon-apps"
echo "Installing to: $INSTALL_DIR"

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Install Settings app
echo "Installing Settings app..."
cp -r "$PROJECT_ROOT/apps/settings" "$INSTALL_DIR/"

echo ""
echo "✅ System apps installed successfully!"
echo "   Settings app: $INSTALL_DIR/settings/"
echo ""
echo "To verify installation:"
echo "   ls -la $INSTALL_DIR/settings/"

