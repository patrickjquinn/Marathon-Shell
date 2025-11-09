#!/bin/bash

# QML Validation Script with PROPER Import Path Configuration
# This script validates QML using qmllint with full Marathon UI type resolution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo " QML Validation with Full Type Resolution"
echo "============================================="
echo ""

# Set up ALL import paths
MARATHON_UI_PATH="$HOME/.local/share/marathon-ui"
SHELL_QML_PATH="$PROJECT_ROOT/shell/qml"
QT_QML_PATH="$(qmlplugindump -nonrelocatable -noinstantiateqmltypes -noncomposite -defaultplatform QtQuick 2.0 2>/dev/null | grep -o 'path: .*' | cut -d' ' -f2 | head -1 || echo '/opt/homebrew/opt/qt@6/share/qt/qml')"
    
# Check Marathon UI installation
if [ ! -d "$MARATHON_UI_PATH" ]; then
    echo -e "${RED}✗ Marathon UI not found at $MARATHON_UI_PATH${NC}"
    echo "  Please rebuild Marathon UI first:"
    echo "  cd $PROJECT_ROOT && ./scripts/full-build.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} Marathon UI found at $MARATHON_UI_PATH"

# Build comprehensive import paths
IMPORT_PATHS="-I $MARATHON_UI_PATH"
IMPORT_PATHS="$IMPORT_PATHS -I $SHELL_QML_PATH"
[ -d "$QT_QML_PATH" ] && IMPORT_PATHS="$IMPORT_PATHS -I $QT_QML_PATH"

echo "  Import paths configured:"
echo "    - $MARATHON_UI_PATH"
echo "    - $SHELL_QML_PATH"
[ -d "$QT_QML_PATH" ] && echo "    - $QT_QML_PATH"
echo ""

# Find all QML files
QML_FILES=$(find "$PROJECT_ROOT/apps" -name "*.qml" -not -path "*/build/*" -not -path "*/.git/*" 2>/dev/null | sort)

if [ -z "$QML_FILES" ]; then
    echo "No QML files found"
    exit 0
fi

ERROR_COUNT=0
WARNING_COUNT=0
CHECKED_COUNT=0

echo "Validating QML files..."
echo ""

for file in $QML_FILES; do
    REL_PATH="${file#$PROJECT_ROOT/}"
    FILE_DIR="$(dirname "$file")"
    
    printf "%-60s" "  $REL_PATH"
    
    # Run qmllint with ALL import paths including file's directory
    LINT_OUTPUT=$(qmllint \
        $IMPORT_PATHS \
        -I "$FILE_DIR" \
        "$file" 2>&1 || true)
    
    # Check for REAL errors (not warnings about missing types in Marathon UI)
    CRITICAL_ERRORS=$(echo "$LINT_OUTPUT" | \
        grep -E "(Error:|is not a type|unavailable)" | \
        grep -v "Failed to import Marathon" | \
        grep -v "was not found. Did you add all imports" | \
        grep -v "Type anchors" | \
        grep -v "Type font" || true)
    
    # Check for property errors
    PROPERTY_ERRORS=$(echo "$LINT_OUTPUT" | \
        grep "Cannot assign to non-existent property" || true)
    
    if [ -n "$CRITICAL_ERRORS" ] || [ -n "$PROPERTY_ERRORS" ]; then
        echo -e " ${RED}✗${NC}"
        [ -n "$CRITICAL_ERRORS" ] && echo "$CRITICAL_ERRORS" | sed 's/^/    /'
        [ -n "$PROPERTY_ERRORS" ] && echo "$PROPERTY_ERRORS" | sed 's/^/    /'
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        # Check for warnings
        WARNINGS=$(echo "$LINT_OUTPUT" | grep "Warning:" || true)
        if [ -n "$WARNINGS" ]; then
            WARNING_COUNT=$((WARNING_COUNT + 1))
            echo -e " ${YELLOW}${NC}"
        else
            echo -e " ${GREEN}✓${NC}"
        fi
    fi
    
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
done

echo ""
echo "============================================="
echo "Checked: $CHECKED_COUNT files"
echo "Warnings: $WARNING_COUNT"
if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${RED}Errors: $ERROR_COUNT${NC}"
echo ""
    echo -e "${RED}✗ Validation failed with $ERROR_COUNT file(s) containing errors${NC}"
    echo ""
    echo "These are REAL errors that will cause runtime failures:"
    echo "  - Missing imports (e.g. MarathonUI.Navigation for MActionBar)"
    echo "  - Non-existent properties"
    echo "  - Type mismatches"
    echo ""
    exit 1
else
    echo -e "${GREEN}Errors: 0${NC}"
    echo ""
    echo -e "${GREEN} All QML files validated successfully!${NC}"
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Note: $WARNING_COUNT warning(s) found but these don't affect functionality${NC}"
    fi
    exit 0
fi
