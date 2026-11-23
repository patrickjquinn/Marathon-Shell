#!/usr/bin/env python3
"""carrier-userdata-image.sh on small synthetic roots carrying the Q25's and
the MP01's carrier.conf, checked by reading the sparse image back. Where the
host's mke2fs is 1.47.3 the script runs itself in an Alpine container."""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'carrier-userdata-image.sh'
PACKAGES = HERE.parents[1] / 'packaging/packages'
TOOLS = ('debugfs', 'mke2fs', 'e2fsck', 'mkfs.vfat', 'mmd', 'mcopy', 'mtype', 'sfdisk', 'img2simg',
         'simg2img', 'blkid')
SECTOR = 4096
ESP = 2048 * SECTOR
CARRIER = 62464 * SECTOR
CARRIER_OPTIONS = ('pmos_rootfsopts=defaults', 'systemd.gpt_auto=0', 'systemd.confext=0', 'systemd.sysext=0')
FILES = {
    'boot/linux.efi': b'zboot kernel',
    'boot/initramfs': b'initramfs',
    'usr/lib/systemd/boot/efi/systemd-bootaa64.efi': b'systemd-boot',
}


def carrier_conf(name, dtb, device):
    return (f'CARRIER_NAME={name}\nCARRIER_DTB={dtb}\n'
            f'CARRIER_CMDLINE=/usr/lib/kernel-cmdline.d/50-device-{device}.conf\n').encode()


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


@unittest.skipUnless(all(shutil.which(t) for t in TOOLS), 'needs e2fsprogs, dosfstools, mtools, sfdisk, '
                     'android-tools')
class UserdataImage:
    NAME = DEVICE = DTB = ''

    @classmethod
    def setUpClass(cls):
        cls.cmdline = PACKAGES / f'device-{cls.DEVICE}/kernel-cmdline.conf'
        cls.tmp = Path(tempfile.mkdtemp())
        tree = cls.tmp / 'tree'
        files = {**FILES, f'boot/dtbs/{cls.DTB}': b'board dtb',
                 'usr/share/marathon/carrier.conf': carrier_conf(cls.NAME, cls.DTB, cls.DEVICE)}
        for rel, data in files.items():
            (tree / rel).parent.mkdir(parents=True, exist_ok=True)
            (tree / rel).write_bytes(data)
        conf = tree / f'usr/lib/kernel-cmdline.d/50-device-{cls.DEVICE}.conf'
        conf.parent.mkdir(parents=True)
        shutil.copy(cls.cmdline, conf)
        cls.root = cls.tmp / 'root-test-1.ext4'
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
        self.assertEqual(self.esp(f'/dtbs/{self.DTB}'), b'board dtb')
        self.assertEqual(self.esp('/EFI/BOOT/BOOTAA64.EFI'),
                         FILES['usr/lib/systemd/boot/efi/systemd-bootaa64.efi'])

    def test_entry_boots_the_root_file_on_this_carrier(self):
        entry_name = f'marathon-{self.NAME}-root-test-1.conf'
        self.assertEqual(self.esp('/loader/loader.conf'), f'default {entry_name}\n'.encode())
        entry = self.esp(f'/loader/entries/{entry_name}').decode()
        self.assertIn('linux /linux.efi\n', entry)
        self.assertIn('initrd /initramfs\n', entry)
        self.assertIn(f'devicetree /dtbs/{self.DTB}\n', entry)
        options = re.search(r'^options (.*)$', entry, re.M).group(1).split()
        package = [w for w in self.cmdline.read_text().split() if not w.startswith('#')]
        package += [o for o in CARRIER_OPTIONS if o not in package]
        self.assertEqual(options[:len(package)], package)
        self.assertEqual(options[len(package):], [
            f'pmos_boot_uuid={self.blkid(ESP, "UUID")}',
            f'pmos_root_uuid={self.blkid(CARRIER, "UUID")}',
            f'{self.NAME}.rootfs_file=/var/lib/marathon/images/root-test-1.ext4',
        ])

    def test_carrier_holds_the_root_image_for_root_only(self):
        dump = self.tmp / 'dumped.ext4'
        self.carrier(f'dump /var/lib/marathon/images/root-test-1.ext4 {dump}')
        self.assertEqual(dump.read_bytes(), self.root.read_bytes())
        listing = self.carrier('ls -l /var/lib/marathon/images')
        self.assertRegex(listing, r'100600 \(1\)\s+0\s+0\s+16777216 .* root-test-1.ext4')
        self.assertRegex(self.carrier('ls -l /var/lib/marathon'), r'40700 \(2\)\s+0\s+0 .* images')
        self.assertEqual(self.carrier('cat /usr/lib/os-release'),
                         f'NAME="Marathon {self.NAME.upper()} carrier"\nID=marathon-{self.NAME}-carrier\n')
        run('e2fsck', '-fn', f'{self.raw}?offset={CARRIER}')

    def test_carrier_options_once_each(self):
        entry = self.esp(f'/loader/entries/marathon-{self.NAME}-root-test-1.conf').decode()
        options = re.search(r'^options (.*)$', entry, re.M).group(1).split()
        for o in CARRIER_OPTIONS:
            self.assertEqual(options.count(o), 1, o)

    def test_root_is_untouched(self):
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o644)


class Q25(UserdataImage, unittest.TestCase):
    NAME, DEVICE, DTB = 'q25', 'zinwa-q25', 'mediatek/mt8781-zinwa-q25.dtb'


class MP01(UserdataImage, unittest.TestCase):
    NAME, DEVICE, DTB = 'mp01', 'minimal-mp01', 'mediatek/mt6789-minimal-mp01.dtb'


@unittest.skipUnless(all(shutil.which(t) for t in TOOLS), 'needs the image tools')
class Refusals(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.board = {'boot/dtbs/mediatek/mt8781-zinwa-q25.dtb': b'board dtb',
                      'usr/share/marathon/carrier.conf': carrier_conf('q25', 'mediatek/mt8781-zinwa-q25.dtb', 'zinwa-q25'),
                      'usr/lib/kernel-cmdline.d/50-device-zinwa-q25.conf': b'console=tty0\n'}

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
        r, out = self.build(self.make('root-a.ext4', {**files, **self.board}))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('has no /boot/initramfs', r.stderr)
        self.assertFalse(out.exists())
        self.assertEqual([p.name for p in self.tmp.iterdir() if p.name.startswith('.carrier')], [])

    def test_root_without_a_carrier_conf(self):
        files = {**FILES, 'boot/dtbs/mediatek/mt8781-zinwa-q25.dtb': b'board dtb'}
        r, out = self.build(self.make('root-a.ext4', files))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('has no /usr/share/marathon/carrier.conf', r.stderr)
        self.assertFalse(out.exists())

    def test_carrier_conf_that_climbs_out_of_the_dtbs(self):
        board = {**self.board, 'usr/share/marathon/carrier.conf': carrier_conf('q25', '../linux.efi', 'zinwa-q25')}
        r, out = self.build(self.make('root-a.ext4', {**FILES, **board}))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('bad CARRIER_DTB', r.stderr)
        self.assertFalse(out.exists())

    def test_name_that_is_not_a_loader_token(self):
        r, out = self.build(self.make('root a.ext4', {**FILES, **self.board}))
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(out.exists())


if __name__ == '__main__':
    unittest.main()
