#!/usr/bin/env bash
# marathon.d/phase4.sh — app-development lifecycle.
#
# Subcommands: app new/run/package/validate/install/watch/registry/permissions
#
# Wraps the existing C++ `marathon-dev` binary (which handles package
# format details) and adds the workflow around it: scaffold from
# template, watch-for-file-change auto-repackage-and-deploy, list what's
# installed on-device, dump manifest permissions.

_marathon_dev_bin() {
    # Prefer local build (fresh code) over system-installed. CMake
    # puts the binary at build/tools/marathon-dev/marathon-dev.
    for candidate in \
        "$MARATHON_SRC/build/tools/marathon-dev/marathon-dev" \
        "$MARATHON_SRC/build/tools/marathon-dev"; do
        if [ -x "$candidate" ] && [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if command -v marathon-dev >/dev/null 2>&1; then
        command -v marathon-dev
        return 0
    fi
    return 1
}

# ── app new NAME ────────────────────────────────────────────────────
cmd_app_new() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon app new <name>"; return 2; }
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        marathon::error "app name must be lowercase-kebab: $name"
        return 2
    fi
    local dev
    dev="$(_marathon_dev_bin)" || {
        marathon::error "marathon-dev binary not found"
        return 1
    }
    marathon::info "scaffold app '$name'"
    "$dev" init "$name"
    marathon::success "app scaffolded at ./$name — edit manifest.json + main.qml"
}

# ── app validate DIR ────────────────────────────────────────────────
cmd_app_validate() {
    local dir="${1:-.}"
    local dev
    dev="$(_marathon_dev_bin)" || { marathon::error "marathon-dev binary not found"; return 1; }
    marathon::info "validate $dir"
    "$dev" validate "$dir"
}

# ── app package [--sign] DIR ───────────────────────────────────────
cmd_app_package() {
    local sign=0
    local dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --sign) sign=1; shift ;;
            *) dir="$1"; shift ;;
        esac
    done
    [ -z "$dir" ] && { marathon::error "usage: marathon app package [--sign] <dir>"; return 2; }
    local dev
    dev="$(_marathon_dev_bin)" || { marathon::error "marathon-dev binary not found"; return 1; }
    marathon::info "package $dir"
    local out
    out="./$(basename "$dir").marathon"
    "$dev" package "$dir" "$out" || return 1
    if [ "$sign" = "1" ]; then
        marathon::step "sign $out"
        "$dev" sign "$out"
    fi
    marathon::success "package: $out"
    echo "$out"
}

# ── app install FILE ────────────────────────────────────────────────
cmd_app_install() {
    local pkg="${1:-}"
    [ -z "$pkg" ] || [ ! -f "$pkg" ] && { marathon::error "usage: marathon app install <package.marathon>"; return 2; }
    marathon::step "push package to device"
    marathon::scp "$pkg" "/tmp/$(basename "$pkg")" >/dev/null
    marathon::step "install on device"
    local dev
    dev="$(_marathon_dev_bin)"
    if [ -n "$dev" ]; then
        # Use device-side marathon-dev if the shipped binary supports install.
        marathon::ssh "marathon-dev install /tmp/$(basename "$pkg") 2>&1" || {
            marathon::error "on-device install failed"
            return 1
        }
    fi
    marathon::success "installed: $pkg"
}

# ── app run [--hot] DIR ─────────────────────────────────────────────
# Package + install + launch. --hot skips re-package if disk state
# unchanged since the last install for the same app.
cmd_app_run() {
    local hot=0
    local dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --hot) hot=1; shift ;;
            *) dir="$1"; shift ;;
        esac
    done
    [ -z "$dir" ] && { marathon::error "usage: marathon app run [--hot] <dir>"; return 2; }
    local manifest="$dir/manifest.json"
    [ ! -f "$manifest" ] && { marathon::error "no manifest.json in $dir"; return 2; }
    local app_id
    app_id="$(python3 -c "import json; print(json.load(open('$manifest'))['id'])" 2>/dev/null)"
    [ -z "$app_id" ] && { marathon::error "manifest.json missing 'id' field"; return 2; }

    marathon::info "run app '$app_id' from $dir (hot=$hot)"

    # Compute checksum of dir to detect changes.
    local sum_file="$MARATHON_SCRATCH/.app-$app_id.sum"
    local now_sum
    now_sum="$(find "$dir" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -exec sha256sum {} + 2>/dev/null | sha256sum | cut -c1-16)"

    local skip_package=0
    if [ "$hot" = "1" ] && [ -f "$sum_file" ]; then
        local prev_sum
        prev_sum="$(cat "$sum_file")"
        [ "$prev_sum" = "$now_sum" ] && skip_package=1
    fi

    local pkg
    if [ "$skip_package" = "1" ]; then
        marathon::debug "no changes since last run, skipping package"
        pkg="$MARATHON_SCRATCH/$app_id.marathon"
    else
        pkg="$(cmd_app_package "$dir" 2>/dev/null | tail -1)"
        [ -f "$pkg" ] || { marathon::error "package failed"; return 1; }
        cp "$pkg" "$MARATHON_SCRATCH/$app_id.marathon"
        pkg="$MARATHON_SCRATCH/$app_id.marathon"
        echo "$now_sum" > "$sum_file"
    fi

    marathon::step "install $pkg"
    cmd_app_install "$pkg" || return 1

    marathon::step "launch $app_id"
    cmd_launch "$app_id" 2>/dev/null || true
}

# ── app watch DIR ───────────────────────────────────────────────────
# inotify loop: on any file change under DIR, auto-repackage + install.
cmd_app_watch() {
    local dir="${1:-.}"
    [ ! -d "$dir" ] && { marathon::error "no such dir: $dir"; return 2; }
    if ! command -v inotifywait >/dev/null 2>&1; then
        marathon::error "inotifywait not installed — 'dnf install inotify-tools'"
        return 1
    fi
    marathon::info "watching $dir — auto app run on changes (Ctrl-C to stop)"
    cmd_app_run --hot "$dir" || true
    while true; do
        inotifywait -r -e modify,create,delete,move --quiet --format '%w%f' "$dir" 2>/dev/null | while read -r file; do
            marathon::step "change: $file"
        done
        sleep 0.5
        cmd_app_run --hot "$dir" || true
    done
}

# ── app registry ───────────────────────────────────────────────────
cmd_app_registry() {
    marathon::ssh 'REG=/home/user/.local/share/marathon-apps
if [ ! -d "$REG" ]; then
    echo "  no apps installed at $REG"
    exit 0
fi
printf "  %-16s %-10s %-8s %s\n" NAME VERSION SIGNED PATH
for app in "$REG"/*/; do
    [ -d "$app" ] || continue
    id=$(basename "$app")
    manifest="$app/manifest.json"
    if [ -f "$manifest" ]; then
        ver=$(python3 -c "import json; print(json.load(open('\''$manifest'\''))[\"version\"])" 2>/dev/null || echo "?")
        signed=$([ -f "$app/.signature" ] && echo "yes" || echo "no")
        printf "  %-16s %-10s %-8s %s\n" "$id" "$ver" "$signed" "$app"
    fi
done
echo
echo "  System apps (baked into image, /usr/share/marathon-apps/):"
for app in /usr/share/marathon-apps/*/; do
    [ -d "$app" ] || continue
    id=$(basename "$app")
    printf "    %s\n" "$id"
done | head -20'
}

# ── app permissions APPID ───────────────────────────────────────────
cmd_app_permissions() {
    local app="${1:-}"
    [ -z "$app" ] && { marathon::error "usage: marathon app permissions <appId>"; return 2; }
    marathon::ssh "for path in /home/user/.local/share/marathon-apps/$app/manifest.json \
                     /usr/share/marathon-apps/$app/manifest.json; do
    if [ -f \"\$path\" ]; then
        echo \"  manifest: \$path\"
        python3 -c 'import json,sys
m = json.load(open(sys.argv[1]))
print(\"  name:        \", m.get(\"name\", \"?\"))
print(\"  version:     \", m.get(\"version\", \"?\"))
print(\"  author:      \", m.get(\"author\", \"?\"))
perms = m.get(\"permissions\", [])
print(\"  permissions:\", perms if perms else \"[]\")
' \"\$path\"
        exit 0
    fi
done
echo \"  no manifest for $app\"
exit 1"
}

# Group dispatch: `app` verb without a subverb prints usage.
cmd_app() {
    marathon::error "usage: marathon app <new|run|package|validate|install|watch|registry|permissions> …"
    return 2
}
