#!/usr/bin/env bash
# Finalize the customized image: optional zerofree to compact, then
# xz-compress to out/marathon-hackberry-cm5.img.xz (or leave raw if
# SKIP_COMPRESS / KEEP_DEV).
set -euo pipefail

BUILD_DIR="$1"
SKIP_COMPRESS="${2:-0}"

WORK_IMG="$BUILD_DIR/work.img"
OUT_DIR="$BUILD_DIR/out"
mkdir -p "$OUT_DIR"

case "$SKIP_COMPRESS" in
    1|1*)
        # Dev mode — leave uncompressed for fast dd cycles.
        cp -v "$WORK_IMG" "$OUT_DIR/marathon-hackberry-cm5.img"
        ls -lh "$OUT_DIR/marathon-hackberry-cm5.img"
        ;;
    *)
        echo "  ↳ compressing (xz -3 -T0 for parallel speed)"
        xz -3 -T0 -c "$WORK_IMG" > "$OUT_DIR/marathon-hackberry-cm5.img.xz.tmp"
        mv "$OUT_DIR/marathon-hackberry-cm5.img.xz.tmp" "$OUT_DIR/marathon-hackberry-cm5.img.xz"
        ls -lh "$OUT_DIR/marathon-hackberry-cm5.img.xz"
        ;;
esac
