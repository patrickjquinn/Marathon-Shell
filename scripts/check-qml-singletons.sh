#!/usr/bin/env bash
set -euo pipefail

# Guardrail: QML singletons must have `pragma Singleton` before any `import` statements.
# Qt requires the pragma to be the first statement in the file (comments/blank lines allowed).
#
# This script fails if it finds a QML file containing `pragma Singleton` where the first
# non-empty, non-comment line is not exactly `pragma Singleton`.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0

while IFS= read -r -d '' file; do
    # Only consider files that claim to be singletons
    if ! grep -q "pragma Singleton" "$file"; then
        continue
    fi

    # Find first non-empty, non-comment line
    first_stmt="$(
        awk '
            {
                line=$0
                sub(/^[ \t]+/, "", line)
                if (line == "") next
                if (line ~ /^\/\//) next
                if (line ~ /^\/\*/) { inblock=1; next }
                if (inblock) {
                    if (line ~ /\*\//) inblock=0
                    next
                }
                print line
                exit
            }
        ' "$file"
    )"

    if [[ "$first_stmt" != "pragma Singleton" ]]; then
        echo "QML singleton pragma must be the first statement: $file"
        echo "  first statement was: ${first_stmt:-<empty>}"
        fail=1
    fi

    # Extra check: pragma must appear before first import
    pragma_line="$(grep -n "pragma Singleton" "$file" | head -n1 | cut -d: -f1 || true)"
    import_line="$(grep -n -E '^[[:space:]]*import[[:space:]]+' "$file" | head -n1 | cut -d: -f1 || true)"
    if [[ -n "${pragma_line}" && -n "${import_line}" && "${pragma_line}" -gt "${import_line}" ]]; then
        echo "QML singleton pragma must appear before imports: $file"
        echo "  pragma line: $pragma_line, first import line: $import_line"
        fail=1
    fi
done < <(find "$ROOT_DIR/shell/qml" -name "*.qml" -print0)

if [[ "$fail" -ne 0 ]]; then
    echo ""
    echo "Fix: move 'pragma Singleton' to the top of the file (before imports)."
    exit 1
fi

echo "✓ QML singleton pragma placement OK"


