#!/usr/bin/env bash
# Mechanical enforcement for the rules in docs/CODING_RULES.md sections B & C.
#
# Runs:
#   - qmllint over shell/qml, marathon-ui, apps/*/qml
#   - clazy-standalone (if installed) over compile_commands.json
#   - clang-tidy (always; we have it) with a Qt-aware check set
#
# Exits non-zero on warnings so CI / pre-push hooks can gate on it. Sources
# from docs/CODING_RULES.md: B1-B15 (C++/Qt), C1-C14 (QML). The checks below
# are the subset clazy / qmllint / clang-tidy can express today; review the
# unenforced rest by hand.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_DIR="${BUILD_DIR:-build}"
COMPDB="$BUILD_DIR/compile_commands.json"

errors=0

# ─ QML ──────────────────────────────────────────────────────────────────────

QMLLINT="$(command -v qmllint-qt6 || command -v qmllint || true)"
if [ -z "$QMLLINT" ]; then
    echo "[lint] qmllint not installed -- QML checks skipped" >&2
    errors=1
else
    echo "[lint] qmllint via $QMLLINT"
    QML_FILES=()
    while IFS= read -r -d '' f; do QML_FILES+=("$f"); done < <(
        find shell/qml apps marathon-ui -name '*.qml' -not -path '*/build*/*' -print0 2>/dev/null)
    if [ "${#QML_FILES[@]}" -gt 0 ]; then
        # Enabled levels: errors fail, warnings reported. Plugin-based
        # checks (binding loops, unqualified access) are on by default.
        "$QMLLINT" \
            --compiler=warning \
            --unqualified=warning \
            --unused-imports=warning \
            --deferred-property-id=warning \
            "${QML_FILES[@]}"
        if [ $? -ne 0 ]; then
            errors=1
        fi
    fi
fi

# ─ C++ / Qt ──────────────────────────────────────────────────────────────────

if [ ! -f "$COMPDB" ]; then
    echo "[lint] $COMPDB not found -- run cmake -B $BUILD_DIR first" >&2
    exit 1
fi

# Only lint our own source. Skip generated, build, third-party, asyncfuture.
filter_sources() {
    jq -r '.[].file' "$COMPDB" |
        grep -E "/(shell|marathon-core|marathon-ui|tools/marathon-app-runner)/" |
        grep -vE "/(build|third-party|\.qt|\.rcc|autogen|qmltyperegistrations|_qmlcache)" |
        grep -E '\.(cpp|cc)$'
}

mapfile -t SOURCES < <(filter_sources)
echo "[lint] ${#SOURCES[@]} C++ sources to check"

CLAZY="$(command -v clazy-standalone || true)"
if [ -n "$CLAZY" ]; then
    echo "[lint] clazy-standalone via $CLAZY"
    "$CLAZY" -p "$BUILD_DIR" \
        -checks=level0,level1,no-overloaded-signal,no-non-pod-global-static \
        "${SOURCES[@]}" 2>&1 || errors=1
else
    echo "[lint] clazy-standalone not installed -- skipping (install: apt install clazy)" >&2
fi

CLANG_TIDY="$(command -v clang-tidy || true)"
if [ -n "$CLANG_TIDY" ]; then
    echo "[lint] clang-tidy via $CLANG_TIDY"
    # Qt-friendly subset. Excludes style nits we don't enforce, and the
    # noisy ones (modernize-use-trailing-return-type, fuchsia-*).
    CHECKS='bugprone-*,clang-analyzer-*,cppcoreguidelines-pro-type-cstyle-cast,'\
'cppcoreguidelines-slicing,misc-const-correctness,misc-unused-using-decls,'\
'modernize-use-nullptr,modernize-use-override,performance-*,readability-redundant-member-init,'\
'-bugprone-easily-swappable-parameters,-bugprone-unchecked-optional-access,'\
'-bugprone-narrowing-conversions,-performance-no-int-to-ptr,'\
'-clang-analyzer-cplusplus.NewDeleteLeaks'
    "$CLANG_TIDY" -p "$BUILD_DIR" --quiet --checks="$CHECKS" "${SOURCES[@]}" 2>&1 ||
        errors=1
else
    echo "[lint] clang-tidy not installed -- skipping" >&2
fi

if [ "$errors" -ne 0 ]; then
    echo "[lint] FAIL"
    exit 1
fi
echo "[lint] OK"
