#!/bin/bash

# Marathon Shell - Build and Run Script

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

echo "🏗️  Building Marathon Shell with $CORES parallel jobs..."
cmake --build build --parallel $CORES

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Install system apps
    echo "📦 Installing system apps..."
    bash scripts/install-system-apps.sh
    
    echo "🚀 Starting Marathon Shell..."
    echo ""
    
    # Run the app (macOS .app bundle)
    ./build/shell/marathon-shell.app/Contents/MacOS/marathon-shell
else
    echo "❌ Build failed!"
    exit 1
fi

