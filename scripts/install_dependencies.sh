#!/bin/bash
set -e

echo "Installing Marathon Shell dependencies..."

# 1. Install Shared Libraries
echo "Installing libMarathonCore..."
sudo cp -P build/marathon-core/libMarathonCore.so* /usr/local/lib/
sudo ldconfig

echo "Dependencies installed successfully."
