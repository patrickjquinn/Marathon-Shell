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
    rm -rf build build-apps
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
./scripts/build-all.sh

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
    
    # Enable QML validation in debug mode
    if [ "$MARATHON_DEBUG" = "1" ] || [ "$MARATHON_DEBUG" = "true" ]; then
        export QML_DISABLE_DISK_CACHE=1
        export QT_LOGGING_RULES="qml.debug=false;qt.qml.debug=false;qt.quick.debug=false"
        echo "🔍 QML validation enabled (cache disabled, reduced logging)"
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
        ./build/shell/marathon-shell.app/Contents/MacOS/marathon-shell
    else
        # Linux executable
        ./build/shell/marathon-shell
    fi
else
    echo "❌ Build failed!"
    exit 1
fi
