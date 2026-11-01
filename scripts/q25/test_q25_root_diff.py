#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('q25_root_diff', HERE / 'q25-root-diff.py')
rd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rd)

APK = 'P:base\nV:1-r0\n\nP:q25-modem\nV:2-r1\n'


def local_manifest(root):
    out = subprocess.run(['python3', '-I', '-B', '-c', rd.MANIFEST_PY, str(root), *rd.FILE_TOPS, *rd.UNIT_TOPS],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)


class RootDiff(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'root'
        r = self.root
        for d in ('etc/systemd/system/multi-user.target.wants', 'usr/libexec/sub', 'usr/lib/apk/db',
                  'usr/lib/systemd/system/sockets.target.wants'):
            (r / d).mkdir(parents=True)
        (r / 'usr/lib/apk/db/installed').write_text(APK)
        (r / 'etc/hostname').write_text('marathon\n')
        (r / 'etc/big').write_bytes(os.urandom(300_000))
        (r / 'usr/libexec/sub/tool').write_text('#!/bin/sh\n')
        (r / 'usr/libexec/sub/tool').chmod(0o755)
        os.symlink('/usr/lib/systemd/system/a.service', r / 'etc/systemd/system/multi-user.target.wants/a.service')
        os.symlink('/dev/null', r / 'etc/systemd/system/systemd-repart.service')
        os.symlink('../b.socket', r / 'usr/lib/systemd/system/sockets.target.wants/b.socket')
        os.symlink('x' * 80, r / 'etc/longlink')
        for i in range(200):
            (r / f'etc/f{i:03}').write_text(str(i))

    def tearDown(self):
        self.tmp.cleanup()

    def test_ext4_reader_matches_the_tree_it_was_built_from(self):
        image = Path(self.tmp.name) / 'root.ext4'
        subprocess.run(['mkfs.ext4', '-q', '-b', '4096', '-E', 'root_owner=0:0', '-d', str(self.root),
                        str(image), '16M'], check=True)
        got, want = rd.load(str(image)), local_manifest(self.root)
        uid, gid = os.getuid(), os.getgid()
        # mke2fs -d copies the builder's ownership; compare everything else.
        self.assertEqual({k: v[:2] + v[4:] for k, v in got['files'].items()},
                         {k: v[:2] + v[4:] for k, v in want['files'].items()})
        self.assertTrue(all(v[2:4] == [uid, gid] for v in got['files'].values()))
        self.assertEqual(got['apk'], APK)
        self.assertEqual(len(got['files']), 207)

    def test_units_and_files_are_split(self):
        units, files = rd.split_units(local_manifest(self.root)['files'])
        self.assertEqual(units, {'system multi-user.target.wants/a.service': 'a.service',
                                 'system mask/systemd-repart.service': 'null',
                                 'system sockets.target.wants/b.socket': 'b.socket'})
        self.assertIn('/usr/libexec/sub/tool', files)
        self.assertNotIn('/etc/systemd/system/systemd-repart.service', files)

    def test_every_difference_needs_a_rule(self):
        live = local_manifest(self.root)
        image = {'files': dict(live['files']), 'apk': APK.replace('2-r1', '3-r0')}
        del image['files']['/etc/hostname']
        del image['files']['/etc/systemd/system/multi-user.target.wants/a.service']
        image['files']['/usr/libexec/sub/tool'] = ['f', 0o644] + live['files']['/usr/libexec/sub/tool'][2:]
        records = list(rd.diff(live, image))
        self.assertEqual([r[:3] for r in records], [
            ('packages', 'changed', 'q25-modem'),
            ('units', 'removed', 'system multi-user.target.wants/a.service'),
            ('files', 'removed', '/etc/hostname'),
            ('files', 'changed', '/usr/libexec/sub/tool'),
        ])
        self.assertEqual(records[3][3], 'mode 0o755 -> 0o644')
        rules_path = Path(self.tmp.name) / 'rules.toml'
        rules_path.write_text('[[rule]]\ncheck = "files"\nkind = "removed"\nmatch = "/etc/host*"\nreason = "id"\n')
        rules = rd.load_rules([str(rules_path)])
        self.assertEqual([rd.explain(r, rules) for r in records], [None, None, 'id', None])


if __name__ == '__main__':
    unittest.main()
