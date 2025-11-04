#!/bin/bash
# Script to batch fix all settings pages with MarathonUI components

cd /Users/patrick.quinn/Developer/personal/Marathon-Shell/apps/settings/pages

# Fix all pages that need MarathonUI imports and replacements
for file in WiFiPage.qml BluetoothPage.qml DisplayPage.qml SoundPage.qml NotificationsPage.qml StoragePage.qml CellularPage.qml AboutPage.qml WallpaperPage.qml ScreenTimeoutPage.qml ScalePage.qml SoundPickerPage.qml AppManagerPage.qml; do
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
        
        # Replace Colors with MColors
        sed -i '' 's/Colors\./MColors\./g' "$file"
        
        # Replace Typography with MTypography
        sed -i '' 's/Typography\./MTypography\./g' "$file"
        
        # Replace SettingsListItem with MSettingsListItem
        sed -i '' 's/SettingsListItem/MSettingsListItem/g' "$file"
        
        # Replace MarathonToggle with MToggle
        sed -i '' 's/MarathonToggle/MToggle/g' "$file"
        
        echo "  ✓ Fixed $file"
    fi
done

echo "Done fixing settings pages!"

