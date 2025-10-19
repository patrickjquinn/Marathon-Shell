#!/bin/bash

# QML Validation Script
# Validates all QML files for syntax errors, import issues, and type mismatches

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔍 QML Validation Report"
echo "========================="

ERRORS=0
WARNINGS=0

# Function to check QML file
check_qml_file() {
    local file="$1"
    local relative_file="${file#$PROJECT_DIR/}"
    
    echo "Checking: $relative_file"
    
    # Check syntax with qmllint
    if ! qmllint "$file" 2>/dev/null; then
        echo "  ❌ Syntax errors found"
        ((ERRORS++))
    else
        echo "  ✅ Syntax OK"
    fi
    
    # Check for common issues
    if grep -q "signal.*Changed()" "$file"; then
        echo "  ⚠️  Potential duplicate signal (property change signals are auto-generated)"
        ((WARNINGS++))
    fi
    
    if grep -q "import.*Process" "$file"; then
        echo "  ❌ Process type doesn't exist in QML"
        ((ERRORS++))
    fi
    
    if grep -q "Qt\.labs\.platform.*Process" "$file"; then
        echo "  ❌ Qt.labs.platform doesn't provide Process"
        ((ERRORS++))
    fi
    
    if grep -q "import.*\./.*" "$file"; then
        echo "  ⚠️  Consider using 'import \"components\"' instead of 'import \"./components\"'"
        ((WARNINGS++))
    fi
}

# Find and check all QML files
echo ""
echo "Checking QML files..."
echo ""

while IFS= read -r -d '' file; do
    check_qml_file "$file"
    echo ""
done < <(find "$PROJECT_DIR/apps" -name "*.qml" -print0)

# Summary
echo "========================="
echo "Validation Summary:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Validation failed with $ERRORS errors"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo ""
    echo "⚠️  Validation passed with $WARNINGS warnings"
    exit 0
else
    echo ""
    echo "✅ All QML files validated successfully"
    exit 0
fi
