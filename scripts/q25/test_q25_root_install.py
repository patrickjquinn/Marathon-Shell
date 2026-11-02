#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / 'packaging/packages/device-zinwa-q25-marathon/q25-root-install'
OPTIONS = ('options pd_ignore_unused console=tty0 pmos_boot_uuid=F362-E950 '
           'q25.rootfs_file=/var/lib/marathon/images/old.ext4 systemd.gpt_auto=0\n')
CURRENT = ('title Marathon Q25 everyday + modem (no bootcon)\nsort-key postmarketOS\n'
           'linux linux-q25-adc-test.efi\n\ninitrd /initramfs-q25-duranium-carrier\n'
           'devicetree /dtbs/mediatek/q25.dtb\n' + OPTIONS)
LOADER = 'default everyday.conf\ntimeout 5\n'


class RootInstall(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.esp, self.carrier = root / 'esp', root / 'carrier'
        (self.esp / 'loader/entries').mkdir(parents=True)
        (self.esp / 'loader/loader.conf').write_text(LOADER)
        (self.esp / 'loader/entries/everyday.conf').write_text(CURRENT)
        (self.carrier / 'var/lib/marathon/images').mkdir(parents=True)
        self.image = self.carrier / 'new-1.ext4'
        self.image.write_bytes(b'root')

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *args, check=True):
        cmd = ['sh', str(SCRIPT), '--esp', str(self.esp), '--carrier', str(self.carrier), '--no-remount', *args]
        return subprocess.run(cmd, check=check, capture_output=True, text=True)

    def tree(self):
        return {p.relative_to(self.tmp.name).as_posix(): p.read_bytes()
                for p in Path(self.tmp.name).rglob('*') if p.is_file()}

    def test_dry_run_changes_nothing(self):
        before = self.tree()
        out = self.run_script('--dry-run', 'install', str(self.image)).stdout
        self.assertIn('q25.rootfs_file=/var/lib/marathon/images/new-1.ext4', out)
        self.assertEqual(self.tree(), before)

    def test_plain_install_changes_only_the_root_token(self):
        self.run_script('install', str(self.image))
        entry = (self.esp / 'loader/entries/marathon-q25-new-1.conf').read_text()
        self.assertEqual(entry, CURRENT.replace('images/old.ext4', 'images/new-1.ext4'))
        self.assertEqual((self.esp / 'loader/loader.conf').read_text(), 'default marathon-q25-new-1.conf\ntimeout 5\n')
        self.assertEqual((self.esp / 'loader/loader.conf.before-new-1').read_text(), LOADER)
        self.assertEqual((self.esp / 'loader/entries/everyday.conf').read_text(), CURRENT)
        self.assertFalse(self.image.exists())
        self.assertEqual((self.carrier / 'var/lib/marathon/images/new-1.ext4').read_bytes(), b'root')

    def test_counted_install_adds_fallback_and_glob_default(self):
        self.run_script('--counted', 'install', str(self.image))
        entries = self.esp / 'loader/entries'
        new = (entries / 'marathon-q25-b-new-1+3.conf').read_text()
        self.assertTrue(new.endswith('sort-key marathon-q25\nversion new-1\n'))
        self.assertNotIn('postmarketOS', new)
        fallback = (entries / 'marathon-q25-a-fallback.conf').read_text()
        self.assertIn('images/old.ext4', fallback)
        self.assertTrue(fallback.endswith('sort-key marathon-q25\nversion 0\n'))
        self.assertEqual((self.esp / 'loader/loader.conf').read_text(), 'default marathon-q25-*\ntimeout 5\n')

    def test_refuses_existing_image_and_wrong_sha(self):
        (self.carrier / 'var/lib/marathon/images/new-1.ext4').write_bytes(b'other')
        self.assertNotEqual(self.run_script('install', str(self.image), check=False).returncode, 0)
        (self.carrier / 'var/lib/marathon/images/new-1.ext4').unlink()
        before = self.tree()
        self.assertNotEqual(self.run_script('install', str(self.image), '0' * 64, check=False).returncode, 0)
        self.assertEqual(self.tree(), before)

    def test_rollback_restores_loader_and_removes_entries(self):
        for mode in ([], ['--counted']):
            self.run_script(*mode, 'install', str(self.image))
            self.run_script('rollback', 'new-1')
            self.assertEqual((self.esp / 'loader/loader.conf').read_text(), LOADER)
            self.assertEqual(sorted(p.name for p in (self.esp / 'loader/entries').iterdir()), ['everyday.conf'])
            (self.esp / 'loader/loader.conf.before-new-1').unlink()
            (self.carrier / 'var/lib/marathon/images/new-1.ext4').rename(self.image)


OS_RELEASE = 'IMAGE_ID=zinwa-q25\nVARIANT_ID=marathon\nVERSION_ID=edge\nIMAGE_VERSION="26110101"\n'
STEM = 'zinwa-q25_marathon_edge_'
# The loop mount, as a link to the image's stand-in tree; systemctl records
# what it was asked.
MOUNT = ('#!/bin/sh\n[ "$1" = -o ] && [ "$2" = loop ] || exit 1\n'
         'rmdir "$4" && ln -s "$3.d" "$4"\n')
UMOUNT = '#!/bin/sh\nrm "$1"\n'
SYSTEMCTL = '#!/bin/sh\necho "$@" >> "$(dirname "$0")/systemctl.log"\n'


class Arm(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        top = Path(self.tmp.name)
        self.esp, self.carrier, self.root, self.bin = top / 'esp', top / 'carrier', top / 'root', top / 'bin'
        self.entries = self.esp / 'loader/entries'
        self.entries.mkdir(parents=True)
        (self.esp / 'loader/loader.conf').write_text(LOADER)
        (self.entries / 'everyday.conf').write_text(CURRENT)
        self.images = self.carrier / 'var/lib/marathon/images'
        self.images.mkdir(parents=True)
        (self.images / 'old.ext4').write_bytes(b'running')
        self.bin.mkdir()
        for name, text in (('mount', MOUNT), ('umount', UMOUNT), ('systemctl', SYSTEMCTL)):
            (self.bin / name).write_text(text)
            (self.bin / name).chmod(0o755)
        self.boot(OPTIONS)
        (self.root / 'etc').mkdir()
        (self.root / 'etc/os-release').write_text(OS_RELEASE)
        self.state = {
            'etc/machine-id': 'a' * 32 + '\n',
            'etc/NetworkManager/system-connections/Home wifi.nmconnection': '[connection]\nid=Home\n',
            'etc/q25-modem/modem.conf': 'IA_APN="data.example"\n',
            'var/lib/bluetooth/0A:91/info': 'paired\n',
            'var/lib/q25-modem/nv/upper/nvdata/md': 'nv\n',
        }
        for rel, text in self.state.items():
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).write_text(text)
        (self.root / 'etc/localtime').symlink_to('../usr/share/zoneinfo/Europe/Dublin')

    def tearDown(self):
        self.tmp.cleanup()

    def boot(self, options):
        (self.root / 'proc').mkdir(parents=True, exist_ok=True)
        (self.root / 'proc/cmdline').write_text('initrd=\\initramfs ' + options.removeprefix('options '))

    def image(self, version):
        """A sysupdate-installed root and the tree its loop mount shows."""
        path = self.images / f'{STEM}{version}.ext4'
        path.write_bytes(b'new')
        shipped = Path(f'{path}.d')
        (shipped / 'etc/q25-modem').mkdir(parents=True)
        (shipped / 'etc/machine-id').write_text('uninitialized\n')
        (shipped / 'etc/q25-modem/modem.conf').write_text('IA_APN=""\n')
        (shipped / 'etc/q25-modem/properties').write_text('defaults\n')
        return shipped

    def arm(self, *args, check=True):
        cmd = ['sh', str(SCRIPT), '--esp', str(self.esp), '--carrier', str(self.carrier),
               '--root', str(self.root), '--no-remount', 'arm', *args]
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}')
        return subprocess.run(cmd, check=check, capture_output=True, text=True, env=env)

    def esp_tree(self):
        return {p.relative_to(self.esp).as_posix(): p.read_text() for p in self.esp.rglob('*') if p.is_file()}

    def test_carries_the_phone_state_and_boots_the_new_root_counted(self):
        shipped = self.image('26110201')
        self.arm()
        name = f'{STEM}26110201'
        new = (self.entries / f'marathon-q25-b-{name}+3.conf').read_text()
        self.assertIn(f'q25.rootfs_file=/var/lib/marathon/images/{name}.ext4 ', new)
        self.assertIn('devicetree /dtbs/mediatek/q25.dtb\n', new)
        self.assertTrue(new.endswith('sort-key marathon-q25\nversion 26110201\n'))
        fallback = (self.entries / 'marathon-q25-a-fallback.conf').read_text()
        self.assertIn('images/old.ext4', fallback)
        self.assertTrue(fallback.endswith('sort-key marathon-q25\nversion 0\n'))
        self.assertEqual((self.esp / 'loader/loader.conf').read_text(), 'default marathon-q25-*\ntimeout 5\n')
        self.assertEqual((self.esp / f'loader/loader.conf.before-{name}').read_text(), LOADER)
        self.assertEqual((self.entries / 'everyday.conf').read_text(), CURRENT)
        for rel, text in self.state.items():
            self.assertEqual((shipped / rel).read_text(), text, rel)
        self.assertEqual(os.readlink(shipped / 'etc/localtime'), '../usr/share/zoneinfo/Europe/Dublin')
        self.assertEqual((shipped / 'etc/q25-modem/properties').read_text(), 'defaults\n')
        self.assertFalse((self.bin / 'systemctl.log').exists())

    def test_reboot_restarts_once_armed(self):
        self.image('26110201')
        self.arm('--reboot')
        self.assertEqual((self.bin / 'systemctl.log').read_text(), '--no-block reboot\n')
        self.arm('--reboot')
        self.assertEqual((self.bin / 'systemctl.log').read_text(), '--no-block reboot\n')

    def test_dry_run_changes_nothing(self):
        shipped = self.image('26110201')
        before = self.esp_tree()
        cmd = ['sh', str(SCRIPT), '--dry-run', '--esp', str(self.esp), '--carrier', str(self.carrier),
               '--root', str(self.root), '--no-remount', 'arm', '--reboot']
        out = subprocess.run(cmd, check=True, capture_output=True, text=True,
                             env=dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}')).stdout
        self.assertIn(f'images/{STEM}26110201.ext4', out)
        self.assertEqual(self.esp_tree(), before)
        self.assertEqual((shipped / 'etc/machine-id').read_text(), 'uninitialized\n')
        self.assertFalse((self.bin / 'systemctl.log').exists())

    def test_nothing_newer_installed_changes_nothing(self):
        before = self.esp_tree()
        self.arm()
        (self.images / 'q25-duranium-20261201-abc.ext4').write_bytes(b'by hand')
        (self.images / f'.sysupdate.partial.{STEM}26120101.ext4').write_bytes(b'half')
        self.image('26110101')
        self.image('26103101')
        self.arm()
        self.assertEqual(self.esp_tree(), before)

    def test_a_version_that_was_tried_is_left_alone(self):
        self.image('26110201')
        (self.entries / f'marathon-q25-b-{STEM}26110201+0-3.conf').write_text(CURRENT)
        before = self.esp_tree()
        self.assertIn('was armed before', self.arm().stdout)
        self.assertEqual(self.esp_tree(), before)

    def test_from_the_fallback_the_next_update_replaces_the_failed_entry(self):
        # 26110201 used up its tries; the fallback, now booted, shares its
        # options with the plain everyday entry.
        self.image('26110201')
        self.arm()
        failed = self.entries / f'marathon-q25-b-{STEM}26110201+3.conf'
        failed.rename(failed.with_name(f'marathon-q25-b-{STEM}26110201+0-3.conf'))
        (self.images / f'{STEM}26110201.ext4').unlink()
        self.image('26110301')
        self.arm()
        entries = sorted(p.name for p in self.entries.iterdir())
        self.assertEqual(entries, ['everyday.conf', 'marathon-q25-a-fallback.conf',
                                   f'marathon-q25-b-{STEM}26110301+3.conf'])
        self.assertIn('images/old.ext4', (self.entries / 'marathon-q25-a-fallback.conf').read_text())

    def test_after_a_good_update_the_running_root_becomes_the_fallback(self):
        self.image('26110201')
        self.arm()
        name = f'{STEM}26110201'
        blessed = self.entries / f'marathon-q25-b-{name}.conf'
        (self.entries / f'marathon-q25-b-{name}+3.conf').rename(blessed)
        self.boot(next(line for line in blessed.read_text().splitlines() if line.startswith('options ')))
        (self.root / 'etc/os-release').write_text(OS_RELEASE.replace('26110101', '26110201'))
        self.image('26110301')
        self.arm()
        self.assertFalse(blessed.exists())
        fallback = (self.entries / 'marathon-q25-a-fallback.conf').read_text()
        self.assertIn(f'images/{name}.ext4', fallback)
        self.assertTrue(fallback.endswith('version 0\n'))
        self.assertTrue((self.entries / f'marathon-q25-b-{STEM}26110301+3.conf').exists())

    def test_refuses_when_the_booted_entry_is_unknown(self):
        self.image('26110201')
        self.boot('options console=tty0 q25.rootfs_file=/elsewhere.ext4\n')
        before = self.esp_tree()
        result = self.arm(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot tell which entry booted', result.stderr)
        self.assertEqual(self.esp_tree(), before)


if __name__ == '__main__':
    unittest.main()
