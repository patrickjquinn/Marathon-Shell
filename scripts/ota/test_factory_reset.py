"""Erase all content on Raspberry Pi A/B images: the request the shell sends
the root service, the initramfs hook that acts on it, and the wipe helper,
run against file-backed images with the real mke2fs and cryptsetup where
they work without root."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

PI = Path(__file__).resolve().parents[2] / "packaging" / "ota" / "pi"
REQUEST = PI / "factory-reset" / "marathon-factory-reset"
WIPE = PI / "factory-reset" / "marathon-wipe-data"
HOOK = PI / "mkinitfs" / "hooks-cleanup" / "40-marathon-factory-reset.sh"
# The initramfs runs them with busybox ash; dash is the closest host shell.
SHELL = shutil.which("dash") or "sh"
TOOLS = all(shutil.which(t) for t in ("mke2fs", "cryptsetup", "debugfs", "blkid"))


def run(cmd, env=None, stdin=""):
    return subprocess.run(cmd, env=env, input=stdin, capture_output=True, text=True, timeout=120)


class Case(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.env = dict(os.environ, MARATHON_AB_TEST_ROOT=str(self.root))

    def data_partition(self, size_mib=32):
        (self.root / "dev/disk/by-partlabel").mkdir(parents=True, exist_ok=True)
        image = self.root / "dev/mmcblk0p6"
        with open(image, "wb") as f:
            f.truncate(size_mib << 20)
        (self.root / "dev/disk/by-partlabel/marathon_data").symlink_to("../../mmcblk0p6")
        return image


class RequestTest(Case):
    def test_an_erase_request_leaves_the_marker(self):
        self.data_partition()
        r = run([SHELL, str(REQUEST)], self.env, "erase\n")
        self.assertEqual((r.returncode, r.stdout), (0, "ok\n"), r.stderr)
        self.assertTrue((self.root / ".marathon-factory-reset").exists())

    def test_anything_else_is_refused(self):
        self.data_partition()
        for line in ("", "erase now\n", "reboot\n"):
            r = run([SHELL, str(REQUEST)], self.env, line)
            self.assertEqual((r.returncode, r.stdout), (1, "unknown request\n"), line)
        self.assertFalse((self.root / ".marathon-factory-reset").exists())

    def test_without_a_data_partition_nothing_is_recorded(self):
        r = run([SHELL, str(REQUEST)], self.env, "erase\n")
        self.assertEqual((r.returncode, r.stdout), (1, "this device has no data partition to erase\n"))
        self.assertFalse((self.root / ".marathon-factory-reset").exists())


class HookTest(Case):
    def setUp(self):
        super().setUp()
        (self.root / "sysroot").mkdir()
        (self.root / "dev").mkdir()
        (self.root / "dev/kmsg").touch()
        self.calls = self.root / "calls"
        helper = self.root / "usr/libexec/marathon-wipe-data"
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/sh\necho "$*" >> "$STUB_LOG"\nexit "${STUB_RC:-0}"\n')
        helper.chmod(0o755)
        self.env["STUB_LOG"] = str(self.calls)
        self.marker = self.root / "sysroot/.marathon-factory-reset"

    def run_hook(self, **env):
        r = run([SHELL, str(HOOK)], {**self.env, **env})
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return r.returncode, calls, (self.root / "dev/kmsg").read_text()

    def test_without_a_request_nothing_is_erased(self):
        self.data_partition()
        self.assertEqual(self.run_hook(), (0, [], ""))

    def test_a_request_erases_the_data_partition_once(self):
        image = self.data_partition()
        self.marker.touch()
        rc, calls, log = self.run_hook()
        self.assertEqual((rc, calls), (0, [str(image)]))
        self.assertFalse(self.marker.exists())
        self.assertIn(f"erased {image}", log)

    def test_a_failed_erase_is_tried_again_at_the_next_boot(self):
        self.data_partition()
        self.marker.touch()
        rc, calls, log = self.run_hook(STUB_RC="1")
        self.assertEqual((rc, len(calls)), (1, 1))
        self.assertTrue(self.marker.exists())
        self.assertIn("trying again at the next boot", log)

    def test_no_data_partition_keeps_the_request(self):
        self.marker.touch()
        rc, calls, log = self.run_hook()
        self.assertEqual((rc, calls), (1, []))
        self.assertTrue(self.marker.exists())
        self.assertIn("no marathon_data partition", log)


@unittest.skipUnless(TOOLS, "needs mke2fs, cryptsetup, debugfs and blkid")
class WipeTest(Case):
    """The real tools on an image file, except what needs root: opening a
    LUKS container is stubbed, and so is the file system made inside it."""

    def setUp(self):
        super().setUp()
        self.image = self.data_partition()
        self.old_key = self.root / "old.key"
        self.old_key.write_bytes(os.urandom(32))

    def probe(self, tag):
        return run(["blkid", "-p", "-o", "value", "-s", tag, str(self.image)]).stdout.strip()

    def luks(self, key):
        r = run(["cryptsetup", "luksFormat", "-q", "--type", "luks2", "--pbkdf", "pbkdf2",
                 "--pbkdf-force-iterations", "1000", "--key-file", str(key), str(self.image)])
        self.assertEqual(r.returncode, 0, r.stderr)

    def opens(self, key):
        return run(["cryptsetup", "open", "--test-passphrase", "--key-file", str(key),
                    str(self.image)]).returncode == 0

    def wipe(self, *args, env=None):
        return run([SHELL, str(WIPE), *args, str(self.image)], env or self.env)

    def test_plain_ext4_comes_back_empty(self):
        self.assertEqual(run(["mke2fs", "-q", "-F", "-t", "ext4", str(self.image)]).returncode, 0)
        secret = self.root / "secret"
        secret.write_text("photos")
        run(["debugfs", "-w", "-R", f"write {secret} secret", str(self.image)])
        self.assertIn("secret", run(["debugfs", "-R", "ls", str(self.image)]).stdout)

        r = self.wipe()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.probe("TYPE"), "ext4")
        self.assertEqual(self.probe("LABEL"), "marathon_data")
        self.assertNotIn("secret", run(["debugfs", "-R", "ls", str(self.image)]).stdout)
        self.assertEqual(run(["e2fsck", "-fn", str(self.image)]).returncode, 0)

    def test_luks_without_a_key_loses_its_keyslots_and_comes_back_plain(self):
        self.luks(self.old_key)
        self.assertTrue(self.opens(self.old_key))
        r = self.wipe()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(self.opens(self.old_key))
        self.assertNotEqual(run(["cryptsetup", "isLuks", str(self.image)]).returncode, 0)
        self.assertEqual(self.probe("TYPE"), "ext4")

    def test_luks_with_a_key_comes_back_as_a_fresh_container(self):
        self.luks(self.old_key)
        new_key = self.root / "new.key"
        new_key.write_bytes(os.urandom(32))
        bin_dir = self.root / "stub-bin"
        bin_dir.mkdir()
        log = self.root / "stub-calls"
        real = shutil.which("cryptsetup")
        (bin_dir / "cryptsetup").write_text(
            '#!/bin/sh\ncase "$1" in open|close) echo "cryptsetup $*" >> "$STUB_LOG"; exit 0 ;; esac\n'
            f'exec {real} "$@"\n')
        (bin_dir / "mke2fs").write_text('#!/bin/sh\necho "mke2fs $*" >> "$STUB_LOG"\n')
        for stub in bin_dir.iterdir():
            stub.chmod(0o755)
        env = dict(self.env, PATH=f"{bin_dir}:{os.environ['PATH']}", STUB_LOG=str(log))

        r = self.wipe("--key-file", str(new_key), env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(self.opens(self.old_key))
        self.assertTrue(self.opens(new_key))
        dump = run(["cryptsetup", "luksDump", str(self.image)]).stdout
        self.assertEqual(dump.count(": luks2"), 1, dump)
        self.assertEqual(log.read_text().splitlines(), [
            f"cryptsetup open --key-file {new_key} {self.image} marathon-wipe-data",
            "mke2fs -q -F -t ext4 -L marathon_data /dev/mapper/marathon-wipe-data",
            "cryptsetup close marathon-wipe-data",
        ])

    def test_usage(self):
        self.assertEqual(run([SHELL, str(WIPE)], self.env).returncode, 2)
        self.assertEqual(run([SHELL, str(WIPE), "a", "b"], self.env).returncode, 2)


if __name__ == "__main__":
    unittest.main()
