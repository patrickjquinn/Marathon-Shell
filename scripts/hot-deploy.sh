#!/usr/bin/env bash
# hot-deploy.sh — iterate on MarathonUI + apps without a full APK/image cycle.
#
# Tar-pipes the disk-imported QML modules (marathon-ui, per-app trees)
# straight into the device's import paths and restarts greetd so the next
# session picks up the new code. ~5 s end-to-end vs ~20 min for the
# build + flash path.
#
# SCOPE — the shell's own QML (shell/qml/) is qt_add_qml_module-embedded
# into the binary as qrc:/qt/qml/MarathonOS/Shell/... resources. A
# file-system rewrite of those resources is NOT picked up by the engine,
# and a URL interceptor that rewrites qrc → file drops the QML module
# context entirely (registered singletons like Constants /
# SettingsManagerCpp / Logger become "not defined", FilteredAppModel
# breaks → empty home grid). Shell QML changes require a binary rebuild
# (--bin) or a full APK cycle. The disk-imported modules below
# (marathon-ui, apps/*) ARE hot-reloadable because they aren't qrc.
#
# rsync isn't shipped on the L5 image so this uses busybox tar instead. The
# trade-off: orphans from deleted files aren't cleaned automatically. Pass
# --wipe to rm -rf the target dir before extracting.
#
# Usage:
#   scripts/hot-deploy.sh                  # tar-push MarathonUI + apps + restart
#   scripts/hot-deploy.sh --bin            # also push the local build/marathon-shell-bin
#   scripts/hot-deploy.sh --no-restart     # push only; keep current session
#   scripts/hot-deploy.sh --wipe           # rm -rf target dirs before extracting
#   scripts/hot-deploy.sh root@10.0.0.42   # override host
#   MARATHON_HOST=... scripts/hot-deploy.sh

set -euo pipefail

PUSH_BIN=0
RESTART=1
WIPE=0
HOST="${MARATHON_HOST:-root@172.16.42.1}"
PASSWORD="${MARATHON_PASSWORD:-marathon}"

for arg in "$@"; do
    case "$arg" in
        --bin)        PUSH_BIN=1 ;;
        --no-restart) RESTART=0 ;;
        --wipe)       WIPE=1 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# *//'
            exit 0
            ;;
        *@*) HOST="$arg" ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)
SSH=(sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "$HOST")

if ! command -v sshpass >/dev/null 2>&1; then
    echo "error: sshpass not on PATH (dnf install sshpass / apt install sshpass)" >&2
    exit 1
fi

# Tar-pipe a source directory into a target directory on the device.
# Args: <local source dir> <remote target dir>
push_tree() {
    local local_dir="$1"
    local remote_dir="$2"
    if [ "$WIPE" = 1 ]; then
        "${SSH[@]}" "rm -rf '$remote_dir' && mkdir -p '$remote_dir'"
    else
        "${SSH[@]}" "mkdir -p '$remote_dir'"
    fi
    tar -cf - -C "$local_dir" . | "${SSH[@]}" "tar -xf - -C '$remote_dir'"
}

echo "==> target: $HOST"
"${SSH[@]}" 'echo "    device: pid=$(pidof marathon-shell-bin) kernel=$(uname -r)"'

# Shell QML (shell/qml/) lives in qrc:/qt/qml/MarathonOS/Shell/... inside
# the binary — not hot-reloadable. Use --bin to push a rebuilt
# marathon-shell-bin, or rebuild the marathon-shell APK for a full cycle.

echo "==> push marathon-ui → /usr/lib/qt6/qml/MarathonUI"
push_tree "$SRC/marathon-ui" /usr/lib/qt6/qml/MarathonUI

echo "==> push apps/* → /usr/share/marathon-apps"
for app_dir in "$SRC"/apps/*/; do
    app="$(basename "$app_dir")"
    [ -d "$app_dir" ] || continue
    push_tree "$app_dir" "/usr/share/marathon-apps/$app" 2>/dev/null || \
        echo "    (skipped $app)"
done

if [ "$PUSH_BIN" = 1 ]; then
    if [ -x "$SRC/build/marathon-shell-bin" ]; then
        echo "==> push freshly-built marathon-shell-bin"
        # scp single-file is fine here — no orphan / mode-bit worries.
        sshpass -p "$PASSWORD" scp "${SSH_OPTS[@]}" \
            "$SRC/build/marathon-shell-bin" \
            "$HOST:/usr/bin/marathon-shell-bin"
    else
        echo "    (skipped: $SRC/build/marathon-shell-bin not present — run cmake --build build first)" >&2
    fi
fi

echo "==> invalidate per-user QML disk cache (.qmlc bytecode keyed on file mtime)"
"${SSH[@]}" 'rm -rf /home/user/.cache/marathon-qml /home/user/.cache/Marathon-Shell /home/user/.cache/QtProject 2>/dev/null || true'

if [ "$RESTART" = 1 ]; then
    echo "==> restart shell (systemctl restart greetd)"
    "${SSH[@]}" 'systemctl restart greetd' || true
    sleep 3
    "${SSH[@]}" 'echo "    new shell pid=$(pidof marathon-shell-bin)"' || true
else
    echo "==> --no-restart: leaving current session running"
fi

echo "done."
