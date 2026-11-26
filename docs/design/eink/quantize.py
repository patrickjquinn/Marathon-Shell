#!/usr/bin/env python3
"""shell/shaders/eink.frag on a PNG: the offscreen renderer has no GPU for
the shader itself. Grey by Rec. 601 luma, then the panel's 16 levels with a
4x4 ordered dither, or two levels with --binary (the fast waveform).
Usage: quantize.py [--binary] in.png out.png"""
import sys

from PIL import Image


def rank2(x, y):
    return (2 * x + 3 * y) % 4


THRESHOLD = [[(4 * rank2(x % 2, y % 2) + rank2(x // 2, y // 2) + 0.5) / 16
              for x in range(4)] for y in range(4)]


def main():
    args = sys.argv[1:]
    binary = "--binary" in args
    src, dst = [a for a in args if a != "--binary"]
    grey = Image.open(src).convert("RGB").convert("L")
    w, h = grey.size
    px = grey.load()
    for y in range(h):
        row = THRESHOLD[y % 4]
        for x in range(w):
            v = px[x, y] / 255
            t = row[x % 4]
            g = (1.0 if v >= t else 0.0) if binary else int(v * 15 + t) / 15
            px[x, y] = round(g * 255)
    grey.save(dst)


main()
