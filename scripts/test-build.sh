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
echo "Now sync to Marathon-Image and build the package:"
echo ""
echo "  # Repo: https://github.com/MarathonOS/Marathon-Image"
echo "  cd /home/patrickquinn/Developer/Marathon-Image"
echo "  rsync -av --exclude=build --exclude=build-apps \\"
echo "      /home/patrickquinn/Developer/Marathon-Shell/ \\"
echo "      packages/marathon-shell/"
echo "  ./build-marathon.sh"
echo ""

