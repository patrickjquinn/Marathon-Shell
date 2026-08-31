#!/bin/bash
# Quick build script for testing Marathon Shell changes
# Does NOT install locally, just builds for deployment

set -e

echo " Building Marathon Shell..."

# Build main shell
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

cmake --build build

echo " Shell built successfully"

# Build apps
cmake -B build-apps -S apps -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

cmake --build build-apps

echo " Apps built successfully"

echo ""
echo " Build complete!"
echo "Package the result with:"
echo ""
echo "  ./scripts/qemu/lib/build-marathon-shell-apk.sh"
echo ""
echo "The aport lives in-tree at packaging/packages/marathon-shell/;"
echo "no sync step is needed."
echo ""

