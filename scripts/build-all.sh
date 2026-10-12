#!/bin/bash
# Build Marathon Shell AND all apps in one command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "Marathon OS Complete Build"
echo "============================================"
echo ""

    # Detect OS and set Qt path
    if [[ "$OSTYPE" == "darwin"* ]]; then
        QT_PATH="/opt/homebrew/opt/qt@6"
    else
        QT_PATH="/usr"
    fi
    
# Detect CPU cores for parallel build
if [[ "$OSTYPE" == "darwin"* ]]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=$(nproc)
fi

# Step 1: Build Marathon Shell
echo "Step 1/2: Building Marathon Shell..."
echo "----------------------------------------"
cd "$PROJECT_ROOT"

# Check if build directory exists and has correct generator
NEEDS_RECONFIGURE=false
if [ ! -d "build" ]; then
    echo "Creating build directory..."
    mkdir -p build
    NEEDS_RECONFIGURE=true
elif [ -f "build/CMakeCache.txt" ]; then
    # Check if generator is Ninja
    if ! grep -q "CMAKE_GENERATOR:INTERNAL=Ninja" build/CMakeCache.txt 2>/dev/null; then
        echo "  Build directory uses wrong generator (not Ninja), reconfiguring..."
        rm -rf build
        mkdir -p build
        NEEDS_RECONFIGURE=true
    fi
fi

if [ "$NEEDS_RECONFIGURE" = true ]; then
    cd build
    cmake .. \
        -G Ninja \
        -DCMAKE_PREFIX_PATH="$QT_PATH" \
        -DCMAKE_BUILD_TYPE=Release
    cd ..
fi

cd build

cmake --build . --parallel $CORES
cd ..

echo ""
echo " Marathon Shell built successfully!"
echo ""

# Step 2: Build all Marathon Apps
echo "Step 2/2: Building Marathon Apps..."
echo "----------------------------------------"
# Pass any arguments (like "install") to build-apps.sh
# QML linting is handled by build-apps.sh and CMake qmllint targets
"$SCRIPT_DIR/build-apps.sh" "$@"

echo ""
echo "============================================"
echo " Complete Build Successful!"
echo "============================================"
echo ""
echo "To run Marathon Shell:"
echo "  ./build/shell/marathon-shell-bin"
echo ""
echo "To rebuild just the shell:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  cd build && cmake --build . --parallel $(sysctl -n hw.ncpu)"
else
    echo "  cd build && cmake --build . --parallel $(nproc)"
fi
echo ""
echo "To rebuild just the apps:"
echo "  ./scripts/build-apps.sh"
echo ""

