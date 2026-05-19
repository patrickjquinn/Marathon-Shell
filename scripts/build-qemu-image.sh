#!/usr/bin/env bash
# Build a bootable Marathon QEMU image from a fresh Marathon-Shell
# clone.
#
# What this does, top to bottom:
#
#   1. Check host tools (podman, qemu, mkosi, EFI firmware, …) and
#      print install hints per package manager when missing.
#   2. Resolve / clone:
#        Marathon-Image      (APKBUILDs for our packages)
#        postmarketos-duranium (the mkosi image skeleton)
#        mkosi (vendored at a pinned tag)
#      under ~/.cache/marathon-build/ by default. Override the
#      location with MARATHON_BUILD_DIR=/path.
#   3. Build the local apks in dependency order, skipping any
#      already present in mkosi.packages/ (drop the .apk to force a
#      rebuild — there's no checksum comparison yet):
#        qmf (libs + dev + messageserver)         ~ 5–10 min cold
#        marathon-base-config                      ~ 30 s
#        marathon-mail-oauth (Rust)                ~ 1 min
#        marathon-shell                            ~ 2–3 min
#   4. Run mkosi to bake the duranium image. The result lands at:
#        ~/.cache/marathon-build/duranium/mkosi.output/...
#   5. Optionally boot the freshly built image under QEMU and run
#      the verify-mail.sh harness (pass --boot or --verify).
#
# Single-command flow from a fresh clone:
#
#   git clone .../Marathon-Shell.git && cd Marathon-Shell
#   scripts/build-qemu-image.sh        # build only
#   scripts/build-qemu-image.sh --verify  # build, boot, verify
#
# Common overrides (all optional):
#   MARATHON_IMAGE_GIT  upstream repo for Marathon-Image
#   MARATHON_IMAGE_REF  branch / tag (default main)
#   DURANIUM_GIT        upstream repo for postmarketos-duranium
#   DURANIUM_REF        branch / tag (default main)
#   MKOSI_REF           pinned mkosi tag (default v25.3)
#   MARATHON_BUILD_DIR  build-cache root (default ~/.cache/marathon-build)
#   MARATHON_IMAGE_SRC  use existing local Marathon-Image clone
#   FORCE_REBUILD       set to "1" to drop the cached apks before
#                       rebuilding (use after an APKBUILD pkgrel bump).

set -euo pipefail

# Resolve repo root (this script lives at $repo/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MARATHON_SHELL_SRC="$(dirname "$SCRIPT_DIR")"
LIB="$SCRIPT_DIR/qemu/lib"

# CLI parsing — keep it small.
#
#   --boot          (after the bake) launch a GL-accelerated interactive
#                   QEMU. Auto-picks GTK if $DISPLAY/$WAYLAND_DISPLAY are
#                   present, else VNC on 127.0.0.1:5905.
#   --verify        (after the bake) headless boot + run verify-mail.sh.
#                   Exits with verify-mail.sh's return code.
#   --boot-only     SKIP the build/bake stages; boot the already-baked
#                   image. Use for fast iteration after a build.
BOOT=0
BOOT_ONLY=0
VERIFY=0
for a in "$@"; do
    case "$a" in
        --boot)       BOOT=1 ;;
        --verify)     BOOT=1; VERIFY=1 ;;
        --boot-only)  BOOT_ONLY=1; BOOT=1 ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $a (try --help)" >&2; exit 64 ;;
    esac
done

echo "==> stage 1: host prerequisites"
bash "$LIB/check-host.sh"

echo "==> stage 2: dependency trees"
# shellcheck source=qemu/lib/setup-trees.sh
. "$LIB/setup-trees.sh"

# --boot-only short-circuits the build chain — straight to the
# launcher. Useful after a regular build to pop the QEMU window
# again without re-running mkosi.
if [ "$BOOT_ONLY" -eq 1 ]; then
    echo "==> --boot-only: skipping build, baking, and verify"
    exec bash "$LIB/boot-image.sh"
fi

# Helper — only build an apk if no matching file already exists in
# mkosi.packages/ (or FORCE_REBUILD=1). Each builder script writes
# its output via its own MKOSI_PKG_DIR env var that we already
# exported from setup-trees.sh.
build_if_missing() {
    local label="$1" glob="$2" script="$3"
    shift 3
    if [ "${FORCE_REBUILD:-0}" = "1" ]; then
        rm -f "$MKOSI_PKG_DIR"/$glob 2>/dev/null || true
    fi
    if compgen -G "$MKOSI_PKG_DIR/$glob" >/dev/null; then
        echo "==> $label: cached ($(ls -1 "$MKOSI_PKG_DIR"/$glob | tail -1 | xargs -n1 basename))"
        return 0
    fi
    echo "==> $label: building"
    MARATHON_SHELL_SRC="$MARATHON_SHELL_SRC" \
    MARATHON_IMAGE_DIR="$MARATHON_IMAGE_DIR" \
    DURANIUM_DIR="$DURANIUM_DIR" \
    MKOSI_PKG_DIR="$MKOSI_PKG_DIR" \
        bash "$script"
}

echo "==> stage 3: build apks"
build_if_missing "qmf"                       'qmf-libs-*.apk'                  "$LIB/build-qmf-apk.sh"
build_if_missing "marathon-base-config"      'marathon-base-config-*.apk'      "$LIB/build-marathon-base-config-apk.sh"
build_if_missing "marathon-mail-oauth"       'marathon-mail-oauth-*.apk'       "$LIB/build-marathon-mail-oauth-apk.sh"
build_if_missing "marathon-shell"            'marathon-shell-*.apk'            "$LIB/build-marathon-shell-apk.sh"
build_if_missing "postmarketos-ui-marathon"  'postmarketos-ui-marathon-*.apk'  "$LIB/build-postmarketos-ui-marathon-apk.sh"

echo "==> stage 4: bake image"
cd "$DURANIUM_DIR"
PATH="$(dirname "$MKOSI_BIN"):$PATH" \
    python3 scripts/build-image.py device-qemu-aarch64 ui-marathon
LATEST_IMG=$(ls -1t "$DURANIUM_DIR/mkosi.output/qemu-aarch64_marathon_edge"/qemu-aarch64_marathon_edge_*.raw 2>/dev/null \
    | grep -E '/qemu-aarch64_marathon_edge_[0-9]+\.raw$' | head -1)
[ -z "$LATEST_IMG" ] && { echo "no image produced" >&2; exit 1; }
echo "==> image ready: $LATEST_IMG"

if [ "$VERIFY" -eq 1 ]; then
    echo "==> stage 5: boot + verify"
    bash "$LIB/boot-and-verify-mail.sh"
elif [ "$BOOT" -eq 1 ]; then
    echo "==> stage 5: boot (Ctrl-C in this terminal stops QEMU)"
    exec bash "$LIB/boot-image.sh"
else
    echo "==> done. Boot with:"
    echo "    $0 --boot       (interactive shell window — GTK or VNC depending on host display)"
    echo "    $0 --verify     (headless boot + Mail verification harness)"
    echo "    $0 --boot-only  (skip rebuild, just launch QEMU again)"
fi
