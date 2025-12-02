#!/bin/bash
set -e

FONT_DIR="/usr/local/share/fonts/marathon"
SOURCE_DIR="shell/resources/fonts"

echo "Installing Marathon Shell fonts..."

# Create font directory
sudo mkdir -p "$FONT_DIR"

# Copy fonts
if [ -d "$SOURCE_DIR" ]; then
    sudo cp "$SOURCE_DIR"/*.TTF "$FONT_DIR/" 2>/dev/null || sudo cp "$SOURCE_DIR"/*.ttf "$FONT_DIR/"
    echo "Fonts copied to $FONT_DIR"
else
    echo "Error: Font source directory '$SOURCE_DIR' not found!"
    exit 1
fi

# Update font cache
echo "Updating font cache..."
sudo fc-cache -fv

# Verify installation
echo "Verifying 'Slate' font..."
if fc-list : family | grep -q "Slate"; then
    echo "✅ Slate font installed successfully!"
else
    echo "❌ Slate font NOT found in system cache."
    exit 1
fi
