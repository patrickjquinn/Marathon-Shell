#!/usr/bin/env python3
"""Host-only: build q25-modem.dtbo and a merged DTB from a copy of the current DTB.

Refuses a base whose SHA256 differs from the current accepted base, or whose
raw phandles 0x12/0x13 are not topckgen/infracfg_ao, or whose GIC is not
4-cell. Verifies the merged result: every pre-existing node is unchanged
except ap_md_nc_smem's reg; the new nodes are present.
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

BASE_SHA = "edc93beb71205271a9ab20bce92b9f892864f4c29a06ca7d4d1c4716b4f49e8a"
HERE = Path(__file__).resolve().parent
KINC = Path(os.environ["KSRC"]) / "include"  # the prepared kernel tree
NEW = ["md_attr_node", "md1-owner", "md_power_o1@10006000", "infracfg_ao_ccci@10001000",
       "mddriver", "ccifdriver@10209000", "dpmaif@10014000"]


def run(*a, **kw):
    return subprocess.run(a, check=True, capture_output=True, **kw).stdout


def get(dtb, node, prop, t="s"):
    return run("fdtget", "-t", t, str(dtb), node, prop).decode().strip()


def node_by_phandle(dts, ph):
    m = re.search(r"\n(\t+)([^\n{]+) \{\n(?:\1\t[^\n]*\n)*?\1\tphandle = <%s>;" % hex(ph), dts)
    return m.group(2) if m else None


def strip(dts):
    for n in NEW:
        m = re.search(r"^(\t+)" + re.escape(n) + r" \{\n", dts, re.M)
        if m:
            end = dts.index("\n" + m.group(1) + "};\n", m.end()) + len(m.group(1)) + 4
            dts = dts[:m.start()] + dts[end:]
    dts = re.sub(r"(ap_md_nc_smem@8e000000 \{\n\t+reg = <)[^>]*>", r"\1X>", dts)
    dts = re.sub(r"\n\t+phandle = <0x[0-9a-f]+>;", "", dts)
    dts = re.sub(r"\n\t*__(symbols|fixups|local_fixups)__ \{.*?\n\t*\};", "", dts, flags=re.S)
    return re.sub(r"\n\s*\n", "\n", dts)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-modem-dtbo.py <copy of current dtb> <outdir>")
    base, outdir = Path(sys.argv[1]), Path(sys.argv[2])
    if base.is_symlink() or hashlib.sha256(base.read_bytes()).hexdigest() != BASE_SHA:
        raise SystemExit("base is not the current q25-native-input-audio-sensors-connsys-btif-nobl.dtb")
    outdir.mkdir(exist_ok=True)
    dts = run("dtc", "-q", "-I", "dtb", "-O", "dts", str(base)).decode()
    if "mediatek,mt6789-infracfg_ao" not in get(base, "/soc/syscon@10001000", "compatible") \
            or get(base, "/soc/syscon@10001000", "phandle", "x") != "13":
        raise SystemExit("phandle 0x13 is not infracfg_ao")
    if get(base, "/soc/clock-controller@10000000", "phandle", "x") != "12":
        raise SystemExit("phandle 0x12 is not topckgen")
    if get(base, "/soc/interrupt-controller@c000000", "#interrupt-cells", "u") != "4":
        raise SystemExit("unexpected GIC cell count")
    for n in NEW:
        if re.search(r"\b" + re.escape(n) + r" \{", dts):
            raise SystemExit(f"{n} already present in base")
    with tempfile.TemporaryDirectory(dir=HERE.parent / "tmp") as td:
        pre = Path(td) / "ov.dts"
        pre.write_bytes(run("cpp", "-nostdinc", "-undef", "-x", "assembler-with-cpp", "-P",
                            "-I", str(KINC), str(HERE / "q25-modem.dtso")))
        dtbo = outdir / "q25-modem.dtbo"
        run("dtc", "-q", "-@", "-I", "dts", "-O", "dtb", "-o", str(dtbo), str(pre))
        merged = outdir / "q25-native-input-audio-sensors-connsys-btif-nobl-modem.dtb"
        run("fdtoverlay", "-i", str(base), "-o", str(merged), str(dtbo))
    mdts = run("dtc", "-q", "-I", "dtb", "-O", "dts", str(merged)).decode()
    if strip(dts) != strip(mdts):
        raise SystemExit("unexpected difference outside the overlay set")
    if get(merged, "/reserved-memory/ap_md_nc_smem@8e000000", "reg", "x").split()[-1] != "e10000":
        raise SystemExit("nc smem resize missing")
    owner_ph = get(merged, "/soc/md1-owner", "phandle", "x")
    if get(merged, "/soc/mddriver", "power-domains", "x") != owner_ph:
        raise SystemExit("mddriver power-domains does not point at md1-owner")
    for f in (dtbo, merged):
        print(f"{f} sha256={hashlib.sha256(f.read_bytes()).hexdigest()} bytes={f.stat().st_size}")


if __name__ == "__main__":
    main()
