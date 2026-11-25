#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Turn `epd-tool vectors DIR` output (link v2 frames from the real engine, one
$readmemh file of 800x600 24-bit pixels each, listed in frames.txt) into the
frames.hex/meta.hex pair tb_bridge.v reads. Expectations come from frames.txt:
resync and drain are accepted without drive, a drive with rows drives them.

  engine_vectors.py IN_DIR OUT_DIR
"""
import sys
from pathlib import Path

W, ROWS, WORDS_KEPT = 800, 600, 58


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    frames, metas = [], []
    for entry in (src / "frames.txt").read_text().splitlines():
        name, what = entry.split(" ", 1)
        px = (src / name).read_text().split()
        assert len(px) == W * ROWS, f"{name}: {len(px)} pixels"
        wire = b"".join(bytes.fromhex(p) for p in px)
        for line in range(ROWS):
            frames.append(wire[line * W * 3:line * W * 3 + WORDS_KEPT * 4])
        drive = what.startswith("drive") and "None" not in what
        metas.append((1 << 4 | 1 << 7) if drive else 1 << 7)
    with open(out / "frames.hex", "w") as f:
        for line in frames:
            for i in range(0, len(line), 4):
                f.write(f"{int.from_bytes(line[i:i + 4], 'little'):08x}\n")
    with open(out / "meta.hex", "w") as f:
        f.writelines(f"{m:012x}\n" for m in metas)
    print(f"{len(metas)} frames, {sum(m >> 4 & 1 for m in metas)} driving")


if __name__ == "__main__":
    main()
