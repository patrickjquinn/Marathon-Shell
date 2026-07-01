#!/usr/bin/env bash
# marathon.d/phase7.sh — build pipeline + lint + CI hooks.
#
#   marathon build shell [--fast]      wrap pmbootstrap
#   marathon build image DEVICE        wrap ~/duranium-build build-image.py
#   marathon build apps                package + install every app in ./apps
#   marathon flash DEVICE IMAGE        L5 uuu / Pi5 dd / QEMU boot
#   marathon fmt                       clang-format + qmllint · fail on diff
#   marathon lint                      clang-tidy on staged .cpp files
#   marathon audit                     fmt + lint + qmllint + memory-lint
#   marathon changelog                 generate from commit messages since last tag
#
# shellcheck source=common.sh
# shellcheck disable=SC2154

# ── build shell ─────────────────────────────────────────────────────
cmd_build_shell_verb() { cmd_build_shell "$@"; }

# ── build image ────────────────────────────────────────────────────
cmd_build_image() {
    local device="${1:-}"
    [ -z "$device" ] && { marathon::error "usage: marathon build image <l5|pi5|cm5|qemu>"; return 2; }
    marathon::askpass::ensure || return 1
    local build_script="$HOME/duranium-build/duranium/scripts/build-image.py"
    if [ ! -x "$build_script" ]; then
        marathon::error "duranium build-image.py not found at $build_script"
        return 1
    fi
    case "$device" in
        l5|librem5)   device=purism-librem5 ;;
        pi5)          device=raspberry-pi5 ;;
        cm5|hackberry) device=raspberry-pi5-hackberry ;;
        qemu)         device=qemu ;;
    esac
    marathon::info "build image for $device"
    "$build_script" --device "$device" "${@:2}"
}

# ── build apps ─────────────────────────────────────────────────────
cmd_build_apps() {
    local apps_dir="${MARATHON_SRC}/apps"
    [ ! -d "$apps_dir" ] && { marathon::error "no apps/ dir at $apps_dir"; return 1; }
    for app in "$apps_dir"/*/; do
        [ -f "$app/manifest.json" ] || continue
        local name
        name="$(basename "$app")"
        marathon::step "package $name"
        cmd_app_package "$app" 2>&1 | tail -2 || marathon::warn "$name: package failed"
    done
}

# ── flash ──────────────────────────────────────────────────────────
cmd_flash() {
    local device="${1:-}" image="${2:-}"
    [ -z "$device" ] || [ -z "$image" ] && { marathon::error "usage: marathon flash <l5|cm5|pi5> <image.raw>"; return 2; }
    [ ! -f "$image" ] && { marathon::error "image not found: $image"; return 1; }
    case "$device" in
        l5)  MARATHON_IMAGE_FILE="$image" bash "$MARATHON_SRC/scripts/flash/flash-librem5.sh" ;;
        cm5) MARATHON_IMAGE_FILE="$image" bash "$MARATHON_SRC/scripts/flash/flash-hackberry-cm5.sh" ;;
        pi5) marathon::warn "Pi5: dd $image to your SD card at /dev/sdX"; ;;
        *)   marathon::error "unknown device kind: $device"; return 2 ;;
    esac
}

# ── fmt ────────────────────────────────────────────────────────────
# shellcheck disable=SC2120
cmd_fmt() {
    local fix=0
    case "${1:-}" in --fix) fix=1; shift ;; esac
    marathon::info "clang-format sweep (fix=$fix)"
    local cf_files
    cf_files="$(find "$MARATHON_SRC/shell" "$MARATHON_SRC/tools" -type f \
        \( -name '*.cpp' -o -name '*.h' \) \
        -not -path '*/build/*' -not -path '*/asyncfuture/*')"
    if [ "$fix" = "1" ]; then
        echo "$cf_files" | xargs clang-format -i
        marathon::success "clang-format applied"
    else
        local diff
        diff="$(echo "$cf_files" | xargs clang-format --dry-run --Werror 2>&1)"
        if [ -n "$diff" ]; then
            echo "$diff" | head -30
            marathon::error "clang-format issues — run 'marathon fmt --fix'"
            return 1
        fi
        marathon::success "clang-format: clean"
    fi

    marathon::info "qmllint sweep"
    local qml_issues=0
    while IFS= read -r f; do
        local out
        out="$(qmllint "$f" 2>&1)"
        if [ -n "$out" ]; then
            echo "── $f ──"
            echo "$out"
            qml_issues=$((qml_issues + 1))
        fi
    done < <(find "$MARATHON_SRC/marathon-ui" "$MARATHON_SRC/shell/qml" "$MARATHON_SRC/apps" \
        -name '*.qml' -not -path '*/build/*' 2>/dev/null)
    if [ "$qml_issues" -gt 0 ]; then
        marathon::error "qmllint: $qml_issues files with issues"
        return 1
    fi
    marathon::success "qmllint: clean"
}

# ── lint ───────────────────────────────────────────────────────────
# shellcheck disable=SC2120
cmd_lint() {
    local build_dir="$MARATHON_SRC/build"
    if [ ! -f "$build_dir/compile_commands.json" ]; then
        marathon::error "no compile_commands.json — build with cmake first"
        return 1
    fi
    local files
    if [ $# -gt 0 ]; then
        files="$*"
    else
        files="$(git -C "$MARATHON_SRC" diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.(cpp|h)$')"
        [ -z "$files" ] && files="$(git -C "$MARATHON_SRC" diff --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.(cpp|h)$')"
    fi
    [ -z "$files" ] && { marathon::info "no changed C++ files"; return 0; }
    marathon::info "clang-tidy on: $files"
    local rc=0
    for f in $files; do
        local full="$MARATHON_SRC/$f"
        [ ! -f "$full" ] && continue
        clang-tidy -p "$build_dir" --quiet "$full" 2>&1 | grep -E "warning:|error:" && rc=1
    done
    [ "$rc" = "0" ] && marathon::success "clang-tidy: clean"
    return "$rc"
}

# ── audit ──────────────────────────────────────────────────────────
cmd_audit() {
    marathon::info "audit: fmt + lint + qmllint"
    local rc=0
    cmd_fmt || rc=$?
    cmd_lint || rc=$?
    [ "$rc" = "0" ] && marathon::success "audit: clean"
    return "$rc"
}

# ── changelog ──────────────────────────────────────────────────────
cmd_changelog() {
    local since="${1:-}"
    if [ -z "$since" ]; then
        since="$(git -C "$MARATHON_SRC" describe --tags --abbrev=0 2>/dev/null || echo)"
    fi
    if [ -z "$since" ]; then
        marathon::warn "no tags found — showing last 20 commits"
        git -C "$MARATHON_SRC" log -20 --pretty='  %h  %s'
    else
        marathon::info "commits since $since"
        git -C "$MARATHON_SRC" log "$since"..HEAD --pretty='  %h  %s'
    fi
}
