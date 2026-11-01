#!/usr/bin/env python3
"""Host-only: derive the MD1-owner candidate DTB from a copy of the accepted DTB.

Edits, and nothing else:
  * replace the four md_mem* reservations with one 128 MiB md1-image node
    covering their exact span [0xdc000000, 0xe4000000), DRDI runtime included;
  * add phandles to ap_md_c_smem, ap_md_nc_smem and the SPM syscon;
  * add the zinwa,q25-md1-owner node under /soc.
The script refuses any input whose SHA256 differs from the accepted DTB and
verifies that every node outside the edit set decompiles identically.
"""
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ACCEPTED = "f668fc23a0ae93ec1d4ab436df7bd051bda9cce30483cda5db1d397294414404"
MD_NODES = ["md_mem@e3200000", "md_mem2@de800000", "md_mem3@ddc00000", "md_mem4@dc000000"]
PH_IMG, PH_C, PH_NC, PH_SPM = 0x1001, 0x1002, 0x1003, 0x1004
INFRACFG_AO_PH = 0x13
CLK_IFRAO_CCIF_AP, CLK_IFRAO_CCIF_MD = 30, 33

OWNER = f"""
		modem@10209000 {{
			compatible = "zinwa,q25-md1-owner";
			reg = <0x00 0x10209000 0x00 0x1000>, <0x00 0x1020a000 0x00 0x1000>;
			reg-names = "ccif-ap", "ccif-md";
			clocks = <{INFRACFG_AO_PH:#x} {CLK_IFRAO_CCIF_AP}>, <{INFRACFG_AO_PH:#x} {CLK_IFRAO_CCIF_MD}>;
			clock-names = "ccif-ap", "ccif-md";
			memory-region = <{PH_IMG:#x}>, <{PH_NC:#x}>, <{PH_C:#x}>;
			memory-region-names = "md-image", "nc-smem", "c-smem";
			mediatek,spm = <{PH_SPM:#x}>;
			mediatek,infracfg-ao = <{INFRACFG_AO_PH:#x}>;
			firmware-name = "q25-md1/md1img.img";
			status = "okay";
		}};
"""

IMG_NODE = f"""		md1-image@dc000000 {{
			reg = <0x00 0xdc000000 0x00 0x8000000>;
			no-map;
			phandle = <{PH_IMG:#x}>;
		}};

"""


def dtc(*args):
    return subprocess.run(["dtc", "-q", *args], check=True, capture_output=True).stdout


def node_span(text, name):
    m = re.search(r"^(\t+)" + re.escape(name) + r" \{\n", text, re.M)
    if not m:
        raise SystemExit(f"node {name} not found")
    end = text.index("\n" + m.group(1) + "};\n", m.end()) + len(m.group(1)) + 4
    return m.start(), end


def add_phandle(text, name, ph):
    s, e = node_span(text, name)
    block = text[s:e]
    if "phandle" in block.split("{", 1)[1].split("\n\t\t\t", 1)[0]:
        raise SystemExit(f"{name} already has a phandle")
    indent = re.match(r"\t+", block).group(0) + "\t"
    first = block.index("{\n") + 2
    block = block[:first] + f"{indent}phandle = <{ph:#x}>;\n" + block[first:]
    return text[:s] + block + text[e:]


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-md1-dtb.py <accepted.dtb copy> <out.dtb>")
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    if src.is_symlink() or not src.is_file():
        raise SystemExit("input must be a regular file")
    data = src.read_bytes()
    if hashlib.sha256(data).hexdigest() != ACCEPTED:
        raise SystemExit("input is not the accepted f668 DTB")
    if out.exists():
        raise SystemExit("refusing to overwrite output")
    with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent.parent / "tmp") as td:
        base = dtc("-I", "dtb", "-O", "dts", str(src)).decode()
        if re.search(r"phandle = <0x100[1-4]>", base):
            raise SystemExit("phandle collision")
        text = base
        for n in MD_NODES:
            s, e = node_span(text, n)
            e += 1 if text[e:e + 1] == "\n" else 0
            text = text[:s] + text[e:]
        s, _ = node_span(text, "ccci_tag@bf9f0000")
        text = text[:s] + IMG_NODE + text[s:]
        text = add_phandle(text, "ap_md_c_smem@8c000000", PH_C)
        text = add_phandle(text, "ap_md_nc_smem@8e000000", PH_NC)
        text = add_phandle(text, "syscon@10006000", PH_SPM)
        s, e = node_span(text, "soc")
        close = text.rindex("\n\t};\n", s, e) + 1
        text = text[:close] + OWNER + text[close:]
        dts = Path(td) / "cand.dts"
        dts.write_text(text)
        blob = dtc("-I", "dts", "-O", "dtb", str(dts))
        tmpdtb = Path(td) / "cand.dtb"
        tmpdtb.write_bytes(blob)
        cand = dtc("-I", "dtb", "-O", "dts", str(tmpdtb)).decode()

    def strip(t):
        for n in MD_NODES + ["md1-image@dc000000", "modem@10209000"]:
            if re.search(r"^\t+" + re.escape(n) + r" \{", t, re.M):
                s, e = node_span(t, n)
                t = t[:s] + t[e:]
        return re.sub(r"\n\t+phandle = <0x100[1-4]>;", "", re.sub(r"\n\s*\n", "\n", t))

    if strip(base) != strip(cand):
        raise SystemExit("unexpected difference outside the edit set")
    out.write_bytes(blob)
    print(f"{out} sha256={hashlib.sha256(blob).hexdigest()} bytes={len(blob)}")


if __name__ == "__main__":
    main()
