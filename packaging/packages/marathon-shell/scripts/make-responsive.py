#!/usr/bin/env python3
"""
Automated responsive design refactor script.
Replaces hardcoded pixel values with Constants properties.
"""

import re
import os
import sys
from pathlib import Path

# Mapping of hardcoded values to Constants properties
REPLACEMENTS = {
    # Layout dimensions
    r'\bheight:\s*44\b': 'height: Constants.statusBarHeight',
    r'\bheight:\s*20\b': 'height: Constants.navBarHeight',
    r'\bheight:\s*100\b': 'height: Constants.bottomBarHeight',
    
    # Spacing
    r'\bspacing:\s*5\b': 'spacing: Constants.spacingXSmall',
    r'\bspacing:\s*8\b': 'spacing: Constants.spacingSmall',
    r'\bspacing:\s*10\b': 'spacing: Constants.spacingSmall',
    r'\bspacing:\s*12\b': 'spacing: Constants.spacingMedium',
    r'\bspacing:\s*16\b': 'spacing: Constants.spacingMedium',
    r'\bspacing:\s*20\b': 'spacing: Constants.spacingLarge',
    r'\bspacing:\s*24\b': 'spacing: Constants.spacingXLarge',
    r'\bspacing:\s*32\b': 'spacing: Constants.spacingXLarge',
    r'\bspacing:\s*40\b': 'spacing: Constants.spacingXXLarge',
    
    # Margins
    r'\b(anchors\.\w+Margin):\s*5\b': r'\1: Constants.spacingXSmall',
    r'\b(anchors\.\w+Margin):\s*8\b': r'\1: Constants.spacingSmall',
    r'\b(anchors\.\w+Margin):\s*10\b': r'\1: Constants.spacingSmall',
    r'\b(anchors\.\w+Margin):\s*12\b': r'\1: Constants.spacingMedium',
    r'\b(anchors\.\w+Margin):\s*16\b': r'\1: Constants.spacingMedium',
    r'\b(anchors\.\w+Margin):\s*20\b': r'\1: Constants.spacingLarge',
    r'\b(anchors\.\w+Margin):\s*24\b': r'\1: Constants.spacingXLarge',
    r'\b(anchors\.\w+Margin):\s*32\b': r'\1: Constants.spacingXLarge',
    r'\b(anchors\.\w+Margin):\s*40\b': r'\1: Constants.spacingXXLarge',
    
    # Border radius
    r'\bradius:\s*8\b': 'radius: Constants.borderRadiusSmall',
    r'\bradius:\s*12\b': 'radius: Constants.borderRadiusMedium',
    r'\bradius:\s*16\b': 'radius: Constants.borderRadiusLarge',
    r'\bradius:\s*20\b': 'radius: Constants.borderRadiusXLarge',
    
    # Icon sizes
    r'\bsize:\s*16\b': 'size: Constants.iconSizeSmall',
    r'\bsize:\s*18\b': 'size: Constants.iconSizeSmall',
    r'\bsize:\s*20\b': 'size: Constants.iconSizeSmall',
    r'\bsize:\s*24\b': 'size: Constants.iconSizeMedium',
    r'\bsize:\s*32\b': 'size: Constants.iconSizeMedium',
    r'\bsize:\s*40\b': 'size: Constants.iconSizeLarge',
    r'\bsize:\s*48\b': 'size: Constants.iconSizeXLarge',
    r'\bsize:\s*64\b': 'size: Constants.iconSizeXLarge',
    r'\bsize:\s*72\b': 'size: Constants.appIconSize',
    
    # Font sizes
    r'\bfont\.pixelSize:\s*12\b': 'font.pixelSize: Constants.fontSizeSmall',
    r'\bfont\.pixelSize:\s*14\b': 'font.pixelSize: Constants.fontSizeSmall',
    r'\bfont\.pixelSize:\s*16\b': 'font.pixelSize: Constants.fontSizeMedium',
    r'\bfont\.pixelSize:\s*18\b': 'font.pixelSize: Constants.fontSizeLarge',
    r'\bfont\.pixelSize:\s*20\b': 'font.pixelSize: Constants.fontSizeXLarge',
    r'\bfont\.pixelSize:\s*24\b': 'font.pixelSize: Constants.fontSizeXLarge',
    r'\bfont\.pixelSize:\s*28\b': 'font.pixelSize: Constants.fontSizeXXLarge',
    r'\bfont\.pixelSize:\s*32\b': 'font.pixelSize: Constants.fontSizeXXLarge',
    r'\bfont\.pixelSize:\s*48\b': 'font.pixelSize: Constants.fontSizeHuge',
    
    # Touch targets
    r'\bwidth:\s*90\b': 'width: Constants.touchTargetLarge',
    r'\bheight:\s*90\b': 'height: Constants.touchTargetLarge',
    r'\bwidth:\s*70\b': 'width: Constants.touchTargetMedium',
    r'\bheight:\s*70\b': 'height: Constants.touchTargetMedium',
    r'\bwidth:\s*60\b': 'width: Constants.touchTargetSmall',
    r'\bheight:\s*60\b': 'height: Constants.touchTargetSmall',
    r'\bwidth:\s*50\b': 'width: Constants.touchTargetIndicator',
    r'\bheight:\s*50\b': 'height: Constants.touchTargetIndicator',
    r'\bwidth:\s*45\b': 'width: Constants.touchTargetMinimum',
    r'\bheight:\s*45\b': 'height: Constants.touchTargetMinimum',
    
    # Common sizes
    r'\bwidth:\s*72\b': 'width: Constants.appIconSize',
    r'\bheight:\s*72\b': 'height: Constants.appIconSize',
    r'\bheight:\s*80\b': 'height: Constants.hubHeaderHeight',
}

def process_file(file_path):
    """Process a single QML file and apply replacements."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        changes = 0
        
        for pattern, replacement in REPLACEMENTS.items():
            new_content, count = re.subn(pattern, replacement, content)
            if count > 0:
                content = new_content
                changes += count
        
        if changes > 0:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return changes
        return 0
            
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
        return 0

def main():
    """Main entry point."""
    script_dir = Path(__file__).parent
    qml_dir = script_dir.parent / 'shell' / 'qml'
    
    if not qml_dir.exists():
        print(f"QML directory not found: {qml_dir}", file=sys.stderr)
        return 1
    
    total_files = 0
    total_changes = 0
    
    # Process all QML files recursively
    for qml_file in qml_dir.rglob('*.qml'):
        # Skip Constants.qml itself
        if qml_file.name == 'Constants.qml':
            continue
            
        changes = process_file(qml_file)
        if changes > 0:
            total_files += 1
            total_changes += changes
            print(f"✓ {qml_file.relative_to(qml_dir)}: {changes} replacements")
    
    print(f"\n🎉 Complete! Updated {total_files} files with {total_changes} replacements")
    return 0

if __name__ == '__main__':
    sys.exit(main())

