#!/bin/bash
# device-snap LABEL — capture whatever the L5 shell is rendering right now,
# pull it back to host as scratchpad/<label>.png. Requires marathon.local
# reachable + sshpass + root pwd 'marathon'.
#
# Uses SIGUSR1 → ScreenshotService.saveScreenshotTo path (main.cpp:747);
# writes to /tmp/marathon-shot.png on device, then scp's to host.
set -euo pipefail
LABEL="${1:?usage: device-snap <label>}"
OUT_DIR="${MARATHON_SNAP_DIR:-/tmp/claude-1000/-home-patrickquinn-Developer-Marathon-Shell/b5c9540a-ab57-4656-8085-ffa97307f874/scratchpad}"
HOST="${MARATHON_HOST:-marathon.local}"
mkdir -p "$OUT_DIR"
sshpass -p marathon ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR root@"$HOST" '
  PID=$(pgrep -f marathon-shell-bin | head -1)
  rm -f /tmp/marathon-shot.png
  kill -USR1 $PID
  # SIGUSR1 is async: Qt processes it on the next event loop tick, then
  # window->grabWindow() runs on the render thread, then QImage::save
  # writes to disk. Wait until file size is stable across two polls AND
  # ends with the PNG IEND chunk so partial writes never escape.
  prev=-1
  for i in $(seq 1 40); do
    sleep 0.1
    cur=$(stat -c %s /tmp/marathon-shot.png 2>/dev/null || echo 0)
    if [ "$cur" -gt 0 ] && [ "$cur" = "$prev" ]; then
      tail=$(tail -c 4 /tmp/marathon-shot.png 2>/dev/null | od -An -tx1 | tr -d " ")
      [ "$tail" = "ae426082" ] && break  # IEND CRC marker
    fi
    prev=$cur
  done
'
RAW="$OUT_DIR/.$LABEL.raw.png"
sshpass -p marathon scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR root@"$HOST":/tmp/marathon-shot.png "$RAW" 2>/dev/null
# Re-encode via ImageMagick (sRGB, 8-bit RGBA, no esoteric chunks). Qt's
# QImage::save sometimes emits PNGs the Anthropic media decoder rejects;
# magick produces a clean baseline file every time.
magick "$RAW" -strip -define png:color-type=6 "$OUT_DIR/$LABEL.png" 2>/dev/null \
  || convert "$RAW" -strip "$OUT_DIR/$LABEL.png"
rm -f "$RAW"
echo "✓ $OUT_DIR/$LABEL.png ($(stat -c %s "$OUT_DIR/$LABEL.png" 2>/dev/null) B)"
