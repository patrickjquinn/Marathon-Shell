#!/usr/bin/env python3
"""The userdata carrier initramfs hook, run against a fake root with mount,
losetup and mountpoint stubbed out, under the Q25's carrier name and the
MP01's."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[2] / 'packaging/carrier/mkinitfs/hooks-cleanup/50-marathon-carrier.sh'
SHELL = shutil.which('dash') or 'sh'
IMAGE = '/var/lib/marathon/images/root-1.ext4'

STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$(basename "$0") $*" in
"losetup "*) [ -z "$STUB_LOSETUP_FAIL" ] && echo /dev/loop9 || exit 1 ;;
"mount -t ext4 "*) exit "${STUB_MOUNT_RC:-0}" ;;
"mountpoint -q "*) [ -z "$STUB_NO_BOOT" ] ;;
esac
"""


class CarrierHook:
    NAME = ''

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
        (self.root / 'usr/share/marathon').mkdir(parents=True)
        (self.root / 'usr/share/marathon/carrier.conf').write_text(
            f'CARRIER_NAME={self.NAME}\nCARRIER_DTB=vendor/board.dtb\n')
        self.cmdline(f'console=tty0 {self.NAME}.rootfs_file={IMAGE} loglevel=4')
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        MARATHON_CARRIER_TEST_ROOT=str(self.root), STUB_LOG=str(self.log))

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
            f'mount --move {r}/sysroot {r}/{self.NAME}-carrier',
            f'losetup --find --show --sector-size 4096 {r}/{self.NAME}-carrier{IMAGE}',
            f'mount -t ext4 -o rw /dev/loop9 {r}/sysroot',
            f'mountpoint -q {r}/{self.NAME}-carrier/boot',
            f'mount --move {r}/{self.NAME}-carrier/boot {r}/sysroot/boot',
            f'mount -o remount,ro {r}/sysroot/boot',
            f'mount --move {r}/{self.NAME}-carrier {r}/sysroot/.{self.NAME}-carrier/root',
        ])
        self.assertEqual((r / f'sysroot/.{self.NAME}-carrier').stat().st_mode & 0o777, 0o700)

    def test_no_esp_mount_is_fine(self):
        rc, calls = self.run_hook(STUB_NO_BOOT='1')
        self.assertEqual(rc, 0, calls)
        self.assertFalse(any('boot' in c and c.startswith('mount ') for c in calls))

    def test_refuses_paths_outside_the_images_dir(self):
        for bad in ('/etc/shadow', '/var/lib/marathon/images/../x.ext4',
                    '/var/lib/marathon/images/a b.ext4', '/var/lib/marathon/images/x.img'):
            with self.subTest(bad=bad):
                self.cmdline(f'{self.NAME}.rootfs_file={bad}')
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
        self.assertEqual(calls[-2:], ['losetup -d /dev/loop9', f'mount --move {r}/{self.NAME}-carrier {r}/sysroot'])

    def test_losetup_failure_puts_the_carrier_back(self):
        rc, calls = self.run_hook(STUB_LOSETUP_FAIL='1')
        self.assertEqual(rc, 1)
        self.assertEqual(calls[-1], f'mount --move {self.root}/{self.NAME}-carrier {self.root}/sysroot')
        self.assertNotIn('losetup -d', ' '.join(calls))


    def test_ignores_another_carrier_name(self):
        other = 'mp01' if self.NAME == 'q25' else 'q25'
        self.cmdline(f'{other}.rootfs_file={IMAGE}')
        self.assertEqual(self.run_hook(), (0, []))

    def test_refuses_without_a_carrier_name(self):
        (self.root / 'usr/share/marathon/carrier.conf').write_text('CARRIER_DTB=vendor/board.dtb\n')
        rc, calls = self.run_hook()
        self.assertEqual((rc, calls), (1, []))
        self.assertIn('no CARRIER_NAME', (self.root / 'dev/kmsg').read_text())


class Q25(CarrierHook, unittest.TestCase):
    NAME = 'q25'


class MP01(CarrierHook, unittest.TestCase):
    NAME = 'mp01'


if __name__ == '__main__':
    unittest.main()
