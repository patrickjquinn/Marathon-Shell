#!/usr/bin/env python3
"""Minimal RFB 3.8 client: connect, request one full raw-encoded
framebuffer update, write a PNG. No third-party deps.

Exists because QMP screendump reads black under egl-headless (the GL
surface never round-trips through QEMU's display pipeline), while QEMU's
VNC server gets a real GL readback. This is the only way to see what the
shell actually renders when hardware GL is on.
"""
import socket, struct, sys, zlib

def png(path, w, h, rgb):
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    raw = b"".join(b"\x00" + rgb[y*w*3:(y+1)*w*3] for y in range(h))
    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b""))

def recvn(s, n):
    b = b""
    while len(b) < n:
        p = s.recv(n - len(b))
        if not p:
            raise IOError("short read")
        b += p
    return b

host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
s = socket.create_connection((host, port), timeout=25); s.settimeout(25)
recvn(s, 12); s.sendall(b"RFB 003.008\n")
n = recvn(s, 1)[0]; recvn(s, n); s.sendall(b"\x01")          # security: None
if struct.unpack(">I", recvn(s, 4))[0] != 0:
    sys.exit("vnc auth failed")
s.sendall(b"\x01")                                            # ClientInit shared
hdr = recvn(s, 24)
w, h = struct.unpack(">HH", hdr[:4])
bpp, depth, big, true = hdr[4], hdr[5], hdr[6], hdr[7]
rmax, gmax, bmax = struct.unpack(">HHH", hdr[8:14])
rsh, gsh, bsh = hdr[14], hdr[15], hdr[16]
# ServerInit is 24 bytes INCLUDING the 4-byte name length at [20:24];
# reading another 4 here hangs waiting for bytes the server never sends.
recvn(s, struct.unpack(">I", hdr[20:24])[0])                   # name
s.sendall(struct.pack(">BBHi", 2, 0, 1, 0))                   # SetEncodings: raw
s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))           # full update
if recvn(s, 1)[0] != 0:
    sys.exit("unexpected msg")
recvn(s, 1)
nrect = struct.unpack(">H", recvn(s, 2))[0]
fb = bytearray(w * h * 3)
Bpp = bpp // 8
for _ in range(nrect):
    rx, ry, rw, rh, enc = struct.unpack(">HHHHi", recvn(s, 12))
    if enc != 0:
        sys.exit(f"non-raw encoding {enc}")
    data = recvn(s, rw * rh * Bpp)
    for y in range(rh):
        for x in range(rw):
            px = data[(y*rw + x)*Bpp:(y*rw + x)*Bpp + Bpp]
            v = int.from_bytes(px, "big" if big else "little")
            r = (v >> rsh) & rmax; g = (v >> gsh) & gmax; b = (v >> bsh) & bmax
            o = ((ry+y)*w + (rx+x)) * 3
            fb[o] = r * 255 // rmax; fb[o+1] = g * 255 // gmax; fb[o+2] = b * 255 // bmax
png(out, w, h, bytes(fb))
print(f"captured {w}x{h} -> {out}")
