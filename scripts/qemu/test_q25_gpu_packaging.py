#!/usr/bin/env python3
"""Bounded source contracts for the accepted Q25 GPU startup package; no builds."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
GPU = ROOT / 'packaging/packages/q25-gpu-render'
DEVICE = ROOT / 'packaging/packages/device-zinwa-q25-marathon'


class Packaging(unittest.TestCase):
    def test_manifest_matches_exact_assets_and_compressed_modules(self):
        manifest = dict(line.split(None, 1)[::-1] for line in
                        (GPU / 'GPU-SHA256SUMS').read_text().splitlines())
        self.assertEqual(len(manifest), 6)
        for module in ['q25-mfg-only-v2', 'gpu-sched', 'panfrost']:
            raw = subprocess.check_output(['zstd', '-q', '-d', '-c', str(GPU / (module + '.ko.zst'))])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), manifest['/usr/lib/q25-gpu/' + module + '.ko'])
        for name, dest in [('simpledrm_dri.so', '/usr/lib/q25-gpu/dri/simpledrm_dri.so'),
                           ('eglfs-kms.json', '/etc/q25/eglfs-kms.json')]:
            self.assertEqual(hashlib.sha256((GPU / name).read_bytes()).hexdigest(), manifest[dest])
        self.assertEqual(manifest['/etc/q25/eglfs-kms.json'],
                         'ed32c467bcf591194d23ea136510b558abbc95f61a83b0881b59f06d69a2802d')
        self.assertEqual(manifest['/usr/lib/q25-gpu/dri/simpledrm_dri.so'],
                         '68fa4b2a5d0b795a1fa273531eff68a27d8c88895df328b10fcc20a9f64e069b')

    def test_package_source_checksums(self):
        for package in [GPU, DEVICE]:
            apk = (package / 'APKBUILD').read_text()
            names = re.search(r'\nsource="([^"]+)"', apk).group(1).split()
            sums = dict(line.split(None, 1)[::-1] for line in
                        re.search(r'\nsha512sums="([^"]+)"', apk).group(1).strip().splitlines())
            self.assertEqual(set(names), set(sums))
            for name in names:
                if name == 'device-profile.conf' and not (package / name).exists():
                    content = subprocess.check_output(['python3', 'tools/devices/devices.py',
                                                       'profile', 'device-zinwa-q25-marathon'], cwd=ROOT)
                else:
                    content = (package / name).read_bytes()
                self.assertEqual(hashlib.sha512(content).hexdigest(), sums[name], name)

    def test_one_guarded_provider_with_cleanup_and_optional_dependency(self):
        unit = (GPU / 'q25-gpu-prepare.service').read_text()
        self.assertIn('Before=greetd.service', unit)
        self.assertIn('TimeoutStopSec=2s', unit)
        self.assertIn('ExecStopPost=/bin/rm -f /run/q25-gpu/ready', unit)
        dropin = (GPU / '80-q25-gpu-prepare.conf').read_text()
        self.assertIn('Wants=q25-gpu-prepare.service', dropin)
        self.assertIn('After=q25-gpu-prepare.service', dropin)
        self.assertNotIn('Requires=', dropin)
        self.assertFalse((GPU / 'q25-gpu-provider.service').exists())
        for name in ['q25-gpu-render.post-install', 'q25-gpu-render.post-upgrade']:
            text = (GPU / name).read_text()
            self.assertIn('q25-gpu-provider.service', text)
            self.assertNotIn('insmod', text)
            self.assertNotIn('systemctl start', text)
        apk = (GPU / 'APKBUILD').read_text()
        self.assertNotIn('multi-user.target.wants', apk)
        self.assertNotIn('/usr/local', apk)
        self.assertIn('mesa=26.2.6-r0', apk)
        self.assertIn('linux-postmarketos-mediatek-g99=7.0-r1000', apk)

    def test_guard_checks_manifest_before_loading_modules(self):
        text = (GPU / 'q25-gpu-prepare').read_text()
        self.assertLess(text.index('sha256sum -c'), text.index('insmod'))
        self.assertIn('7.0.0-q25-cfi-test', text)
        self.assertIn('q25.gpu=off', text)
        self.assertIn('675000', text)
        self.assertIn('775000', text)
        self.assertNotIn('/dev/mem', text)
        self.assertEqual(json.loads((GPU / 'eglfs-kms.json').read_text())['outputs'][0]['mode'], 'current')


if __name__ == '__main__':
    unittest.main()
