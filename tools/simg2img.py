#!/usr/bin/env python3
"""
Minimal Android sparse image -> raw image converter (simg2img replacement).

This is useful for inspecting pmbootstrap-exported userdata/rootfs images, which
are often Android sparse images.

Format reference:
- AOSP libsparse (sparse_format.h)
"""

from __future__ import annotations

import argparse
import os
import struct
import sys


SPARSE_HEADER_MAGIC = 0xED26FF3A

CHUNK_TYPE_RAW = 0xCAC1
CHUNK_TYPE_FILL = 0xCAC2
CHUNK_TYPE_DONT_CARE = 0xCAC3
CHUNK_TYPE_CRC32 = 0xCAC4


def _read_exact(f, n: int) -> bytes:
    b = f.read(n)
    if len(b) != n:
        raise EOFError(f"Unexpected EOF (wanted {n} bytes, got {len(b)})")
    return b


def convert(sparse_path: str, raw_path: str) -> None:
    with open(sparse_path, "rb") as fin:
        hdr = _read_exact(fin, 28)
        (
            magic,
            major,
            minor,
            file_hdr_sz,
            chunk_hdr_sz,
            blk_sz,
            total_blks,
            total_chunks,
            _checksum,
        ) = struct.unpack("<IHHHHIIII", hdr)

        if magic != SPARSE_HEADER_MAGIC:
            raise ValueError(f"Not an Android sparse image (bad magic {magic:#x})")
        if major != 1:
            raise ValueError(f"Unsupported sparse version {major}.{minor}")
        if file_hdr_sz < 28:
            raise ValueError(f"Invalid file header size: {file_hdr_sz}")
        if chunk_hdr_sz < 12:
            raise ValueError(f"Invalid chunk header size: {chunk_hdr_sz}")

        # Skip any extra file header bytes.
        if file_hdr_sz > 28:
            _read_exact(fin, file_hdr_sz - 28)

        out_size = total_blks * blk_sz
        os.makedirs(os.path.dirname(os.path.abspath(raw_path)) or ".", exist_ok=True)

        with open(raw_path, "wb") as fout:
            written = 0

            for _ in range(total_chunks):
                ch = _read_exact(fin, chunk_hdr_sz)
                chunk_type, _reserved, chunk_sz, total_sz = struct.unpack("<HHII", ch[:12])

                # Skip any extra chunk header bytes.
                if chunk_hdr_sz > 12:
                    extra = chunk_hdr_sz - 12
                    _read_exact(fin, extra)

                out_bytes = chunk_sz * blk_sz

                if chunk_type == CHUNK_TYPE_RAW:
                    data_sz = total_sz - chunk_hdr_sz
                    if data_sz != out_bytes:
                        raise ValueError(
                            f"RAW chunk size mismatch: data_sz={data_sz} expected={out_bytes}"
                        )
                    fout.write(_read_exact(fin, data_sz))
                    written += out_bytes

                elif chunk_type == CHUNK_TYPE_FILL:
                    # total_sz = chunk_hdr_sz + 4
                    fill = _read_exact(fin, 4)
                    if total_sz < chunk_hdr_sz + 4:
                        raise ValueError("FILL chunk too small")
                    # If total_sz > chunk_hdr_sz + 4, skip remaining.
                    if total_sz > chunk_hdr_sz + 4:
                        _read_exact(fin, total_sz - (chunk_hdr_sz + 4))

                    # Build one block of fill data.
                    # fill is a 32-bit little-end value repeated.
                    block = fill * (blk_sz // 4) + fill[: (blk_sz % 4)]
                    for _i in range(chunk_sz):
                        fout.write(block)
                    written += out_bytes

                elif chunk_type == CHUNK_TYPE_DONT_CARE:
                    # total_sz = chunk_hdr_sz
                    if total_sz > chunk_hdr_sz:
                        _read_exact(fin, total_sz - chunk_hdr_sz)
                    # represent "don't care" as zeroes in raw output
                    # (sufficient for filesystem inspection).
                    fout.write(b"\x00" * out_bytes)
                    written += out_bytes

                elif chunk_type == CHUNK_TYPE_CRC32:
                    # total_sz = chunk_hdr_sz + 4
                    # No output produced.
                    if total_sz > chunk_hdr_sz:
                        _read_exact(fin, total_sz - chunk_hdr_sz)

                else:
                    raise ValueError(f"Unknown chunk type: {chunk_type:#x}")

            fout.flush()
            if written != out_size:
                raise ValueError(f"Output size mismatch: written={written} expected={out_size}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sparse_img", help="Input Android sparse image (.img)")
    ap.add_argument("raw_img", help="Output raw image path")
    args = ap.parse_args()

    convert(args.sparse_img, args.raw_img)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



