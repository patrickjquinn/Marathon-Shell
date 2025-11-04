#!/bin/bash
# Script to batch fix all shell components with MarathonUI components

cd /Users/patrick.quinn/Developer/personal/Marathon-Shell/shell/qml/components

# Fix all component files
for file in ui/SettingsListItem.qml PowerMenu.qml AppContextMenu.qml ShareSheet.qml ui/ListPickerModal.qml ui/TextInputModal.qml ui/StorageDetailsModal.qml; do
    if [ -f "$file" ]; then
        echo "Fixing $file..."
        
        # Add MarathonUI imports if not present
        if ! grep -q "import MarathonUI.Theme" "$file"; then
            sed -i '' '/import MarathonOS.Shell/a\
import MarathonUI.Theme
' "$file"
        fi
        
        if ! grep -q "import MarathonUI.Containers" "$file"; then
            sed -i '' '/import MarathonUI.Theme/a\
import MarathonUI.Containers
' "$file"
        fi
        
        if ! grep -q "import MarathonUI.Controls" "$file"; then
            sed -i '' '/import MarathonUI.Containers/a\
import MarathonUI.Controls
' "$file"
        fi
        
        if ! grep -q "import MarathonUI.Core" "$file"; then
            sed -i '' '/import MarathonUI.Controls/a\
import MarathonUI.Core
' "$file"
        fi
        
        # Replace Colors with MColors (but be careful - some might be intentional)
        sed -i '' 's/Colors\.text\b/MColors.textPrimary/g' "$file"
        sed -i '' 's/Colors\.textSecondary\b/MColors.textSecondary/g' "$file"
        sed -i '' 's/Colors\.textTertiary\b/MColors.textTertiary/g' "$file"
        sed -i '' 's/Colors\.accent\b/MColors.marathonTeal/g' "$file"
        sed -i '' 's/Colors\.backgroundDark\b/MColors.background/g' "$file"
        sed -i '' 's/Colors\.surfaceLight\b/MColors.surface/g' "$file"
        sed -i '' 's/Colors\.surfaceDark\b/MColors.elevated/g' "$file"
        
        # Replace Typography with MTypography
        sed -i '' 's/Typography\./MTypography\./g' "$file"
        
        # Replace MarathonToggle with MToggle
        sed -i '' 's/MarathonToggle/MToggle/g' "$file"
        
        echo "  ✓ Fixed $file"
    fi
done

echo "Done fixing shell components!"

