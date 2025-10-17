#!/bin/bash
# Build Marathon Shell AND all apps in one command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "Marathon OS Complete Build"
echo "============================================"
echo ""

# Step 1: Build Marathon Shell
echo "Step 1/2: Building Marathon Shell..."
echo "----------------------------------------"
cd "$PROJECT_ROOT"

if [ ! -d "build" ]; then
    echo "Creating build directory..."
    mkdir -p build
    cd build
    cmake .. \
        -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt@6" \
        -DCMAKE_BUILD_TYPE=Release
    cd ..
fi

cd build
cmake --build . --parallel $(sysctl -n hw.ncpu)
cd ..

echo ""
echo "✅ Marathon Shell built successfully!"
echo ""

# Step 2: Build all Marathon Apps
echo "Step 2/2: Building Marathon Apps..."
echo "----------------------------------------"
"$SCRIPT_DIR/build-apps.sh"

echo ""
echo "============================================"
echo "✅ Complete Build Successful!"
echo "============================================"
echo ""
echo "To run Marathon Shell:"
echo "  ./build/shell/marathon-shell"
echo ""
echo "To rebuild just the shell:"
echo "  cd build && make -j$(sysctl -n hw.ncpu)"
echo ""
echo "To rebuild just the apps:"
echo "  ./scripts/build-apps.sh"
echo ""

