#!/usr/bin/env bash
# Build a bootable Marathon QEMU image (device-qemu-aarch64).
#
# Thin wrapper around scripts/build-image.sh that pins the target
# device. See `build-image.sh --help` for env-var overrides and
# `--boot` / `--verify` flags.
#
# Single-command from a fresh clone:
#   git clone .../Marathon-Shell.git && cd Marathon-Shell
#   ./scripts/build-qemu-image.sh          # build only
#   ./scripts/build-qemu-image.sh --boot   # build + launch QEMU (GL, VNC)
#   ./scripts/build-qemu-image.sh --verify # build + headless mail-verify
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" qemu-aarch64 "$@"
