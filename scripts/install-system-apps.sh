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

# Install all system apps
echo "Installing system apps..."
for app in settings notes clock calendar gallery music messages phone maps camera; do
    if [ -d "$PROJECT_ROOT/apps/$app" ]; then
        echo "  - $app"
        cp -r "$PROJECT_ROOT/apps/$app" "$INSTALL_DIR/"
    fi
done

echo ""
echo "✅ System apps installed successfully!"
echo "Installed apps:"
ls "$INSTALL_DIR"
echo ""
echo "To verify installation:"
echo "   ls -la $INSTALL_DIR/"

