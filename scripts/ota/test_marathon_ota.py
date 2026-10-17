"""marathon-ota publishes a feed systemd-sysupdate can verify and consume."""

import functools
import hashlib
import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "marathon-ota"
TRANSFERS = Path(__file__).resolve().parents[2] / "packaging" / "ota" / "sysupdate.d"
SYSUPDATE = Path("/usr/lib/systemd/systemd-sysupdate")
IMAGE_ID = "qemu-aarch64_marathon_edge"
UUID_A = "0123456789abcdef0123456789abcdef"
UUID_B = "fedcba9876543210fedcba9876543210"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


@unittest.skipUnless(shutil.which("gpg") and shutil.which("gpgv") and shutil.which("zstd"),
                     "needs gpg, gpgv and zstd")
class FeedCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.gnupg = cls.tmp / "gnupg"
        cls.pubkey = cls.tmp / "marathon-ota.asc"
        cls.run_tool("keygen", "--gnupghome", cls.gnupg, "--export", cls.pubkey)
        # What mkosi.finalize installs as /usr/lib/systemd/import-pubring.pgp.
        cls.keyring = cls.tmp / "import-pubring.pgp"
        with open(cls.pubkey, "rb") as armored, open(cls.keyring, "wb") as out:
            subprocess.run(["gpg", "--dearmor"], stdin=armored, stdout=out, check=True)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", str(cls.gnupg), "--kill", "all"],
                       stderr=subprocess.DEVNULL, check=False)
        shutil.rmtree(cls.tmp)

    @staticmethod
    def run_tool(*args, check=True):
        return subprocess.run([sys.executable, str(TOOL), *map(str, args)],
                              capture_output=True, text=True, check=check)

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.tmp))
        self.image_dir = self.case / IMAGE_ID
        self.image_dir.mkdir()
        self.feed = self.case / "feed"

    def build(self, version, uuid=UUID_A, payload=b"usr"):
        stem = f"{IMAGE_ID}_{version}"
        (self.image_dir / f"{stem}.efi").write_bytes(b"MZ" + version.encode())
        (self.image_dir / f"{stem}.usr-arm64.{uuid}.raw").write_bytes(payload * 4096 + b"\0" * 65536)
        (self.image_dir / f"{stem}.usr-arm64-verity.{uuid}.raw").write_bytes(b"verity" + version.encode())
        # Splits that are not part of an update.
        (self.image_dir / f"{stem}.esp.raw").write_bytes(b"esp")
        (self.image_dir / f"{stem}.raw").write_bytes(b"disk")

    def publish(self, version, *extra, check=True):
        return self.run_tool("publish", "--image-dir", self.image_dir, "--version", version,
                             "--feed", self.feed, "--gnupghome", self.gnupg, *extra, check=check)

    @property
    def out(self):
        return self.feed / IMAGE_ID



class PublishTest(FeedCase):
    def manifest(self):
        entries = {}
        for line in (self.out / "SHA256SUMS").read_text().splitlines():
            digest, name = line.split("  ", 1)
            entries[name] = digest
        return entries

    def test_feed_holds_compressed_partitions_and_the_uki(self):
        self.build("26101701")
        self.publish("26101701")
        stem = f"{IMAGE_ID}_26101701"
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), sorted([
            "SHA256SUMS", "SHA256SUMS.gpg", "marathon-os.metainfo.xml",
            f"{stem}.efi",
            f"{stem}.usr-arm64.{UUID_A}.raw.zst",
            f"{stem}.usr-arm64-verity.{UUID_A}.raw.zst",
        ]))
        restored = subprocess.run(["zstd", "-dc", str(self.out / f"{stem}.usr-arm64.{UUID_A}.raw.zst")],
                                  capture_output=True, check=True).stdout
        self.assertEqual(restored, (self.image_dir / f"{stem}.usr-arm64.{UUID_A}.raw").read_bytes())

    def test_manifest_lists_every_file_with_its_hash(self):
        self.build("26101701")
        self.publish("26101701")
        entries = self.manifest()
        self.assertEqual(set(entries), {p.name for p in self.out.iterdir()} - {"SHA256SUMS", "SHA256SUMS.gpg"})
        for name, digest in entries.items():
            self.assertEqual(digest, hashlib.sha256((self.out / name).read_bytes()).hexdigest(), name)

    def test_signature_verifies_against_the_image_keyring(self):
        self.build("26101701")
        self.publish("26101701")
        verify = ["gpgv", "--keyring", str(self.keyring), str(self.out / "SHA256SUMS.gpg"),
                  str(self.out / "SHA256SUMS")]
        subprocess.run(verify, capture_output=True, check=True)
        with open(self.out / "SHA256SUMS", "a") as f:
            f.write("0" * 64 + "  evil.efi\n")
        self.assertNotEqual(subprocess.run(verify, capture_output=True).returncode, 0)

    def test_catalog_carries_size_and_notes_per_release(self):
        self.build("26101701")
        self.publish("26101701")
        self.build("26101801", UUID_B, b"usr2")
        notes = self.case / "notes.txt"
        notes.write_text("Faster boot & <shell>\n\nFixes Wi-Fi\n")
        self.publish("26101801", "--notes", notes)
        root = ET.parse(self.out / "marathon-os.metainfo.xml").getroot()
        component = root.find("component")
        self.assertIsNotNone(component.find("bundle[@type='systemd'][@class='sysupdate']"))
        releases = {r.get("version"): r for r in component.iter("release")}
        self.assertEqual(list(releases), ["26101801", "26101701"])
        new = releases["26101801"]
        self.assertEqual([p.text for p in new.iter("p")], ["Faster boot & <shell>", "Fixes Wi-Fi"])
        payload = [p for p in self.out.iterdir() if p.name.startswith(f"{IMAGE_ID}_26101801.")
                   and not p.name.endswith(".notes")]
        self.assertEqual(int(new.find("artifacts/artifact/size[@type='download']").text),
                         sum(p.stat().st_size for p in payload))
        self.assertIsNone(releases["26101701"].find("description"))

    def test_keeps_the_newest_versions(self):
        for i, version in enumerate(["26101701", "26101801", "26101901"]):
            self.build(version, f"{i:032x}")
            self.publish(version)
        names = {p.name for p in self.out.iterdir()}
        self.assertFalse(any("26101701" in n for n in names), names)
        self.assertIn(f"{IMAGE_ID}_26101901.efi", names)
        self.assertIn(f"{IMAGE_ID}_26101801.efi", names)
        self.assertFalse(any("26101701" in n for n in self.manifest()))

    def test_refuses_republishing_or_going_backwards(self):
        self.build("26101801")
        self.publish("26101801")
        again = self.publish("26101801", check=False)
        self.assertNotEqual(again.returncode, 0)
        self.assertIn("already in the feed", again.stderr)
        self.build("26101701", UUID_B)
        older = self.publish("26101701", check=False)
        self.assertNotEqual(older.returncode, 0)
        self.assertIn("older than", older.stderr)

    def test_refuses_a_single_partition_image(self):
        stem = f"{IMAGE_ID}_26101701"
        (self.image_dir / f"{stem}.efi").write_bytes(b"MZ")
        (self.image_dir / f"{stem}.root-arm64.{UUID_A}.raw").write_bytes(b"root")
        result = self.publish("26101701", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MARATHON_IMAGE_LAYOUT=ab", result.stderr)
        self.assertFalse((self.out / "SHA256SUMS").exists())


@unittest.skipUnless(SYSUPDATE.exists(), "needs systemd-sysupdate")
class SysupdateTest(FeedCase):
    """The image's own transfer definitions, run by systemd-sysupdate."""

    def serve(self):
        handler = functools.partial(QuietHandler, directory=str(self.feed))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}"

    def device(self, url):
        root = self.case / "root"
        (root / "usr/lib/sysupdate.d").mkdir(parents=True)
        (root / "etc").mkdir()
        (root / "boot/EFI/Linux").mkdir(parents=True)
        (root / "usr/lib/os-release").write_text(
            "ID=postmarketos\nIMAGE_ID=qemu-aarch64\nVARIANT_ID=marathon\nVERSION_ID=edge\n"
            "IMAGE_VERSION=26101701\n")
        (root / "boot/EFI/Linux" / f"{IMAGE_ID}_26101701.efi").write_bytes(b"MZ")
        # Partitions need a real disk; the UKI transfer is the one sysupdate
        # can run unprivileged.
        template = (TRANSFERS / "marathon-20-uki.transfer.in").read_text()
        (root / "usr/lib/sysupdate.d/marathon-20-uki.transfer").write_text(
            template.replace("@MARATHON_OTA_URL@", url))
        return root

    def sysupdate(self, root, *args):
        env = dict(os.environ, SYSTEMD_ESP_PATH="/boot", SYSTEMD_RELAX_ESP_CHECKS="1",
                   SYSTEMD_RELAX_XBOOTLDR_CHECKS="1", SYSTEMD_LOG_LEVEL="info")
        return subprocess.run([str(SYSUPDATE), f"--root={root}", "--sync=no", *args],
                              capture_output=True, text=True, env=env)

    def test_installs_the_new_uki_with_boot_counting(self):
        self.build("26101801")
        self.publish("26101801")
        root = self.device(self.serve())
        check = self.sysupdate(root, "--verify=no", "check-new")
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(check.stdout.strip(), "26101801")
        update = self.sysupdate(root, "--verify=no", "update")
        self.assertEqual(update.returncode, 0, update.stderr)
        installed = sorted(p.name for p in (root / "boot/EFI/Linux").iterdir())
        self.assertEqual(installed, [f"{IMAGE_ID}_26101701.efi", f"{IMAGE_ID}_26101801+3-0.efi"])
        self.assertEqual((root / "boot/EFI/Linux" / f"{IMAGE_ID}_26101801+3-0.efi").read_bytes(),
                         b"MZ26101801")

    def test_refuses_a_feed_signed_by_an_untrusted_key(self):
        # The host keyring does not hold the test key, as a device's would
        # not hold an attacker's.
        self.build("26101801")
        self.publish("26101801")
        root = self.device(self.serve())
        check = self.sysupdate(root, "check-new")
        self.assertNotEqual(check.returncode, 0)
        self.assertIn("Signature verification failed", check.stderr)
        self.assertEqual(len(list((root / "boot/EFI/Linux").iterdir())), 1)


if __name__ == "__main__":
    unittest.main()
