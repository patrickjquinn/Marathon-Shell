#!/usr/bin/env python3
"""kocmp.py A.ko B.ko

Compare two kernel modules built from the same source in different
directories. ThinLTO names promoted local symbols NAME.llvm.HASH, where HASH
depends on the build path, so .strtab and the build ID differ. Every other
section, and the symbol table with those suffixes removed, must be
identical. Compare copies stripped of debug info: DWARF records the build
path. Exits 1 on any difference.
"""
import re
import struct
import sys


def sections(path):
    data = open(path, "rb").read()
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    hdrs = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    names = hdrs[shstrndx]
    out = {}
    for name, typ, _, _, off, size, link, _, _, entsize in hdrs:
        end = data.index(b"\0", names[4] + name)
        sname = data[names[4] + name:end].decode()
        body = b"" if typ == 8 else data[off:off + size]
        out[sname] = (typ, body, link, entsize)
    return out, hdrs, data


def symbols(secs, hdrs, data):
    typ, body, link, entsize = secs[".symtab"]
    strtab = hdrs[link]
    strs = data[strtab[4]:strtab[4] + strtab[5]]
    syms = []
    for i in range(0, len(body), entsize):
        name, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", body, i)
        n = strs[name:strs.index(b"\0", name)].decode()
        syms.append((re.sub(r"\.llvm\.\d+$", ".llvm", n), info, other, shndx, value, size))
    return syms


def main():
    a, ah, ad = sections(sys.argv[1])
    b, bh, bd = sections(sys.argv[2])
    bad = []
    for name in sorted(set(a) | set(b)):
        if name.startswith((".debug", ".rela.debug")) or name in (
                ".strtab", ".symtab", ".shstrtab", ".note.gnu.build-id"):
            continue
        if a.get(name) != b.get(name):
            bad.append(name)
    if symbols(a, ah, ad) != symbols(b, bh, bd):
        bad.append(".symtab")
    print(("differ: " + " ".join(bad)) if bad else "same code and data")
    sys.exit(1 if bad else 0)


main()
