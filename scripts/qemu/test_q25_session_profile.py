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
        text = (PROFILE / 'q25-shell-session').read_text()
        text = text.replace('/etc/marathon/q25-session.conf', str(self.config))
        text = text.replace('/usr/bin/marathon-shell-session', str(stub))
        self.wrapper = self.dir / 'wrapper'
        self.wrapper.write_text(text)

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
