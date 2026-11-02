#!/usr/bin/env python3
"""The Q25 carrier initramfs hook, run against a fake root with mount,
losetup and mountpoint stubbed out."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[2] / 'packaging/packages/device-zinwa-q25/q25-carrier.hook'
SHELL = shutil.which('dash') or 'sh'
IMAGE = '/var/lib/marathon/images/q25-1.ext4'

STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$(basename "$0") $*" in
"losetup "*) [ -z "$STUB_LOSETUP_FAIL" ] && echo /dev/loop9 || exit 1 ;;
"mount -t ext4 "*) exit "${STUB_MOUNT_RC:-0}" ;;
"mountpoint -q "*) [ -z "$STUB_NO_BOOT" ] ;;
esac
"""


class CarrierHook(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        bin_dir = self.root / 'stub-bin'
        bin_dir.mkdir()
        for name in ('mount', 'losetup', 'mountpoint'):
            (bin_dir / name).write_text(STUB)
            (bin_dir / name).chmod(0o755)
        self.log = self.root / 'calls'
        self.log.touch()
        (self.root / 'dev').mkdir()
        (self.root / 'dev/kmsg').touch()
        (self.root / 'proc').mkdir()
        (self.root / f'sysroot{IMAGE}').parent.mkdir(parents=True)
        (self.root / f'sysroot{IMAGE}').touch()
        self.cmdline(f'console=tty0 q25.rootfs_file={IMAGE} loglevel=4')
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        MARATHON_Q25_TEST_ROOT=str(self.root), STUB_LOG=str(self.log))

    def cmdline(self, text):
        (self.root / 'proc/cmdline').write_text(text + '\n')

    def run_hook(self, **env):
        result = subprocess.run([SHELL, str(HOOK)], env={**self.env, **env},
                                capture_output=True, text=True, timeout=30)
        return result.returncode, self.log.read_text().splitlines()

    def test_without_a_root_file_leaves_the_carrier_as_root(self):
        self.cmdline('console=tty0')
        self.assertEqual(self.run_hook(), (0, []))

    def test_mounts_the_file_and_keeps_carrier_and_esp(self):
        rc, calls = self.run_hook()
        self.assertEqual(rc, 0, calls)
        r = self.root
        self.assertEqual(calls, [
            f'mount --move {r}/sysroot {r}/q25-carrier',
            f'losetup --find --show --sector-size 4096 {r}/q25-carrier{IMAGE}',
            f'mount -t ext4 -o rw /dev/loop9 {r}/sysroot',
            f'mountpoint -q {r}/q25-carrier/boot',
            f'mount --move {r}/q25-carrier/boot {r}/sysroot/boot',
            f'mount -o remount,ro {r}/sysroot/boot',
            f'mount --move {r}/q25-carrier {r}/sysroot/.q25-carrier/root',
        ])
        self.assertEqual((r / 'sysroot/.q25-carrier').stat().st_mode & 0o777, 0o700)

    def test_no_esp_mount_is_fine(self):
        rc, calls = self.run_hook(STUB_NO_BOOT='1')
        self.assertEqual(rc, 0, calls)
        self.assertFalse(any('boot' in c and c.startswith('mount ') for c in calls))

    def test_refuses_paths_outside_the_images_dir(self):
        for bad in ('/etc/shadow', '/var/lib/marathon/images/../x.ext4',
                    '/var/lib/marathon/images/a b.ext4', '/var/lib/marathon/images/x.img'):
            with self.subTest(bad=bad):
                self.cmdline(f'q25.rootfs_file={bad}')
                rc, calls = self.run_hook()
                self.assertEqual((rc, calls), (1, []))

    def test_missing_file_leaves_everything_mounted(self):
        (self.root / f'sysroot{IMAGE}').unlink()
        rc, calls = self.run_hook()
        self.assertEqual((rc, calls), (1, []))
        self.assertIn('no /var', (self.root / 'dev/kmsg').read_text())

    def test_a_file_that_will_not_mount_puts_the_carrier_back(self):
        rc, calls = self.run_hook(STUB_MOUNT_RC='32')
        self.assertEqual(rc, 1)
        r = self.root
        self.assertEqual(calls[-2:], ['losetup -d /dev/loop9', f'mount --move {r}/q25-carrier {r}/sysroot'])

    def test_losetup_failure_puts_the_carrier_back(self):
        rc, calls = self.run_hook(STUB_LOSETUP_FAIL='1')
        self.assertEqual(rc, 1)
        self.assertEqual(calls[-1], f'mount --move {self.root}/q25-carrier {self.root}/sysroot')
        self.assertNotIn('losetup -d', ' '.join(calls))


if __name__ == '__main__':
    unittest.main()
