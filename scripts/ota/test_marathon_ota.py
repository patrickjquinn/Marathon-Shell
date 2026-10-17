"""marathon-ota publishes a feed systemd-sysupdate can verify and consume."""

import functools
import hashlib
import http.server
import json
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
PI_TRANSFERS = Path(__file__).resolve().parents[2] / "packaging" / "ota" / "pi" / "sysupdate.d"
SYSUPDATE = Path("/usr/lib/systemd/systemd-sysupdate")
IMAGE_ID = "qemu-aarch64_marathon_edge"
PI_IMAGE_ID = "raspberry-pi5_marathon_edge"
BOOT_TYPE = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
ROOT_TYPE = "B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
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

    image_id = IMAGE_ID

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.tmp))
        self.image_dir = self.case / self.image_id
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

    def build_pi(self, version, uuid=UUID_A, payload=b"slot"):
        stem = f"{self.image_id}_{version}"
        (self.image_dir / f"{stem}.boot.{uuid}.raw").write_bytes(b"boot" + payload * 1024)
        (self.image_dir / f"{stem}.root.{uuid}.raw").write_bytes(b"root" + payload * 2048)
        # mkosi still writes a UKI and the whole disk; neither is an update.
        (self.image_dir / f"{stem}.efi").write_bytes(b"MZ")
        (self.image_dir / f"{stem}.raw").write_bytes(b"disk")

    @property
    def out(self):
        return self.feed / self.image_id



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


class PiPublishTest(FeedCase):
    image_id = PI_IMAGE_ID

    def test_feed_holds_the_boot_and_root_slots(self):
        self.build_pi("26101701")
        self.publish("26101701")
        stem = f"{PI_IMAGE_ID}_26101701"
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), sorted([
            "SHA256SUMS", "SHA256SUMS.gpg", "marathon-os.metainfo.xml",
            f"{stem}.boot.{UUID_A}.raw.zst",
            f"{stem}.root.{UUID_A}.raw.zst",
        ]))

    def test_keeps_the_newest_versions_and_refuses_going_backwards(self):
        for i, version in enumerate(["26101701", "26101801", "26101901"]):
            self.build_pi(version, f"{i:032x}")
            self.publish(version)
        names = {p.name for p in self.out.iterdir()}
        self.assertFalse(any("26101701" in n for n in names), names)
        self.assertTrue(any("26101801.boot." in n for n in names), names)
        self.build_pi("26101801", UUID_B)
        older = self.publish("26101801", check=False)
        self.assertIn("already in the feed", older.stderr)

    def test_refuses_a_boot_slot_without_its_root(self):
        self.build_pi("26101701")
        (self.image_dir / f"{PI_IMAGE_ID}_26101701.root.{UUID_A}.raw").unlink()
        result = self.publish("26101701", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no root slot image", result.stderr)


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


@unittest.skipUnless(SYSUPDATE.exists() and shutil.which("sfdisk"), "needs systemd-sysupdate and sfdisk")
class PiSysupdateTest(SysupdateTest):
    """The Pi transfers writing slot partitions of a GPT disk image."""

    image_id = PI_IMAGE_ID
    test_installs_the_new_uki_with_boot_counting = None
    test_refuses_a_feed_signed_by_an_untrusted_key = None

    def device(self, url, running="26101701", first="26101701"):
        root = self.case / "root"
        (root / "usr/lib/sysupdate.d").mkdir(parents=True)
        (root / "etc").mkdir()
        (root / "usr/lib/os-release").write_text(
            "ID=postmarketos\nIMAGE_ID=raspberry-pi5\nVARIANT_ID=marathon\nVERSION_ID=edge\n"
            f"IMAGE_VERSION={running}\n")
        disk = root / "disk.raw"
        with open(disk, "wb") as f:
            f.truncate(32 << 20)
        # mkosi.repart.ab-pi in miniature.
        layout = (
            "label: gpt\n"
            'start=2048, size=2048, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="marathon_autoboot"\n'
            f'size=2048, type={BOOT_TYPE}, name="marathon_{first}_boot"\n'
            f'size=2048, type={BOOT_TYPE}, name="_empty"\n'
            f'size=4096, type={ROOT_TYPE}, name="marathon_{first}_root"\n'
            f'size=4096, type={ROOT_TYPE}, name="_empty"\n'
            'size=2048, type=4D21B016-B534-45C2-A9FB-5C16E091FD2D, name="marathon_data"\n')
        subprocess.run(["sfdisk", "-q", str(disk)], input=layout, text=True, check=True)
        for t in PI_TRANSFERS.glob("*.transfer.in"):
            text = t.read_text().replace("@MARATHON_OTA_URL@", url).replace("Path=auto", "Path=/disk.raw")
            (root / "usr/lib/sysupdate.d" / t.name.removesuffix(".in")).write_text(text)
        return root

    def table(self, root):
        dump = json.loads(subprocess.run(["sfdisk", "--json", str(root / "disk.raw")],
                                         capture_output=True, text=True, check=True).stdout)
        return [(p["name"], p["type"], p["start"]) for p in dump["partitiontable"]["partitions"]]

    def slot(self, root, start, size):
        with open(root / "disk.raw", "rb") as f:
            f.seek(start * 512)
            return f.read(size)

    def test_writes_the_free_slot_pair_and_labels_it(self):
        self.build_pi("26101801")
        self.publish("26101801")
        root = self.device(self.serve())
        check = self.sysupdate(root, "--verify=no", "check-new")
        self.assertEqual(check.stdout.strip(), "26101801", check.stderr)
        update = self.sysupdate(root, "--verify=no", "update")
        self.assertEqual(update.returncode, 0, update.stderr)
        table = self.table(root)
        self.assertEqual([name for name, _, _ in table], [
            "marathon_autoboot", "marathon_26101701_boot", "marathon_26101801_boot",
            "marathon_26101701_root", "marathon_26101801_root", "marathon_data"])
        self.assertEqual([t for _, t, _ in table][1:5], [BOOT_TYPE, BOOT_TYPE, ROOT_TYPE, ROOT_TYPE])
        stem = f"{PI_IMAGE_ID}_26101801"
        boot = (self.image_dir / f"{stem}.boot.{UUID_A}.raw").read_bytes()
        rootfs = (self.image_dir / f"{stem}.root.{UUID_A}.raw").read_bytes()
        self.assertEqual(self.slot(root, table[2][2], len(boot)), boot)
        self.assertEqual(self.slot(root, table[4][2], len(rootfs)), rootfs)

    def test_never_overwrites_the_running_slot(self):
        self.build_pi("26101801")
        self.publish("26101801")
        url = self.serve()
        root = self.device(url, running="26101801")
        # Booted 26101801 from the second pair; 26101701 is the other one.
        subprocess.run(["sfdisk", "-q", "--part-label", str(root / "disk.raw"), "3", "marathon_26101801_boot"],
                       check=True)
        subprocess.run(["sfdisk", "-q", "--part-label", str(root / "disk.raw"), "5", "marathon_26101801_root"],
                       check=True)
        self.build_pi("26101901", UUID_B, b"new")
        self.publish("26101901")
        update = self.sysupdate(root, "--verify=no", "update")
        self.assertEqual(update.returncode, 0, update.stderr)
        names = [name for name, _, _ in self.table(root)]
        self.assertEqual(names[1:5], ["marathon_26101901_boot", "marathon_26101801_boot",
                                      "marathon_26101901_root", "marathon_26101801_root"])


if __name__ == "__main__":
    unittest.main()
