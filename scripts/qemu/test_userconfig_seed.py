#!/usr/bin/env python3
"""Exercise the generated pipeline payload, with only deployment paths/IDs relocated.
Defaults to replaying checked-in postinst patches only (no bootstrap/network/build).
Optionally validate a generated pipeline: --postinst BUILD/duranium/mkosi.images/base/mkosi.postinst
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

POSTINST = None


def payload(name):
    pattern = r'cat > "\$BUILDROOT/' + re.escape(name) + r'" <<\x27?EOF\x27?\n(.*?)\nEOF'
    match = re.search(pattern, POSTINST.read_text(), re.S)
    if not match:
        raise AssertionError(f"generated payload not found: {name}")
    return match.group(1) + "\n"


class UserConfigSeed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if POSTINST is None:
            raise unittest.SkipTest("requires --postinst from a bootstrapped pipeline")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home/user'
        self.factory = self.root / 'usr/share/factory/home/user'
        self.defaults = {
            '.config/marathon-os/Marathon Shell.conf': b'[system]\nfirstRunComplete=false\n',
            '.config/marathon/app-permissions.json': b'{}\n',
            '.ssh/authorized_keys': b'ssh-ed25519 factory-fixture-key\n',
        }
        for name, data in self.defaults.items():
            p = self.factory / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        etc = self.root / 'etc'
        etc.mkdir()
        (etc / 'passwd').write_text(f'user:x:{os.getuid()}:{os.getgid()}::/home/user:/bin/sh\n')
        (etc / 'group').write_text(f'user:x:{os.getgid()}:\n')
        conf = self.root / 'usr/lib/tmpfiles.d/marathon-home.conf'
        conf.parent.mkdir(parents=True)
        conf.write_text(payload('usr/lib/tmpfiles.d/marathon-home.conf').replace('$USER_NAME', 'user'))
        # Run the actual generated shell body. Only fixed deployment paths and
        # account IDs change; all copy/guard/install logic remains untouched.
        script = payload('usr/libexec/marathon-userconfig-seed')
        script = script.replace('USER_NAME=user', f'USER_NAME={os.getuid()}')
        script = script.replace('HOME_DIR=/home/$USER_NAME', f'HOME_DIR="{self.home}"')
        script = script.replace('FACTORY="/usr/share/factory/home/$USER_NAME"', f'FACTORY="{self.factory}"')
        script = script.replace('-g $USER_NAME', f'-g {os.getgid()}')
        script = script.replace('chown $USER_NAME:$USER_NAME', f'chown {os.getuid()}:{os.getgid()}')
        self.script = self.root / 'seed.sh'
        self.script.write_text(script)

    def seed(self):
        subprocess.run(['sh', str(self.script)], check=True, capture_output=True)

    def tmpfiles(self):
        subprocess.run(['systemd-tmpfiles', '--root=' + str(self.root), '--create', 'marathon-home.conf'],
                       check=True, capture_output=True)

    def existing(self):
        values = {
            '.config/marathon-os/Marathon Shell.conf': b'[system]\nfirstRunComplete=true\nowner=existing\n',
            '.config/marathon/app-permissions.json': b'{"keep":true}\n',
            '.config/marathon/quickpin.conf': b'opaque-existing-pin-fixture\n',
            '.ssh/authorized_keys': b'ssh-ed25519 existing-user-fixture-key\n',
        }
        for name, value in values.items():
            p = self.home / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(value)
            p.chmod(0o600)
        return values

    def test_migrated_home_without_marker_survives_seed_and_repeated_boot(self):
        values = self.existing()
        self.seed()
        self.tmpfiles()
        self.tmpfiles()
        self.seed()
        for name, value in values.items():
            self.assertEqual((self.home / name).read_bytes(), value, name)
        self.assertTrue((self.home / '.config/marathon/.seeded').is_file())

    def test_fresh_home_gets_missing_defaults_and_developer_key(self):
        self.seed()
        self.tmpfiles()
        for name, value in self.defaults.items():
            p = self.home / name
            self.assertEqual(p.read_bytes(), value, name)
            self.assertEqual(p.stat().st_mode & 0o777, 0o600, name)
        self.assertFalse((self.home / '.config/marathon/quickpin.conf').exists())

    def test_partial_home_preserves_empty_config_and_seeds_missing_permissions(self):
        p = self.home / '.config/marathon-os/Marathon Shell.conf'
        p.parent.mkdir(parents=True)
        p.write_bytes(b'')
        self.seed()
        self.tmpfiles()
        self.assertEqual(p.read_bytes(), b'')
        self.assertEqual((self.home / '.config/marathon/app-permissions.json').read_bytes(), b'{}\n')

    def test_seeder_preserves_dangling_config_symlink(self):
        p = self.home / '.config/marathon-os/Marathon Shell.conf'
        p.parent.mkdir(parents=True)
        p.symlink_to('owner-managed-missing.conf')
        self.seed()
        self.assertTrue(p.is_symlink())
        self.assertEqual(str(p.readlink()), 'owner-managed-missing.conf')
        self.assertFalse((p.parent / 'owner-managed-missing.conf').exists())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--postinst', type=Path)
    args, rest = parser.parse_known_args()
    POSTINST = args.postinst
    generated = None
    if POSTINST is None:
        # Reconstruct the actual pipeline file from its checked-in patch series.
        # This runs git apply only, never bootstrap or postinst itself.
        generated = tempfile.TemporaryDirectory()
        root = Path(__file__).resolve().parents[2]
        target = 'mkosi.images/base/mkosi.postinst'
        for patch in sorted((root / 'packaging/pipeline-patches').glob('*.patch')):
            if f'diff --git a/{target} b/{target}' in patch.read_text():
                subprocess.run(['git', 'apply', '--unsafe-paths', '--include=' + target,
                                str(patch)], cwd=generated.name, check=True, capture_output=True)
        POSTINST = Path(generated.name) / target
        if not POSTINST.is_file():
            parser.error('pipeline patches did not create the base postinst')
    if not shutil.which('systemd-tmpfiles'):
        parser.error('systemd-tmpfiles is required for the actual repeated-boot copy test')
    unittest.main(argv=[__file__, *rest])
