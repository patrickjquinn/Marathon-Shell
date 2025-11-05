#!/bin/bash
# Build MarathonUI, Marathon Shell AND all apps in one command

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

# Step 1: Build MarathonUI
echo "Step 1/3: Building MarathonUI..."
echo "----------------------------------------"
cd "$PROJECT_ROOT"

BUILD_UI_DIR="$PROJECT_ROOT/build-ui"
INSTALL_UI_DIR="$HOME/.local/share/marathon-ui"

# Check if MarathonUI needs rebuilding
NEEDS_UI_RECONFIGURE=false
if [ ! -d "$BUILD_UI_DIR" ]; then
    echo "Creating MarathonUI build directory..."
    mkdir -p "$BUILD_UI_DIR"
    NEEDS_UI_RECONFIGURE=true
elif [ -f "$BUILD_UI_DIR/CMakeCache.txt" ]; then
    # Check if generator is Ninja
    if ! grep -q "CMAKE_GENERATOR:INTERNAL=Ninja" "$BUILD_UI_DIR/CMakeCache.txt" 2>/dev/null; then
        echo "⚠️  MarathonUI build directory uses wrong generator, reconfiguring..."
        rm -rf "$BUILD_UI_DIR"
        mkdir -p "$BUILD_UI_DIR"
        NEEDS_UI_RECONFIGURE=true
    fi
fi

if [ "$NEEDS_UI_RECONFIGURE" = true ] || [ "$PROJECT_ROOT/marathon-ui/CMakeLists.txt" -nt "$BUILD_UI_DIR/CMakeCache.txt" ]; then
    cd "$BUILD_UI_DIR"
    cmake "$PROJECT_ROOT/marathon-ui" \
        -G Ninja \
        -DCMAKE_PREFIX_PATH="$QT_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local"
    cd ..
fi

cd "$BUILD_UI_DIR"

# Detect CPU cores for parallel build
if [[ "$OSTYPE" == "darwin"* ]]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=$(nproc)
fi

cmake --build . --parallel $CORES
cmake --install .

cd "$PROJECT_ROOT"

echo ""
echo "✅ MarathonUI built and installed successfully!"
echo ""

# Step 2: Build Marathon Shell
echo "Step 2/3: Building Marathon Shell..."
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
        echo "⚠️  Build directory uses wrong generator (not Ninja), reconfiguring..."
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
echo "✅ Marathon Shell built successfully!"
echo ""

# Step 3: Build all Marathon Apps
echo "Step 3/3: Building Marathon Apps..."

# Add QML validation
echo "🔍 Validating QML files..."
find "$PROJECT_ROOT/apps" -name "*.qml" -exec qmllint {} \; 2>/dev/null || {
    echo "⚠️  QML validation found issues (continuing build...)"
}
echo "----------------------------------------"
# Pass any arguments (like "install") to build-apps.sh
"$SCRIPT_DIR/build-apps.sh" "$@"

echo ""
echo "============================================"
echo "✅ Complete Build Successful!"
echo "============================================"
echo ""
echo "To run Marathon Shell:"
echo "  ./build/shell/marathon-shell"
echo ""
echo "To rebuild just MarathonUI:"
echo "  cd build-ui && cmake --build . && cmake --install ."
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

