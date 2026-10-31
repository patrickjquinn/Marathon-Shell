#!/usr/bin/env python3
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / 'q25-root-install.sh'
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


if __name__ == '__main__':
    unittest.main()
