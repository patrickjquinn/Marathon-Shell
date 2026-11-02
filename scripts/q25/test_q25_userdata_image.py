#!/usr/bin/env python3
"""q25-userdata-image.sh on a small synthetic root, checked by reading the
sparse image back."""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'q25-userdata-image.sh'
CMDLINE = HERE.parents[1] / 'packaging/packages/device-zinwa-q25/kernel-cmdline.conf'
TOOLS = ('debugfs', 'mke2fs', 'e2fsck', 'mkfs.vfat', 'mmd', 'mcopy', 'mtype', 'sfdisk', 'img2simg',
         'simg2img', 'blkid')
SECTOR = 4096
ESP = 2048 * SECTOR
CARRIER = 62464 * SECTOR
FILES = {
    'boot/linux.efi': b'zboot kernel',
    'boot/initramfs': b'initramfs',
    'boot/dtbs/mediatek/mt8781-zinwa-q25.dtb': b'board dtb',
    'usr/lib/systemd/boot/efi/systemd-bootaa64.efi': b'systemd-boot',
}


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


@unittest.skipUnless(all(shutil.which(t) for t in TOOLS), 'needs e2fsprogs, dosfstools, mtools, sfdisk, '
                     'android-tools')
class UserdataImage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        tree = cls.tmp / 'tree'
        for rel, data in FILES.items():
            (tree / rel).parent.mkdir(parents=True, exist_ok=True)
            (tree / rel).write_bytes(data)
        conf = tree / 'usr/lib/kernel-cmdline.d/50-device-zinwa-q25.conf'
        conf.parent.mkdir(parents=True)
        shutil.copy(CMDLINE, conf)
        cls.root = cls.tmp / 'q25-test-1.ext4'
        run('truncate', '-s', '16M', str(cls.root))
        run('mke2fs', '-q', '-t', 'ext4', '-d', str(tree), str(cls.root))
        cls.out = cls.tmp / 'userdata.img'
        cls.log = run('bash', str(SCRIPT), str(cls.root), str(cls.out))
        cls.raw = cls.tmp / 'userdata.raw'
        run('simg2img', str(cls.out), str(cls.raw))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def esp(self, path):
        return subprocess.run(['mtype', '-i', f'{self.raw}@@{ESP}', f'::{path}'], check=True,
                              capture_output=True).stdout

    def carrier(self, cmd):
        return run('debugfs', '-R', cmd, f'{self.raw}?offset={CARRIER}')

    def blkid(self, offset, tag):
        return run('blkid', '-p', '-O', str(offset), '-s', tag, '-o', 'value', str(self.raw)).strip()

    def test_is_a_sparse_image(self):
        self.assertEqual(self.out.read_bytes()[:4], b'\x3a\xff\x26\xed')

    def test_nested_gpt_with_4k_sectors(self):
        table = run('sfdisk', '--sector-size', str(SECTOR), '-d', str(self.raw))
        self.assertIn('sector-size: 4096', table)
        parts = re.findall(r'start=\s*(\d+), size=\s*(\d+), type=([0-9A-F-]+)', table)
        self.assertEqual(parts[0], ('2048', '60416', 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'))
        self.assertEqual(parts[1][0], '62464')
        self.assertEqual(parts[1][2], 'B921B045-1DF0-41C3-AF44-4C6F280D3FAE')
        self.assertEqual(len(parts), 2)

    def test_filesystems(self):
        self.assertEqual(self.blkid(ESP, 'TYPE'), 'vfat')
        self.assertEqual(self.blkid(ESP, 'LABEL'), 'pmOS_boot')
        self.assertEqual(self.blkid(ESP, 'FSBLOCKSIZE'), '4096')
        self.assertEqual(self.blkid(CARRIER, 'TYPE'), 'ext4')
        self.assertEqual(self.blkid(CARRIER, 'LABEL'), 'pmOS_root')

    def test_esp_holds_the_root_boot_files(self):
        self.assertEqual(self.esp('/linux.efi'), FILES['boot/linux.efi'])
        self.assertEqual(self.esp('/initramfs'), FILES['boot/initramfs'])
        self.assertEqual(self.esp('/dtbs/mediatek/mt8781-zinwa-q25.dtb'),
                         FILES['boot/dtbs/mediatek/mt8781-zinwa-q25.dtb'])
        self.assertEqual(self.esp('/EFI/BOOT/BOOTAA64.EFI'),
                         FILES['usr/lib/systemd/boot/efi/systemd-bootaa64.efi'])

    def test_entry_boots_the_root_file_on_this_carrier(self):
        self.assertEqual(self.esp('/loader/loader.conf'), b'default marathon-q25-q25-test-1.conf\n')
        entry = self.esp('/loader/entries/marathon-q25-q25-test-1.conf').decode()
        self.assertIn('linux /linux.efi\n', entry)
        self.assertIn('initrd /initramfs\n', entry)
        self.assertIn('devicetree /dtbs/mediatek/mt8781-zinwa-q25.dtb\n', entry)
        options = re.search(r'^options (.*)$', entry, re.M).group(1).split()
        package = [w for w in CMDLINE.read_text().split() if not w.startswith('#')]
        self.assertEqual(options[:len(package)], package)
        self.assertEqual(options[len(package):], [
            f'pmos_boot_uuid={self.blkid(ESP, "UUID")}',
            f'pmos_root_uuid={self.blkid(CARRIER, "UUID")}',
            'q25.rootfs_file=/var/lib/marathon/images/q25-test-1.ext4',
        ])

    def test_carrier_holds_the_root_image_for_root_only(self):
        dump = self.tmp / 'dumped.ext4'
        self.carrier(f'dump /var/lib/marathon/images/q25-test-1.ext4 {dump}')
        self.assertEqual(dump.read_bytes(), self.root.read_bytes())
        listing = self.carrier('ls -l /var/lib/marathon/images')
        self.assertRegex(listing, r'100600 \(1\)\s+0\s+0\s+16777216 .* q25-test-1.ext4')
        self.assertRegex(self.carrier('ls -l /var/lib/marathon'), r'40700 \(2\)\s+0\s+0 .* images')
        self.assertIn('ID=marathon-q25-carrier', self.carrier('cat /usr/lib/os-release'))
        run('e2fsck', '-fn', f'{self.raw}?offset={CARRIER}')

    def test_root_is_untouched(self):
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o644)


@unittest.skipUnless(all(shutil.which(t) for t in TOOLS), 'needs the image tools')
class Refusals(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def make(self, name, files):
        tree = self.tmp / 'tree'
        for rel, data in files.items():
            (tree / rel).parent.mkdir(parents=True, exist_ok=True)
            (tree / rel).write_bytes(data)
        root = self.tmp / name
        run('truncate', '-s', '8M', str(root))
        run('mke2fs', '-q', '-t', 'ext4', '-d', str(tree), str(root))
        return root

    def build(self, root):
        out = self.tmp / 'out.img'
        r = subprocess.run(['bash', str(SCRIPT), str(root), str(out)], capture_output=True, text=True)
        return r, out

    def test_root_without_an_initramfs(self):
        files = {k: v for k, v in FILES.items() if k != 'boot/initramfs'}
        r, out = self.build(self.make('q25-a.ext4', files))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('has no /boot/initramfs', r.stderr)
        self.assertFalse(out.exists())
        self.assertEqual([p.name for p in self.tmp.iterdir() if p.name.startswith('.q25')], [])

    def test_name_that_is_not_a_loader_token(self):
        r, out = self.build(self.make('q25 a.ext4', FILES))
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(out.exists())


if __name__ == '__main__':
    unittest.main()
