#!/usr/bin/env python3
"""marathon-carrier-root-install: the Q25's q25-root-install tests, run on the
carrier one with the Q25's carrier.conf, and its names on another carrier."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'packaging/packages/marathon-carrier/marathon-carrier-root-install'
Q25_CONF = ('CARRIER_NAME=q25\nCARRIER_DTB=mediatek/mt8781-zinwa-q25.dtb\n'
            'CARRIER_CMDLINE=/usr/lib/kernel-cmdline.d/50-device-zinwa-q25.conf\n')

_conf_dir = tempfile.TemporaryDirectory()
_q25_conf = Path(_conf_dir.name) / 'carrier.conf'
_q25_conf.write_text(Q25_CONF)

_spec = importlib.util.spec_from_file_location('q25_root_install', REPO / 'scripts/q25/test_q25_root_install.py')
q25 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(q25)
q25.SCRIPT = SCRIPT


class _Subprocess:
    """subprocess for the Q25 tests: the script gets --conf ahead of the rest."""
    def __getattr__(self, name):
        return getattr(subprocess, name)

    @staticmethod
    def run(cmd, *args, **kwargs):
        if cmd[:2] == ['sh', str(SCRIPT)]:
            cmd = cmd[:2] + ['--conf', str(_q25_conf)] + cmd[2:]
        return subprocess.run(cmd, *args, **kwargs)


q25.subprocess = _Subprocess()
Q25RootInstall = q25.RootInstall
Q25Arm = q25.Arm


class OtherCarrier(unittest.TestCase):
    def test_entries_and_token_follow_the_carrier_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            conf = root / 'carrier.conf'
            conf.write_text('CARRIER_NAME=jp2601\nCARRIER_DTB=mediatek/mt6858-jolla-jp2601.dtb\n'
                            'CARRIER_CMDLINE=/usr/lib/kernel-cmdline.d/50-device-jolla-jp2601.conf\n')
            esp, carrier = root / 'esp', root / 'carrier'
            (esp / 'loader/entries').mkdir(parents=True)
            (esp / 'loader/loader.conf').write_text('default marathon-jp2601-old.conf\n')
            (esp / 'loader/entries/marathon-jp2601-old.conf').write_text(
                'title Marathon\nlinux /linux.efi\noptions console=tty0 '
                'jp2601.rootfs_file=/var/lib/marathon/images/old.ext4\n')
            (carrier / 'var/lib/marathon/images').mkdir(parents=True)
            image = carrier / 'new-1.ext4'
            image.write_bytes(b'root')
            subprocess.run(['sh', str(SCRIPT), '--conf', str(conf), '--esp', str(esp), '--carrier', str(carrier),
                            '--no-remount', '--counted', 'install', str(image)], check=True, capture_output=True)
            new = (esp / 'loader/entries/marathon-jp2601-b-new-1+3.conf').read_text()
            self.assertIn('jp2601.rootfs_file=/var/lib/marathon/images/new-1.ext4', new)
            self.assertTrue(new.endswith('sort-key marathon-jp2601\nversion new-1\n'))
            self.assertTrue((esp / 'loader/entries/marathon-jp2601-a-fallback.conf').exists())
            self.assertIn('default marathon-jp2601-*', (esp / 'loader/loader.conf').read_text())

    def test_refuses_a_bad_carrier_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / 'carrier.conf'
            conf.write_text('CARRIER_NAME=../x\n')
            r = subprocess.run(['sh', str(SCRIPT), '--conf', str(conf), 'arm'], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('CARRIER_NAME', r.stderr)


if __name__ == '__main__':
    unittest.main()
