#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Option-B DSI test frames for tb_bridge.v.

Writes <out>/frames.hex (one 24-bit word {B0,B1,B2} per line, 800 per DSI line,
51 lines per frame) and <out>/meta.hex (one 32-bit word per frame):
  [3:0] scenario  [4] expect drive  [5] expect refuse  [6] expect fault
  [7] expect accept  [15:8] bad-checksum line  [23:16] starved line
  [31:24] short line (0 = none)
"""
import random
import struct
import sys
from pathlib import Path

W, LINES, ROWS, RB = 800, 51, 600, 200
DRIVE, PMIC_ON, VCOM_SET, RESYNC = 1, 2, 4, 8
SCN = {s: i for i, s in enumerate("abcdefghijkl")}


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc


def header(seq, flags, first=0, last=ROWS - 1, vcom=0, bad_crc=False):
    h = b"EPD1" + bytes([1, flags, 0, 0]) + struct.pack("<IHHH", seq, first, last, vcom) + bytes(10)
    return h + struct.pack("<H", crc16(h) ^ bad_crc)


def drive_frame(hdr, data):
    assert len(data) == ROWS * RB
    return hdr.ljust(W * 3, b"\0") + data


def logo_frame():
    return bytes((x * 7 + y) & 0xFF for y in range(LINES) for x in range(W * 3))


def meta(scn, drive=0, refuse=0, fault=0, accept=0, crc_line=0, starve=0, short=0):
    return (SCN[scn] | drive << 4 | refuse << 5 | fault << 6 | accept << 7 |
            crc_line << 8 | starve << 16 | short << 24)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    assert crc16(b"123456789") == 0x6F91
    rng = random.Random(1)
    no11 = [b for b in range(256) if all((b >> s) & 3 != 3 for s in (0, 2, 4, 6))]

    def data(codes=no11):
        return bytes(rng.choices(codes, k=ROWS * RB))

    dv = DRIVE | PMIC_ON
    acc = dict(drive=1, accept=1)
    frames = [
        (logo_frame(), meta("d", refuse=1)),
        (drive_frame(header(50, RESYNC | DRIVE), data()), meta("e", refuse=1)),
        (drive_frame(header(100, RESYNC), data()), meta("c")),
        (drive_frame(header(101, dv, bad_crc=True), data()), meta("c", refuse=1)),
        (drive_frame(header(200, RESYNC), data()), meta("a")),
        (drive_frame(header(201, dv | VCOM_SET, vcom=1750), data()), meta("a", **acc)),
        (drive_frame(header(202, dv), data()), meta("a", **acc)),
        (drive_frame(header(203, dv), data()), meta("a", **acc)),
        (drive_frame(header(204, dv), data()), meta("b", **acc)),
    ]
    frames.append((frames[-1][0], meta("b", refuse=1)))
    frames += [
        (drive_frame(header(300, RESYNC), data()), meta("f")),
        (drive_frame(header(301, dv, 100, 357), data()), meta("f", **acc)),
        (drive_frame(header(302, dv), data()), meta("g", fault=1, crc_line=20, **acc)),
        (drive_frame(header(303, dv), data()), meta("h", fault=1, starve=30, **acc)),
        (drive_frame(header(304, dv), data()), meta("k", fault=1, short=10, **acc)),
        (drive_frame(header(305, dv), data(range(256))), meta("j", **acc)),
        (drive_frame(header(306, DRIVE), data()), meta("l", **acc)),
        (drive_frame(header(307, PMIC_ON), data()), meta("i", accept=1)),
    ]

    with open(out / "frames.hex", "w") as f:
        for fr, _ in frames:
            assert len(fr) == LINES * W * 3
            f.writelines(f"{fr[i]:02x}{fr[i+1]:02x}{fr[i+2]:02x}\n" for i in range(0, len(fr), 3))
    with open(out / "meta.hex", "w") as f:
        f.writelines(f"{m:08x}\n" for _, m in frames)


if __name__ == "__main__":
    main()
