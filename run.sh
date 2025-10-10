#!/bin/bash

# Marathon Shell - Build and Run Script

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Kill any existing instances first
echo "🛑 Killing any running Marathon Shell instances..."
pkill -9 marathon-shell 2>/dev/null || true

echo "🏗️  Building Marathon Shell..."
cmake --build build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Starting Marathon Shell..."
    echo ""
    
    # Run the app
    ./build/shell/marathon-shell
else
    echo "❌ Build failed!"
    exit 1
fi

