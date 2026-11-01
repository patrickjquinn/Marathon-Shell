#!/usr/bin/env python3
"""Diff a Q25 root image against the live phone root (Q25-IMAGE-PLAN §3.3).

Compares the apk package set, systemd unit enablement and the /etc and
/usr/libexec file lists (type, mode, owner, sha256 or link target). Every
difference must match a rule in an --explain TOML file; anything else is
reported as UNEXPLAINED and the exit status is 1.

  q25-root-diff.py snapshot live.json        read-only capture over Q25_SSH
  q25-root-diff.py diff --live live.json --image new.ext4 --explain rules.toml

--live and --image each take a snapshot .json or an ext4 image file.
"""
import argparse
import fnmatch
import hashlib
import json
import os
import re
import shlex
import struct
import subprocess
import sys
import tomllib

FILE_TOPS = ('/etc', '/usr/libexec')
UNIT_TOPS = ('/usr/lib/systemd/system', '/usr/lib/systemd/user')
APK_DB = '/usr/lib/apk/db/installed'

# argv: ROOT TOP... Runs on the phone with -I -B so it never writes bytecode
# into the root.
MANIFEST_PY = r'''
import hashlib, json, os, stat, sys
out = {}
def walk(path, dev):
    for e in sorted(os.scandir(path), key=lambda e: e.name):
        st = e.stat(follow_symlinks=False)
        if st.st_dev != dev:
            continue
        rec = [None, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid, '']
        if stat.S_ISLNK(st.st_mode):
            rec[0], rec[4] = 'l', os.readlink(e.path)
        elif stat.S_ISREG(st.st_mode):
            h = hashlib.sha256()
            with open(e.path, 'rb') as f:
                for b in iter(lambda: f.read(1 << 20), b''):
                    h.update(b)
            rec[0], rec[4] = 'f', h.hexdigest()
        elif stat.S_ISDIR(st.st_mode):
            walk(e.path, dev)
            continue
        else:
            rec[0] = 'o'
        out[e.path[len(root):]] = rec
root = sys.argv[1].rstrip('/')
for top in sys.argv[2:]:
    if os.path.isdir(root + top):
        walk(root + top, os.lstat(root + top).st_dev)
apk = open(root + '/usr/lib/apk/db/installed').read()
print(json.dumps({'files': out, 'apk': apk}))
'''


class Ext4:
    """Read-only ext4 walker: enough for extent-mapped, non-inline images."""

    def __init__(self, f):
        self.f = f
        sb = self.read(1024, 1024)
        if struct.unpack_from('<H', sb, 56)[0] != 0xEF53:
            raise SystemExit(f'{f.name}: not ext4')
        self.bs = 1024 << struct.unpack_from('<I', sb, 24)[0]
        self.first_data_block = struct.unpack_from('<I', sb, 20)[0]
        self.ipg = struct.unpack_from('<I', sb, 40)[0]
        self.isize = struct.unpack_from('<H', sb, 88)[0]
        incompat = struct.unpack_from('<I', sb, 96)[0]
        self.dsize = struct.unpack_from('<H', sb, 254)[0] if incompat & 0x80 else 32

    def read(self, off, n):
        self.f.seek(off)
        return self.f.read(n)

    def inode(self, ino):
        group, idx = divmod(ino - 1, self.ipg)
        gd = self.read((self.first_data_block + 1) * self.bs + group * self.dsize, self.dsize)
        table = struct.unpack_from('<I', gd, 8)[0]
        if self.dsize >= 64:
            table |= struct.unpack_from('<I', gd, 0x28)[0] << 32
        raw = self.read(table * self.bs + idx * self.isize, self.isize)
        mode, uid, size, gid, flags = (struct.unpack_from('<H', raw, 0)[0], struct.unpack_from('<H', raw, 2)[0],
                                      struct.unpack_from('<I', raw, 4)[0], struct.unpack_from('<H', raw, 24)[0],
                                      struct.unpack_from('<I', raw, 32)[0])
        size |= struct.unpack_from('<I', raw, 108)[0] << 32
        uid |= struct.unpack_from('<H', raw, 120)[0] << 16
        gid |= struct.unpack_from('<H', raw, 122)[0] << 16
        if flags & 0x10000000:
            raise SystemExit(f'inode {ino}: inline data is not supported')
        return mode, uid, gid, size, flags, raw[40:100]

    def extents(self, node):
        magic, entries, _, depth = struct.unpack_from('<HHHH', node, 0)
        if magic != 0xF30A:
            raise SystemExit('bad extent header')
        for i in range(entries):
            e = node[12 + 12 * i:24 + 12 * i]
            if depth:
                leaf = struct.unpack_from('<I', e, 4)[0] | struct.unpack_from('<H', e, 8)[0] << 32
                yield from self.extents(self.read(leaf * self.bs, self.bs))
            else:
                lblk, length, hi, lo = struct.unpack_from('<IHHI', e, 0)
                yield lblk, length, (hi << 32) | lo

    def data(self, ino):
        _, _, _, size, flags, block = self.inode(ino)
        if not flags & 0x80000:
            raise SystemExit(f'inode {ino}: block-mapped files are not supported')
        pos = 0
        for lblk, length, pblk in sorted(self.extents(block)):
            if lblk * self.bs > pos:
                yield bytes(min(lblk * self.bs, size) - pos)
                pos = lblk * self.bs
            n = min((length & 0x7FFF if length > 32768 else length) * self.bs, size - pos)
            if n <= 0:
                break
            yield bytes(n) if length > 32768 else self.read(pblk * self.bs, n)
            pos += n
        if pos < size:
            yield bytes(size - pos)

    def entries(self, ino):
        buf = b''.join(self.data(ino))
        for base in range(0, len(buf), self.bs):
            pos = base
            while pos < base + self.bs:
                child, rec_len, name_len = struct.unpack_from('<IHB', buf, pos)
                if rec_len == 0:
                    break
                name = buf[pos + 8:pos + 8 + name_len].decode('utf-8', 'surrogateescape')
                if child and name not in ('.', '..'):
                    yield name, child
                pos += rec_len

    def lookup(self, path):
        ino = 2
        for part in path.strip('/').split('/'):
            ino = dict(self.entries(ino)).get(part)
            if ino is None:
                return None
        return ino

    def walk(self, path, out):
        for name, ino in sorted(self.entries(self.lookup(path))):
            child = f'{path}/{name}'
            mode, uid, gid, size, flags, block = self.inode(ino)
            kind = mode & 0xF000
            rec = [None, mode & 0o7777, uid, gid, '']
            if kind == 0x4000:
                self.walk(child, out)
                continue
            if kind == 0xA000:
                raw = block[:size] if size < 60 and not flags & 0x80000 else b''.join(self.data(ino))
                rec[0], rec[4] = 'l', raw.decode('utf-8', 'surrogateescape')
            elif kind == 0x8000:
                h = hashlib.sha256()
                for chunk in self.data(ino):
                    h.update(chunk)
                rec[0], rec[4] = 'f', h.hexdigest()
            else:
                rec[0] = 'o'
            out[child] = rec

    def snapshot(self):
        files = {}
        for top in FILE_TOPS + UNIT_TOPS:
            if self.lookup(top):
                self.walk(top, files)
        apk = b''.join(self.data(self.lookup(APK_DB))).decode()
        return {'files': files, 'apk': apk}


def phone_snapshot():
    ssh = shlex.split(os.environ.get('Q25_SSH', 'q25-ssh'))
    cmd = shlex.join(['python3', '-I', '-B', '-c', MANIFEST_PY, '/', *FILE_TOPS, *UNIT_TOPS])
    snap = json.loads(subprocess.run([*ssh, cmd], check=True, stdout=subprocess.PIPE).stdout)
    snap['boot_id'] = subprocess.run([*ssh, 'cat /proc/sys/kernel/random/boot_id'], check=True,
                                     stdout=subprocess.PIPE, text=True).stdout.strip()
    return snap


def load(path):
    if path.endswith('.json'):
        with open(path) as f:
            return json.load(f)
    with open(path, 'rb') as f:
        return Ext4(f).snapshot()


UNIT_LINK = re.compile(r'^/(?:etc|usr/lib)/systemd/(system|user)/(?:([^/]+\.(?:wants|requires|upholds))/)?([^/]+)$')


def split_units(files):
    """Return (units, rest): enablement symlinks keyed 'scope dir/unit', or 'scope mask/unit'."""
    units, rest = {}, {}
    for path, rec in files.items():
        m = UNIT_LINK.match(path)
        if m and rec[0] == 'l' and (m[2] or path.startswith('/etc/')):
            scope, deps, unit = m.groups()
            key = f'{scope} {deps}/{unit}' if deps else (
                f'{scope} mask/{unit}' if rec[4] == '/dev/null' else f'{scope} alias/{unit}')
            units[key] = os.path.basename(rec[4])
        elif path.startswith(tuple(t + '/' for t in FILE_TOPS)):
            rest[path] = rec
    return units, rest


def packages(apk):
    pkgs = {}
    for block in apk.split('\n\n'):
        fields = dict(line.split(':', 1) for line in block.splitlines() if line[1:2] == ':')
        if 'P' in fields:
            pkgs[fields['P']] = fields.get('V', '')
    return pkgs


def describe(a, b):
    if a[0] != b[0]:
        return f'type {a[0]} -> {b[0]}'
    names = ('type', 'mode', 'uid', 'gid', 'target' if a[0] == 'l' else 'sha256')
    parts = []
    for name, x, y in zip(names, a, b):
        if x != y:
            parts.append(f'{name} {oct(x) if name == "mode" else x} -> {oct(y) if name == "mode" else y}')
    return ', '.join(parts)


def diff_maps(check, live, image, detail=lambda a, b: f'{a} -> {b}'):
    for key in sorted(live.keys() | image.keys()):
        if key not in image:
            yield check, 'removed', key, ''
        elif key not in live:
            yield check, 'added', key, ''
        elif live[key] != image[key]:
            yield check, 'changed', key, detail(live[key], image[key])


def diff(live, image):
    live_units, live_files = split_units(live['files'])
    image_units, image_files = split_units(image['files'])
    yield from diff_maps('packages', packages(live['apk']), packages(image['apk']))
    yield from diff_maps('units', live_units, image_units)
    yield from diff_maps('files', live_files, image_files, describe)


def load_rules(paths):
    rules = []
    for path in paths:
        with open(path, 'rb') as f:
            for rule in tomllib.load(f).get('rule', []):
                kinds = rule.get('kind', ['added', 'removed', 'changed'])
                rule['kind'] = [kinds] if isinstance(kinds, str) else kinds
                rule['match'] = [rule['match']] if isinstance(rule['match'], str) else rule['match']
                rule['source'], rule['used'] = path, 0
                rules.append(rule)
    return rules


def explain(record, rules):
    check, kind, key, _ = record
    for rule in rules:
        if rule['check'] == check and kind in rule['kind'] and any(fnmatch.fnmatchcase(key, m) for m in rule['match']):
            rule['used'] += 1
            return rule['reason']
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sp = sub.add_parser('snapshot', help='capture the live root over Q25_SSH (read-only)')
    sp.add_argument('out')
    dp = sub.add_parser('diff', help='diff an image against the live root')
    dp.add_argument('--live', required=True)
    dp.add_argument('--image', required=True)
    dp.add_argument('--explain', action='append', default=[])
    dp.add_argument('--verbose', action='store_true', help='also print explained differences')
    args = ap.parse_args()

    if args.cmd == 'snapshot':
        snap = phone_snapshot()
        with open(args.out, 'w') as f:
            json.dump(snap, f, indent=0, sort_keys=True)
        return 0

    rules = load_rules(args.explain)
    counts = {}
    unexplained = 0
    for record in diff(load(args.live), load(args.image)):
        reason = explain(record, rules)
        check, kind, key, detail = record
        tally = counts.setdefault(check, [0, 0])
        tally[reason is None] += 1
        if reason is None:
            unexplained += 1
            print(f'UNEXPLAINED {check} {kind} {key} {detail}'.rstrip())
        elif args.verbose:
            print(f'explained   {check} {kind} {key} -- {reason}')
    for rule in rules:
        if not rule['used']:
            print(f'warning: rule never matched ({rule["source"]}): {rule["reason"]}', file=sys.stderr)
    for check in ('packages', 'units', 'files'):
        explained_n, unexplained_n = counts.get(check, [0, 0])
        print(f'{check}: {explained_n} explained, {unexplained_n} unexplained')
    return 1 if unexplained else 0


if __name__ == '__main__':
    sys.exit(main())
