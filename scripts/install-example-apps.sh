#!/bin/bash

# Install example apps to ~/.local/share/marathon-apps/
# This script should be run after building the shell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use user-writable directory
INSTALL_DIR="$HOME/.local/share/marathon-apps"
echo "Installing example apps to: $INSTALL_DIR"

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Install Calculator app
if [ -d "$PROJECT_ROOT/example-apps/calculator" ]; then
    echo "Installing Calculator app..."
    cp -r "$PROJECT_ROOT/example-apps/calculator" "$INSTALL_DIR/"
else
    echo "Calculator app not found, skipping..."
fi

echo ""
echo "✅ Example apps installed successfully!"
echo ""
echo "Installed apps:"
ls -1 "$INSTALL_DIR" | grep -v "settings" || true
echo ""
echo "To verify installation:"
echo "   ls -la $INSTALL_DIR/"

