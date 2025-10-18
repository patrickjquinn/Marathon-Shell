#!/bin/bash

# Marathon Shell - Build and Run Script
# Now builds BOTH shell AND apps using the new build system

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

# Kill any existing instances first
echo "🛑 Killing any running Marathon Shell instances..."
pkill -9 marathon-shell 2>/dev/null || true

echo ""
echo "============================================"
echo "Marathon OS Complete Build"
echo "============================================"
echo ""

# Build everything using new build-all.sh script
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
    
    # Run the app (macOS .app bundle)
    ./build/shell/marathon-shell.app/Contents/MacOS/marathon-shell
else
    echo "❌ Build failed!"
    exit 1
fi
