#!/bin/bash
set -e

echo "Installing Marathon Shell dependencies..."

# 1. Install Shared Libraries
echo "Installing libMarathonCore..."
sudo cp -P build/marathon-core/libMarathonCore.so* /usr/local/lib/
sudo ldconfig

# 2. Install QML Modules
echo "Installing MarathonUI modules..."
# Create target directory
sudo mkdir -p /usr/local/lib/qt6/qml/MarathonUI

# Copy MarathonUI modules from build-ui
# We use rsync to copy the contents, excluding intermediate build files if possible, 
# but cp -r is safer to ensure we get everything needed (qmldir, plugins, etc.)
# The build-ui/MarathonUI structure should be:
# build-ui/MarathonUI/Theme/qmldir, lib..., etc.
sudo cp -r build-ui/MarathonUI/* /usr/local/lib/qt6/qml/MarathonUI/

echo "Dependencies installed successfully."
