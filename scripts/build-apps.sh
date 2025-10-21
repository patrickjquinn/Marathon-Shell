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

# Only reconfigure if CMakeLists.txt changed or build directory is empty
if [ ! -f "CMakeCache.txt" ] || [ "$PROJECT_ROOT/apps/CMakeLists.txt" -nt "CMakeCache.txt" ]; then
    echo "Configuring CMake..."
    
    # Detect OS and set Qt path
    if [[ "$OSTYPE" == "darwin"* ]]; then
        QT_PATH="/opt/homebrew/opt/qt@6"
    else
        QT_PATH="/usr"
    fi
    
    cmake "$PROJECT_ROOT/apps" \
        -G Ninja \
        -DCMAKE_PREFIX_PATH="$QT_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DMARATHON_APPS_DIR="$INSTALL_DIR"
else
    echo "⚡ Skipping CMake configuration (no changes detected)"
fi

echo ""
echo "🔍 Linting QML files..."
find "$PROJECT_ROOT/apps" -name "*.qml" -exec qmllint {} \; 2>/dev/null || {
    echo "⚠️  QML linting found issues (continuing build...)"
}

echo "Building apps..."

# Detect CPU cores for parallel build
if [[ "$OSTYPE" == "darwin"* ]]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=$(nproc)
fi

cmake --build . --parallel $CORES

echo ""
echo "Installing apps to $INSTALL_DIR..."
cmake --install .

# Add warning file to installed apps directory
echo "📝 Adding DO NOT EDIT warning..."
cat > "$INSTALL_DIR/DO_NOT_EDIT_WARNING.txt" << 'EOF'
⚠️  WARNING: DO NOT EDIT APPS IN THIS DIRECTORY! ⚠️

This directory contains INSTALLED COPIES of Marathon apps.
These files are overwritten every time you run ./run.sh or ./scripts/build-apps.sh

TO MAKE CHANGES TO APPS:
========================

1. Edit source files in: /Users/patrick.quinn/Developer/personal/Marathon-Shell/apps/
2. Run: ./run.sh (or ./scripts/build-apps.sh)
3. Changes will be automatically installed to this directory

THESE INSTALLED FILES ARE TEMPORARY COPIES!
Any edits made here will be LOST on the next build.

Source location: /Users/patrick.quinn/Developer/personal/Marathon-Shell/apps/
Build script: /Users/patrick.quinn/Developer/personal/Marathon-Shell/scripts/build-apps.sh
EOF

# Add .do-not-edit marker to each app directory
for app in "$INSTALL_DIR"/*; do
    if [ -d "$app" ] && [ "$(basename "$app")" != "." ]; then
        cat > "$app/.do-not-edit" << 'MARKER'
⚠️  DO NOT EDIT FILES IN THIS DIRECTORY ⚠️

This is an INSTALLED COPY. Changes here will be LOST.
Edit source files in: /Users/patrick.quinn/Developer/personal/Marathon-Shell/apps/
Then run: ./run.sh
MARKER
    fi
done

echo ""
echo "✅ All apps built and installed successfully!"
echo ""
echo "⚠️  WARNING: Apps in $INSTALL_DIR are installed copies!"
echo "   Edit source files in $PROJECT_ROOT/apps/ instead"
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
