"""python3 -I test_mtk_gnss_frames.py — synthetic frames only."""
import importlib.machinery
import os
import unittest

tool = importlib.machinery.SourceFileLoader(
    "frames", os.path.join(os.path.dirname(os.path.abspath(__file__)), "mtk-gnss-frames")
).load_module()


def frame(mid, payload):
    body = (len(payload) + 4).to_bytes(2, "little") + mid.to_bytes(2, "little") + payload
    body += (sum(body) & 0xFFFF).to_bytes(2, "little")
    esc = body.replace(b"\xde", b"\xde\xe0").replace(b"\xaa", b"\xde\xdf")
    return b"\xaa\xf0" + esc + b"\xaa\x0f"


class Frames(unittest.TestCase):
    def test_escapes_round_trip(self):
        data = b"\x00\x11" + frame(0xFE2C, bytes([0xAA, 0xDE, 1])) + frame(0xFE32, b"\x01\x00")
        got = [(off, b) for off, b in tool.frames(data)]
        self.assertEqual(len(got), 2)
        self.assertEqual(got[0][1][4:-2], bytes([0xAA, 0xDE, 1]))
        self.assertEqual(int.from_bytes(got[1][1][2:4], "little"), 0xFE32)

    def test_bad_sum_and_truncation(self):
        bad = bytearray(frame(0xFE29, b"\x05" * 8))
        bad[-3] ^= 1
        data = bytes(bad) + b"\xaa\xf0\x05\x00" + frame(0xFE14, b"\x00" * 4)
        got = [b for _, b in tool.frames(data)]
        self.assertEqual(got[0], None)
        self.assertEqual(got[-1][2:4], b"\x14\xfe")

    def test_unscramble(self):
        self.assertEqual(tool.unscramble(bytes([0xCA, 0x42, 0xD8])), bytes([0x00, 0x11, 0x42]))

    def test_capture_records(self):
        raw = frame(0xFE62, bytes(8))
        rec = bytes(16) + len(raw).to_bytes(4, "little") + raw
        self.assertEqual(tool.raw_stream(rec + rec), raw + raw)


if __name__ == "__main__":
    unittest.main()
