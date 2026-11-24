#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Link v2 test frames for tb_bridge.v (stock DSI mode, 800x600 RGB888).

Each DSI line is 600 payload words (32-bit, first wire byte in bits 7:0). Only
words 0..57 carry anything (header on line 0, the line's panel row in words
8..57), so <out>/frames.hex holds those 58 words per line, 600 lines per frame;
the testbench pads the rest. <out>/meta.hex has one 48-bit word per frame:
  [3:0] scenario  [4] drive  [5] refuse  [6] fault  [7] accept
  [17:8] bad-checksum line  [27:18] late line  [37:28] short line
  [47:38] line from which the DSI link is lost (0 = none for all four)
"""
import random
import struct
import sys
from pathlib import Path

ROWS, RB, WORDS_KEPT = 600, 200, 58
DRIVE, PMIC_ON, VCOM_SET, RESYNC = 1, 2, 4, 8
SCN = {s: i for i, s in enumerate("abcdefghijklmno")}


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc


def header(seq, flags, first=0, last=ROWS - 1, vcom=0, bad_crc=False):
    h = b"EPD1" + bytes([2, flags, 0, 0]) + struct.pack("<IHHH", seq, first, last, vcom) + bytes(10)
    return h + struct.pack("<H", crc16(h) ^ bad_crc) + bytes(2)


def frame(hdr, rows):
    """Wire bytes 0..231 of each of the 600 lines."""
    assert len(hdr) == 32 and len(rows) == ROWS * RB
    out = bytearray()
    for r in range(ROWS):
        out += (hdr if r == 0 else bytes(32)) + rows[r * RB:(r + 1) * RB]
    return bytes(out)


def logo_frame():
    return bytes((x * 7 + y) & 0xFF for y in range(ROWS) for x in range(WORDS_KEPT * 4))


def meta(scn, drive=0, refuse=0, fault=0, accept=0, crc=0, late=0, short=0, cut=0):
    return (SCN[scn] | drive << 4 | refuse << 5 | fault << 6 | accept << 7 |
            crc << 8 | late << 18 | short << 28 | cut << 38)


def write(out, frames):
    with open(out / "frames.hex", "w") as f:
        for fr, _ in frames:
            assert len(fr) == ROWS * WORDS_KEPT * 4
            for i in range(0, len(fr), 4):
                f.write(f"{int.from_bytes(fr[i:i + 4], 'little'):08x}\n")
    with open(out / "meta.hex", "w") as f:
        f.writelines(f"{m:012x}\n" for _, m in frames)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    assert crc16(b"123456789") == 0x6F91
    rng = random.Random(1)
    no11 = [b for b in range(256) if all((b >> s) & 3 != 3 for s in (0, 2, 4, 6))]

    def data(codes=no11):
        return bytes(rng.choices(codes, k=ROWS * RB))

    dv, pm = DRIVE | PMIC_ON, PMIC_ON
    acc = dict(drive=1, accept=1)
    f = []
    f.append((logo_frame(), meta("d", refuse=1)))
    f.append((frame(header(50, RESYNC | DRIVE | pm), data()), meta("e", refuse=1)))
    f.append((frame(header(100, RESYNC | pm), data()), meta("c", accept=1)))
    f.append((frame(header(101, dv, bad_crc=True), data()), meta("c", refuse=1)))
    f.append((frame(header(200, RESYNC | pm), data()), meta("a", accept=1)))
    f.append((frame(header(201, dv | VCOM_SET, vcom=1750), data()), meta("a", **acc)))
    f.append((frame(header(202, dv), data()), meta("a", **acc)))
    f.append((frame(header(203, dv), data()), meta("a", **acc)))
    f.append((frame(header(204, dv), data()), meta("b", **acc)))
    f.append((f[-1][0], meta("b", refuse=1)))
    f.append((frame(header(250, RESYNC | pm), data()), meta("n", accept=1)))
    f.append((f[-1][0], meta("n", refuse=1)))
    f.append((frame(header(251, dv), data()), meta("n", **acc)))
    f.append((frame(header(252, dv, 100, 357), data()), meta("f", **acc)))
    f.append((frame(header(253, dv), data()), meta("g", fault=1, crc=20, **acc)))
    f.append((frame(header(254, dv), data()), meta("h", late=30, **acc)))
    f.append((frame(header(255, dv), data()), meta("k", fault=1, short=10, **acc)))
    f.append((frame(header(256, dv), data(range(256))), meta("j", **acc)))
    f.append((frame(header(257, DRIVE), data()), meta("l", **acc)))
    f.append((frame(header(258, dv), data()), meta("m", refuse=1)))
    f.append((frame(header(258, pm), data()), meta("m", accept=1)))
    f.append((frame(header(259, dv), data()), meta("m", **acc)))
    f.append((frame(header(260, dv), data()), meta("i", fault=1, cut=300, **acc)))
    f.append((frame(header(300, RESYNC | pm), data()), meta("o", accept=1)))
    f.append((frame(header(301, pm), data()), meta("o", accept=1)))
    black = bytes([0x55]) * (ROWS * RB)
    for s in range(302, 306):
        f.append((frame(header(s, dv), black), meta("o", **acc)))
    f.append((frame(header(306, dv), data()), meta("o", refuse=1)))
    write(out, f)


if __name__ == "__main__":
    main()
