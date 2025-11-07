#!/bin/bash

# Marathon Shell - Build and Run Script
# Incremental builds only (much faster). Run with CLEAN=1 for clean rebuild.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Detect number of CPU cores
if [[ "$OSTYPE" == "darwin"* ]]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=$(nproc)
fi

echo "💻 Detected $CORES CPU cores"

# Clean build if requested
if [ "$CLEAN" = "1" ]; then
    echo "🧹 Clean build requested, removing build directories..."
    rm -rf build build-apps build-ui
fi

# Kill any existing instances first
echo "🛑 Killing any running Marathon Shell instances..."
pkill -9 marathon-shell 2>/dev/null || true

echo ""
echo "============================================"
echo "Marathon OS Incremental Build"
echo "============================================"
echo ""

# Build everything using build-all.sh script
echo "🏗️  Building Marathon Shell and Apps..."
# CRITICAL: Always reinstall apps to ensure source changes are deployed
./scripts/build-all.sh install

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Complete build successful!"
    echo ""
    echo "🚀 Starting Marathon Shell..."
    echo ""
    
    # Check for debug mode
    if [ "$MARATHON_DEBUG" = "1" ] || [ "$MARATHON_DEBUG" = "true" ]; then
        echo "🐛 Debug mode enabled (MARATHON_DEBUG=$MARATHON_DEBUG)"
        echo ""
    fi
    
    # CRITICAL: Disable Qt's automatic HiDPI scaling for the compositor itself
    # The compositor must render at native 1:1 scale, regardless of host DPI
    # Otherwise QWaylandOutput will advertise wrong geometry (e.g. 1080x2280 instead of 540x1140)
    export QT_AUTO_SCREEN_SCALE_FACTOR=0
    export QT_ENABLE_HIGHDPI_SCALING=0
    
    # Check for device DPI simulation (OnePlus 6: ~1.25x scale for 50% window)
    if [ "$DEVICE_DPI" = "1" ] || [ "$DEVICE_DPI" = "oneplus6" ]; then
        export QT_SCALE_FACTOR=1.25
        echo "📱 Device DPI simulation enabled (OnePlus 6: 1.25x scale)"
        echo "   Window: 540x1140 (50% of 1080x2280), DPI: ~402 ppi"
        echo ""
    else
        # Force 1:1 scaling (no DPI scaling from host)
        export QT_SCALE_FACTOR=1
        echo "🖥️  Compositor scaling: 1:1 (native resolution, no HiDPI from host)"
    fi
    
    # Enable QML validation in debug mode
    if [ "$MARATHON_DEBUG" = "1" ] || [ "$MARATHON_DEBUG" = "true" ]; then
        export QML_DISABLE_DISK_CACHE=1
        # Allow all logging in debug mode (same as running binary directly)
        unset QT_LOGGING_RULES
        echo "🔍 Debug mode: Full logging enabled (no filtering)"
        echo ""
    else
        # Disable all debug logging in production
        export QT_LOGGING_RULES="*.debug=false;*.info=false;*.warning=false"
    fi
    
    # Additional Qt environment variables to reduce verbosity
    export QT_QUICK_CONTROLS_STYLE=""
    export QT_QUICK_CONTROLS_IMAGEPROVIDER=""
    export QT_QUICK_CONTROLS_MATERIAL_THEME=""
    export QT_QUICK_CONTROLS_MATERIAL_VARIANT=""
    export QT_QUICK_CONTROLS_UNIVERSAL_THEME=""
    export QT_QUICK_CONTROLS_UNIVERSAL_VARIANT=""
    
    # Set QML import path for MarathonUI modules
    export QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml:$QML_IMPORT_PATH"
    
    # Run the app (detect OS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS .app bundle
        ./build/shell/marathon-shell-bin.app/Contents/MacOS/marathon-shell-bin
    else
        # Linux executable
        ./build/shell/marathon-shell-bin
    fi
else
    echo "❌ Build failed!"
    exit 1
fi
