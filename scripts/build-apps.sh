#!/bin/bash
# Build all Marathon apps as QML modules with optional C++ plugins

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build-apps"
INSTALL_DIR="$HOME/.local/share/marathon-apps"

echo "============================================"
echo "Marathon Apps Build System"
echo "============================================"
echo "Project root: $PROJECT_ROOT"
echo "Build directory: $BUILD_DIR"
echo "Install directory: $INSTALL_DIR"
echo "============================================"
echo ""

# Clean install directory before building
echo "🧹 Cleaning install directory..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"/*
    echo "✅ Cleaned existing apps from $INSTALL_DIR"
else
    echo "📁 Install directory doesn't exist, will be created"
fi
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure CMake for apps
echo "Configuring CMake..."
cmake "$PROJECT_ROOT/apps" \
    -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt@6" \
    -DCMAKE_BUILD_TYPE=Release \
    -DMARATHON_APPS_DIR="$INSTALL_DIR"

echo ""
echo "Building apps..."
cmake --build . --parallel $(sysctl -n hw.ncpu)

echo ""
echo "Installing apps to $INSTALL_DIR..."
cmake --install .

echo ""
echo "✅ All apps built and installed successfully!"
echo ""
echo "Installed apps:"
ls -1 "$INSTALL_DIR"
echo ""
echo "App structure:"
for app in "$INSTALL_DIR"/*; do
    if [ -d "$app" ]; then
        appname=$(basename "$app")
        echo "  $appname/"
        if [ -f "$app/lib${appname}-plugin.dylib" ] || [ -f "$app/lib${appname}-plugin.so" ]; then
            echo "    ✓ C++ plugin found"
        else
            echo "    ○ Pure QML"
        fi
        if [ -f "$app/manifest.json" ]; then
            echo "    ✓ manifest.json"
        fi
        if [ -f "$app/qmldir" ]; then
            echo "    ✓ qmldir"
        fi
    fi
done
echo ""
echo "To rebuild a specific app:"
echo "  cd $BUILD_DIR && make browser-plugin && cmake --install ."
echo ""
echo "To clean and rebuild all:"
echo "  rm -rf $BUILD_DIR && $0"

