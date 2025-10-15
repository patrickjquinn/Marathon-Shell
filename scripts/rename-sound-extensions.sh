#!/bin/bash

# Script to rename .m4a.mp3 files to .mp3 in sound directories

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOUNDS_DIR="$PROJECT_ROOT/shell/resources/sounds"
RESOURCES_FILE="$PROJECT_ROOT/shell/resources.qrc"

echo "Renaming sound files from .m4a.mp3 to .mp3..."
echo "Sounds directory: $SOUNDS_DIR"
echo ""

# Counter for renamed files
count=0

# Find and rename all .m4a.mp3 files
find "$SOUNDS_DIR" -type f -name "*.m4a.mp3" | while read -r file; do
    new_file="${file%.m4a.mp3}.mp3"
    echo "Renaming: $(basename "$file") -> $(basename "$new_file")"
    mv "$file" "$new_file"
    ((count++)) || true
done

echo ""
echo "Files renamed. Now updating resources.qrc..."

# Create backup of resources.qrc
cp "$RESOURCES_FILE" "${RESOURCES_FILE}.bak"
echo "Backup created: ${RESOURCES_FILE}.bak"

# Update resources.qrc - replace .m4a.mp3 with .mp3
sed -i '' 's/\.m4a\.mp3/\.mp3/g' "$RESOURCES_FILE"

echo ""
echo "✅ Done!"
echo "- Sound files renamed"
echo "- resources.qrc updated"
echo "- Backup saved as resources.qrc.bak"

