#!/usr/bin/env python3
"""Q25 session policy must survive greetd's empty PAM environment."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / 'packaging/packages/device-zinwa-q25-marathon'
GPU = ROOT / 'packaging/packages/q25-gpu-render'
LAUNCHER = ROOT / 'packaging/packages/marathon-shell/marathon-shell-session'


class Q25Session(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.config = self.dir / 'q25-session.conf'
        stub = self.dir / 'normal-session'
        stub.write_text('#!' + sys.executable + '\nimport json,os,sys\nprint(json.dumps({"env":dict(os.environ),"args":sys.argv[1:]}))\n')
        stub.chmod(0o755)
        replacements = {
            '/etc/marathon/q25-session.conf': str(self.config),
            '/usr/bin/marathon-shell-session': str(stub),
            '/run/q25-gpu/ready': str(self.dir / 'ready'),
            '/etc/q25/gpu-disabled': str(self.dir / 'disabled'),
            '/sys/devices/platform/soc/13000000.gpu/power/control': str(self.dir / 'power'),
            '/sys/class/devfreq/13000000.gpu/cur_freq': str(self.dir / 'frequency'),
            '/etc/q25/keyboard-layout-preview.env': str(self.dir / 'keyboard.env'),
            '/usr/libexec/marathon/q25-shell-session.gpu': str(self.dir / 'gpu'),
            '/usr/libexec/marathon/q25-shell-session.software': str(self.dir / 'software'),
        }
        for src, dest in [(PROFILE / 'q25-shell-session', 'wrapper'),
                          (PROFILE / 'q25-shell-session.software', 'software'),
                          (GPU / 'q25-shell-session.gpu', 'gpu')]:
            text = src.read_text()
            for old, new in replacements.items():
                text = text.replace(old, new)
            out = self.dir / dest
            out.write_text(text)
            out.chmod(0o755)
        self.wrapper = self.dir / 'wrapper'

    def ready(self):
        (self.dir / 'ready').write_text('ready\n')
        (self.dir / 'power').write_text('on\n')
        (self.dir / 'frequency').write_text('390000000\n')

    def test_gpu_ready_selects_accepted_environment_and_preserves_arguments(self):
        self.ready()
        result = self.run_wrapper()
        env = result['env']
        self.assertEqual(env['QT_QPA_PLATFORM'], 'eglfs')
        self.assertEqual(env['QT_QPA_EGLFS_KMS_CONFIG'], '/etc/q25/eglfs-kms.json')
        self.assertEqual(env['PAN_MESA_DEBUG'], 'noafbc')
        self.assertEqual(env['MARATHON_FORCE_DPI'], '240')
        self.assertEqual(env['LIBGL_DRIVERS_PATH'], '/usr/lib/q25-gpu/dri:/usr/lib/dri')
        self.assertNotIn('QT_QUICK_BACKEND', env)
        self.assertEqual(result['args'], ['argument with spaces'])

    def test_failed_readiness_conditions_choose_software(self):
        for failure in ['disabled', 'power', 'frequency', 'gpu']:
            with self.subTest(failure=failure):
                self.ready()
                if failure == 'disabled':
                    (self.dir / 'disabled').touch()
                elif failure == 'power':
                    (self.dir / 'power').write_text('auto\n')
                elif failure == 'frequency':
                    (self.dir / 'frequency').write_text('467000000\n')
                else:
                    (self.dir / 'gpu').chmod(0o644)
                self.assertEqual(self.run_wrapper()['env']['QT_QUICK_BACKEND'], 'software')
                (self.dir / 'disabled').unlink(missing_ok=True)
                (self.dir / 'gpu').chmod(0o755)

    def test_optional_keyboard_hook_is_preserved(self):
        self.ready()
        (self.dir / 'keyboard.env').write_text('XKB_DEFAULT_LAYOUT=q25\n')
        self.assertEqual(self.run_wrapper()['env']['XKB_DEFAULT_LAYOUT'], 'q25')
        (self.dir / 'ready').unlink()
        self.assertEqual(self.run_wrapper()['env']['QT_QUICK_BACKEND'], 'software')
        self.assertEqual(self.run_wrapper()['env']['XKB_DEFAULT_LAYOUT'], 'q25')

    def run_wrapper(self):
        result = subprocess.run(['sh', str(self.wrapper), 'argument with spaces'],
                                env={'PATH': '/usr/bin:/bin'}, text=True,
                                capture_output=True, check=True)
        return json.loads(result.stdout)

    def test_empty_pam_environment_gets_software_policy_and_delegates(self):
        r = self.run_wrapper()
        for k, v in {'QT_QPA_PLATFORM': 'linuxfb:fb=/dev/fb0', 'QT_QUICK_BACKEND': 'software',
                     'QSG_RENDER_LOOP': 'basic', 'QT_QPA_FB_FORCE_FULLSCREEN': '1',
                     'MARATHON_FORCE_DPI': '240'}.items():
            self.assertEqual(r['env'].get(k), v, k)
        self.assertEqual(r['args'], ['argument with spaces'])
        self.assertNotIn('MARATHON_STARTUP_TIMING', r['env'])

    def test_diagnostics_only_from_boolean_allowlist(self):
        marker = self.dir / 'must-not-execute'
        self.config.write_text('MARATHON_STARTUP_TIMING=1\nMARATHON_PRESENT_STATS=1\n'
                               'MARATHON_FRAME_TIMING=0\nQT_QPA_PLATFORM=eglfs\n'
                               f'UNEXPECTED=$(touch {marker})\n')
        env = self.run_wrapper()['env']
        self.assertEqual(env['MARATHON_STARTUP_TIMING'], '1')
        self.assertEqual(env['MARATHON_PRESENT_STATS'], '1')
        self.assertEqual(env['MARATHON_FRAME_TIMING'], '0')
        self.assertEqual(env['QT_QPA_PLATFORM'], 'linuxfb:fb=/dev/fb0')
        self.assertNotIn('UNEXPECTED', env)
        self.assertFalse(marker.exists())

    def test_both_greetd_sessions_select_wrapper(self):
        c = tomllib.loads((PROFILE / 'greetd-q25.toml').read_text())
        for session in ['default_session', 'initial_session']:
            self.assertEqual(c[session]['command'], '/usr/libexec/marathon/q25-shell-session')
            self.assertEqual(c[session]['user'], 'user')

    def test_normal_launcher_respects_basic_and_defaults_threaded(self):
        line = next(l for l in LAUNCHER.read_text().splitlines() if l.startswith('export QSG_RENDER_LOOP='))
        for preset, expected in [('basic', 'basic'), ('', 'threaded')]:
            env = {'PATH': '/usr/bin:/bin'}
            if preset:
                env['QSG_RENDER_LOOP'] = preset
            result = subprocess.check_output(['sh', '-c', line + '\nprintf %s "$QSG_RENDER_LOOP"'], env=env, text=True)
            self.assertEqual(result, expected)


if __name__ == '__main__':
    unittest.main()
