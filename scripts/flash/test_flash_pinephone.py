#!/usr/bin/env python3
"""flash-pinephone.sh refuses images without the PinePhone boot layout,
before it touches any device."""
import lzma
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "flash-pinephone.sh"


def image(path: Path, mbr=True, gpt=False, spl=True) -> Path:
    data = bytearray(64 * 1024)
    if mbr:
        data[510:512] = b"\x55\xaa"
    if gpt:
        data[512:520] = b"EFI PART"
    if spl:
        data[8196:8204] = b"eGON.BT0"
    if path.suffix == ".xz":
        path.write_bytes(lzma.compress(bytes(data)))
    else:
        path.write_bytes(bytes(data))
    return path


class FlashPinePhone(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.env = {**os.environ, "MARATHON_BUILD_DIR": str(self.dir / "cache")}

    def tearDown(self):
        self.tmp.cleanup()

    def flash(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *map(str, args)], env=self.env,
                              capture_output=True, text=True, stdin=subprocess.DEVNULL)

    def test_refuses_gpt_image(self):
        run = self.flash(self.dir / "not-a-device", image(self.dir / "gpt.raw.xz", gpt=True))
        self.assertEqual(run.returncode, 1)
        self.assertIn("has a GPT", run.stderr)

    def test_refuses_image_without_spl(self):
        run = self.flash(self.dir / "not-a-device", image(self.dir / "nospl.raw", spl=False))
        self.assertEqual(run.returncode, 1)
        self.assertIn("eGON.BT0", run.stderr)

    def test_refuses_image_without_mbr(self):
        run = self.flash(self.dir / "not-a-device", image(self.dir / "nombr.raw", mbr=False))
        self.assertEqual(run.returncode, 1)
        self.assertIn("MBR", run.stderr)

    def test_good_image_reaches_the_device_check(self):
        run = self.flash(self.dir / "not-a-device", image(self.dir / "good.raw.xz"))
        self.assertEqual(run.returncode, 1)
        self.assertIn("is not a block device", run.stderr)

    def test_defaults_to_newest_whole_disk_image(self):
        out = self.dir / "cache/duranium/mkosi.output/pine64-pinephone_marathon_edge"
        out.mkdir(parents=True)
        old = image(out / "pine64-pinephone_marathon_edge_26101301.raw")
        os.utime(old, (1, 1))
        image(out / "pine64-pinephone_marathon_edge_26101302.raw", spl=False)
        image(out / "pine64-pinephone_marathon_edge_26101303.root-arm64.0123abcd.raw")
        run = self.flash(self.dir / "not-a-device")
        self.assertIn("pine64-pinephone_marathon_edge_26101302.raw has no Allwinner SPL", run.stderr)


if __name__ == "__main__":
    unittest.main()
