#!/usr/bin/env python3
import hashlib
import importlib.machinery
import importlib.util
import json
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
_loader = importlib.machinery.SourceFileLoader('q25_install', str(HERE / 'q25-install'))
_spec = importlib.util.spec_from_loader('q25_install', _loader)
qi = importlib.util.module_from_spec(_spec)
_loader.exec_module(qi)

try:
    from mtkclient.Library.DA.xmlflash.xml_lib import DAXML
    from mtkclient.Library.DA.xmlflash.xml_cmd import XMLCmd
except ImportError:
    DAXML = None

BLOCK = 4096
MiB = 1 << 20


def sparse(chunks, blk=BLOCK):
    """An Android sparse image from ('raw', bytes) / ('fill', 4 bytes, blocks) / ('skip', blocks) / ('crc',)."""
    body, nblocks = b'', 0
    for c in chunks:
        if c[0] == 'raw':
            body += struct.pack('<HHII', qi.RAW, 0, len(c[1]) // blk, 12 + len(c[1])) + c[1]
            nblocks += len(c[1]) // blk
        elif c[0] == 'fill':
            body += struct.pack('<HHII', qi.FILL, 0, c[2], 16) + c[1]
            nblocks += c[2]
        elif c[0] == 'skip':
            body += struct.pack('<HHII', qi.DONT_CARE, 0, c[1], 12)
            nblocks += c[1]
        else:
            body += struct.pack('<HHII', qi.CRC32, 0, 0, 16) + b'\0' * 4
    return struct.pack('<IHHHHIIII', qi.SPARSE_MAGIC, 1, 0, 28, 12, blk, nblocks, len(chunks), 0) + body


def expand(chunks, blk=BLOCK):
    out = bytearray()
    for c in chunks:
        if c[0] == 'raw':
            out += c[1]
        elif c[0] == 'fill':
            out += c[1] * (c[2] * blk // 4)
        elif c[0] == 'skip':
            out += bytes(c[1] * blk)
    return bytes(out)


def lk_part(name, data, itype=0, last=0, align=16):
    head = bytearray(512)
    struct.pack_into('<II', head, 0, qi.LK_MAGIC, len(data))
    head[8:8 + len(name)] = name.encode()
    struct.pack_into('<IIIIIIII', head, 40, 0xFFFFFFFF, 0xFFFFFFFF, qi.LK_EXT, 512, 1, itype, last, align)
    return bytes(head) + data + bytes(-(512 + len(data)) % align)


def stock_lk():
    parts = []
    for name, size in (('lk', 3000), ('bl2_ext', 1000), ('aee', 700), ('lk_main_dtb', 500)):
        parts += [lk_part(name, bytes([len(name)]) * size), lk_part('cert1', b'c1' * 40, 0x2000000),
                  lk_part('cert2', b'c2' * 30, 0x2000002)]
    img = bytearray(b''.join(parts))
    struct.pack_into('<I', img, len(img) - len(parts[-1]) + 64, 1)
    return bytes(img) + bytes(qi.LK_SIZE - len(img))


UBOOT = b'U-Boot mt6789-q25 ' + bytes(range(256)) * 20

LAYOUT = {  # name: (offset, size), in a small stand-in for the Q25's GPT
    'misc': (8 * BLOCK, 64 << 10), 'seccfg': (1 * MiB, 64 << 10), 'boot_a': (2 * MiB, 128 << 10),
    'lk_a': (4 * MiB, qi.LK_SIZE), 'lk_b': (8 * MiB, qi.LK_SIZE), 'userdata': (16 * MiB, 64 * MiB)}


def gpt(layout, disk_end):
    entries = bytearray(128 * 128)
    for i, (name, (off, size)) in enumerate(layout.items()):
        e = memoryview(entries)[i * 128:(i + 1) * 128]
        e[:16] = b'\x11' * 16
        e[16:32] = bytes([i + 1]) * 16
        struct.pack_into('<QQ', e, 32, off // BLOCK, (off + size) // BLOCK - 1)
        name16 = name.encode('utf-16-le')
        e[56:56 + len(name16)] = name16
    head = bytearray(BLOCK)
    head[:8] = b'EFI PART'
    struct.pack_into('<Q', head, 32, disk_end // BLOCK - 1)
    struct.pack_into('<QII', head, 72, 2, 128, 128)
    return bytes(BLOCK) + bytes(head) + bytes(entries)


class Store:
    """The phone's storage: 4 KiB blocks, unwritten ones read as 0xAA."""

    def __init__(self):
        self.blocks = {}

    def write(self, off, data):
        for i in range(0, len(data), BLOCK):
            self.blocks[(off + i) // BLOCK] = bytes(data[i:i + BLOCK])

    def read(self, off, n):
        return b''.join(self.blocks.get(b, b'\xaa' * BLOCK) for b in range(off // BLOCK, (off + n) // BLOCK))


class FakePhone:
    def __init__(self, store, log, one_write=False, lose_on_read=None):
        self.store, self.log, self.one_write, self.lose_on_read = store, log, one_write, lose_on_read
        self.ident, self.hwcode, self.is_brom, self.boot_lu_size = 'abc123', qi.MT6789, False, 64 << 10
        self.wrote = self.dead = False
        self.reads = 0

    def read(self, off, n, lu='user'):
        self.reads += 1
        if self.dead or self.reads == self.lose_on_read:
            raise qi.SessionLost('read')
        return b'P' * n if lu == 'boot1' else self.store.read(off, n)

    def write(self, off, length, pieces, progress):
        if self.dead:
            raise qi.SessionLost('write')
        data = b''.join(pieces)
        assert len(data) == length
        self.store.write(off, data)
        self.log.append(('write', off, length))
        progress(length)
        self.wrote = True
        self.dead = self.one_write

    def reboot(self):
        if self.dead:
            raise qi.SessionLost('reboot')
        self.log.append(('reboot',))

    def close(self):
        self.log.append(('close',))


class QuietUi(qi.Ui):
    def __init__(self):
        self.text = []

    def say(self, text=''):
        self.text.append(text)

    def step(self, text):
        self.text.append(text)

    def ask(self, prompt):
        return ''

    def progress(self, label, total):
        return _Bar()


class _Bar:
    def __call__(self, n):
        pass

    def end(self):
        pass


class Sparse(unittest.TestCase):
    CHUNKS = [('raw', b'G' * BLOCK * 2), ('fill', b'\1\2\3\4', 3), ('skip', 5), ('crc',),
              ('raw', b'R' * BLOCK), ('skip', 2), ('fill', b'\0\0\0\0', 2), ('skip', 1)]

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.img = self.dir / 'x.userdata.img'
        self.img.write_bytes(sparse(self.CHUNKS))

    def test_scan_finds_written_runs(self):
        plan = qi.scan(self.img, hashlib.sha256(self.img.read_bytes()).hexdigest())
        self.assertEqual(plan.size, 16 * BLOCK)
        self.assertEqual(plan.extents, [qi.Extent(0, 5 * BLOCK), qi.Extent(10 * BLOCK, BLOCK),
                                        qi.Extent(13 * BLOCK, 2 * BLOCK)])

    def test_feeds_give_the_image_bytes(self):
        plan, whole = qi.scan(self.img), expand(self.CHUNKS)
        with qi.open_image(self.img) as f:
            _, runs = qi.image_runs(f, None)
            got = {e: b''.join(p) for e, p in qi.feeds(runs, plan.extents)}
        for e, data in got.items():
            self.assertEqual(data, whole[e.start:e.end])

    def test_one_span_fills_the_gaps_with_zeros(self):
        plan, whole = qi.scan(self.img), expand(self.CHUNKS)
        with qi.open_image(self.img) as f:
            _, runs = qi.image_runs(f, None)
            [data] = [b''.join(p) for _, p in qi.feeds(runs, plan.span())]
            self.assertEqual(data, whole[:15 * BLOCK])

    def test_a_bad_checksum_or_a_short_image_stops(self):
        with self.assertRaises(qi.Fail):
            qi.scan(self.img, '0' * 64)
        self.img.write_bytes(self.img.read_bytes()[:-100])
        with self.assertRaises(qi.Fail):
            qi.scan(self.img)

    def test_a_plain_image_is_one_run_padded_to_blocks(self):
        raw = self.dir / 'raw.img'
        raw.write_bytes(b'Z' * (BLOCK + 10))
        plan = qi.scan(raw)
        self.assertEqual(plan.extents, [qi.Extent(0, 2 * BLOCK)])

    @unittest.skipUnless(shutil.which('zstd'), 'needs zstd')
    def test_a_zstd_image_is_read_through(self):
        subprocess.run(['zstd', '-q', str(self.img)], check=True)
        zst = self.dir / 'x.userdata.img.zst'
        self.assertEqual(qi.scan(zst, hashlib.sha256(self.img.read_bytes()).hexdigest()).size, 16 * BLOCK)

    def test_samples_cover_both_gpts(self):
        ext = [qi.Extent(0, 2 * MiB), qi.Extent(4 * MiB, BLOCK), qi.Extent(8 * MiB, 3 * BLOCK)]
        picks = qi.pick_samples(ext)
        self.assertIn((0, MiB), picks)
        self.assertIn((8 * MiB, 3 * BLOCK), picks)


class Lk(unittest.TestCase):
    def test_splice_keeps_mediatek_parts_and_certificates(self):
        lk = stock_lk()
        out = qi.splice_uboot(lk, UBOOT)
        old, new = qi.lk_parts(lk), qi.lk_parts(out)
        self.assertEqual(len(old), len(new))
        self.assertTrue(qi.is_marathon_lk(out))
        self.assertFalse(qi.is_marathon_lk(lk))
        for (s0, e0, c0), (s1, e1, c1) in zip(old[1:], new[1:]):
            self.assertEqual(c0, c1)
            self.assertEqual(lk[s0 + 512:e0], out[s1 + 512:e1])
        # As gimme-uboot.py (liblk) writes it: the last non-certificate part ends the list too.
        self.assertEqual(qi._u32(out, new[9][0] + 64), 1)
        self.assertEqual(qi.splice_uboot(out + bytes(BLOCK), UBOOT), out)

    def test_refuses_what_is_not_lk_or_not_the_q25_uboot(self):
        with self.assertRaises(qi.Fail):
            qi.splice_uboot(bytes(qi.LK_SIZE), UBOOT)
        with self.assertRaises(qi.Fail):
            qi.splice_uboot(stock_lk(), b'U-Boot for something else')
        with self.assertRaises(qi.Fail):
            qi.splice_uboot(stock_lk(), b'mt6789-q25' + bytes(qi.HANDOFF_LIMIT))


class Table(unittest.TestCase):
    def test_reads_the_gpt(self):
        store = Store()
        store.write(0, gpt(LAYOUT, 128 * MiB))
        t = qi.read_table(FakePhone(store, []))
        self.assertEqual(t.parts['lk_b'], qi.Part(8 * MiB, qi.LK_SIZE))
        self.assertEqual(t.primary, qi.Extent(0, 8 * BLOCK))
        self.assertEqual(t.backup, qi.Extent(80 * MiB, 48 * MiB))
        qi.check_q25(t, qi.MT6789, 64 * MiB)
        with self.assertRaises(qi.Fail):
            qi.check_q25(t, 0x1234)
        with self.assertRaises(qi.Fail):
            qi.check_q25(t, qi.MT6789, 65 * MiB)


class Release(unittest.TestCase):
    def rel(self, tag, published, pre=False, assets=('a.userdata.img.zst', 'a.SHA256SUMS', 'u-boot-q25.bin')):
        return {'tag_name': tag, 'published_at': published, 'prerelease': pre, 'draft': False,
                'assets': [{'name': n, 'size': 1, 'browser_download_url': n} for n in assets]}

    def test_picks_the_newest_install_release(self):
        rels = [self.rel('zinwa-q25/1', '2026-11-01'), self.rel('zinwa-q25/3', '2026-11-20', pre=True),
                self.rel('zinwa-q25/2', '2026-11-10'), self.rel('stable/zinwa-q25_marathon_edge', '2026-11-22'),
                self.rel('zinwa-q25/4', '2026-11-21', assets=('a.SHA256SUMS',))]
        self.assertEqual(qi.pick_release(rels)[0], 'zinwa-q25/2')
        self.assertEqual(qi.pick_release(rels, 'zinwa-q25/3')[0], 'zinwa-q25/3')
        with self.assertRaises(qi.Fail):
            qi.pick_release(rels, 'zinwa-q25/4')

    def test_parse_sums(self):
        self.assertEqual(qi.parse_sums(f'{"a" * 64}  x.img\n{"B" * 64} *y.bin\nnoise\n'),
                         {'x.img': 'a' * 64, 'y.bin': 'b' * 64})


class Usb(unittest.TestCase):
    def test_waits_for_a_stale_session_to_be_unplugged(self):
        with tempfile.TemporaryDirectory() as d:
            dev = Path(d) / '1-1'
            dev.mkdir()
            for f, v in (('idVendor', '0e8d'), ('idProduct', '2000')):
                (dev / f).write_text(v + '\n')
            self.assertEqual(qi.mtk_devices(d), [(0x0e8d, 0x2000)])
            ui = QuietUi()
            qi.plug_in(ui, 2, d, sleep=lambda s: shutil.rmtree(dev))
            self.assertFalse(dev.exists())
            self.assertIn('still connected', ui.text[0])


class Flow(unittest.TestCase):
    CHUNKS = [('raw', b'G' * BLOCK * 3), ('skip', 50), ('raw', b'D' * BLOCK * 4), ('fill', b'\7\7\7\7', 8),
              ('skip', 20), ('raw', b'T' * BLOCK)]

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.store = Store()
        self.store.write(0, gpt(LAYOUT, 128 * MiB))
        self.store.write(LAYOUT['lk_a'][0], stock_lk())
        self.store.write(LAYOUT['lk_b'][0], stock_lk()[:-BLOCK] + b'B' * BLOCK)
        self.image = self.dir / 'm.userdata.img'
        self.image.write_bytes(sparse(self.CHUNKS))
        self.args = SimpleNamespace(backup_dir=self.dir / 'backups', from_backup=None)
        self.log = []

    def job(self):
        return qi.Job(self.args, self.image, qi.scan(self.image), UBOOT)

    def run_install(self, **phone):
        phones = []

        def opener(ui, attempt):
            phones.append(FakePhone(self.store, self.log, **phone))
            return phones[-1]
        job = self.job()
        return qi.run_sessions(QuietUi(), job, qi.install_session, opener), job, len(phones)

    def ud(self, off, n):
        return self.store.read(LAYOUT['userdata'][0] + off, n)

    def check_installed(self):
        lk = qi.pad_block(qi.splice_uboot(stock_lk(), UBOOT))
        self.assertEqual(self.store.read(LAYOUT['lk_a'][0], len(lk)), lk)
        self.assertEqual(self.store.read(LAYOUT['lk_b'][0], len(lk)), lk)
        whole = expand(self.CHUNKS)
        self.assertEqual(self.ud(0, 3 * BLOCK), whole[:3 * BLOCK])
        self.assertEqual(self.ud(53 * BLOCK, 12 * BLOCK), whole[53 * BLOCK:65 * BLOCK])
        self.assertEqual(self.ud(85 * BLOCK, BLOCK), whole[85 * BLOCK:86 * BLOCK])

    def writes(self):
        names = {v[0]: k for k, v in LAYOUT.items()}
        return [names.get(e[1], 'userdata') for e in self.log if e[0] == 'write']

    def test_one_session_backs_up_then_writes_lk_before_userdata(self):
        rebooted, job, sessions = self.run_install()
        self.assertTrue(rebooted)
        self.assertEqual(sessions, 1)
        self.assertEqual(self.writes(), ['lk_a', 'lk_b', 'userdata', 'userdata', 'userdata'])
        self.assertIn(('reboot',), self.log)
        self.check_installed()
        self.assertEqual(self.ud(3 * BLOCK, BLOCK), b'\xaa' * BLOCK, 'DONT_CARE blocks are left alone')
        [bdir] = (self.dir / 'backups/q25-abc123').glob('2*')
        manifest = json.loads((bdir / 'manifest.json').read_text())
        self.assertTrue(manifest['complete'] and manifest['lk_a_is_stock'])
        self.assertEqual((bdir / 'lk_a.bin').read_bytes(), stock_lk())
        sums = qi.parse_sums((bdir / 'SHA256SUMS').read_text())
        self.assertEqual(set(sums), {f'{n}.bin' for n in ('gpt-primary', 'gpt-backup', 'lk_a', 'lk_b', 'boot_a',
                                                           'seccfg', 'preloader')})
        self.assertTrue(job.state['multiwrite'])

    def test_a_phone_with_one_write_per_session_gets_one_write_per_session(self):
        rebooted, job, sessions = self.run_install(one_write=True)
        self.assertFalse(rebooted, 'the last write leaves the phone for the user to restart')
        self.assertEqual(sessions, 3)
        self.assertEqual(self.writes(), ['lk_a', 'lk_b', 'userdata'])
        self.assertIs(job.state['multiwrite'], False)
        self.check_installed()
        self.assertEqual(self.ud(3 * BLOCK, BLOCK), bytes(BLOCK), 'one span: gaps are written as zeros')

    def test_userdata_is_never_written_while_android_can_still_start(self):
        for one_write in (False, True):
            with self.subTest(one_write=one_write):
                self.setUp()
                seen = []
                orig = FakePhone.write

                def write(phone, off, length, pieces, progress):
                    if off >= LAYOUT['userdata'][0]:
                        seen.append(all(qi.is_marathon_lk(self.store.read(LAYOUT[n][0], qi.LK_SIZE))
                                        for n in ('lk_a', 'lk_b')))
                    orig(phone, off, length, pieces, progress)
                with unittest.mock.patch.object(FakePhone, 'write', write):
                    self.run_install(one_write=one_write)
                self.assertTrue(seen and all(seen))

    def test_a_second_run_finds_everything_done(self):
        self.run_install()
        self.log.clear()
        rebooted, _, _ = self.run_install()
        self.assertTrue(rebooted)
        self.assertEqual(self.writes(), [])

    def test_a_lost_read_during_the_backup_resumes_it(self):
        phones = []

        def opener(ui, attempt):
            phones.append(FakePhone(self.store, self.log, lose_on_read=6 if attempt == 1 else None))
            return phones[-1]
        job = self.job()
        self.assertTrue(qi.run_sessions(QuietUi(), job, qi.install_session, opener))
        self.assertEqual(len(phones), 2)
        self.assertIs(job.state['multiwrite'], True, 'a lost read is not a write problem')
        self.check_installed()

    def test_restore_stock_puts_the_backup_back(self):
        self.run_install()
        self.log.clear()

        def opener(ui, attempt):
            return FakePhone(self.store, self.log)
        job = qi.Job(self.args)
        self.assertTrue(qi.run_sessions(QuietUi(), job, qi.restore_session, opener))
        self.assertEqual(self.store.read(LAYOUT['lk_a'][0], qi.LK_SIZE), stock_lk())
        self.assertEqual(self.store.read(LAYOUT['lk_b'][0], BLOCK * 2)[-BLOCK:], stock_lk()[BLOCK:2 * BLOCK])
        self.assertEqual(self.ud(0, qi.WIPE_HEAD), bytes(qi.WIPE_HEAD))
        self.assertEqual(self.writes(), ['userdata', 'lk_a', 'lk_b'])


class FakeDA:
    """The download agent's side of the XML write exchange, as documented by penumbra
    (docs/content/Mediatek/Common/DA/XML DA Protocol.md) and as mtkclient's boot_to() uses it.

    A packet that arrives where a command is due and is not one is recorded, and the
    fake then answers nothing, which is what the phone looked like after a write."""

    def __init__(self, wants_extra_ok=False):
        self.wants_extra_ok = wants_extra_ok
        self.state, self.inbox, self.out = 'cmd', bytearray(), []
        self.stray, self.flash, self.want = [], {}, None

    def send(self, payload):
        if isinstance(payload, str):
            payload = payload.encode() + b'\0'
        self.out += [struct.pack('<III', 0xFEEEEEEF, 1, len(payload)), payload]

    def xml(self, cmd, arg):
        self.send(f'<?xml version="1.0" encoding="utf-8"?><host><version>1.0</version><command>{cmd}</command>'
                  f'<arg>{arg}</arg></host>')

    def usbwrite(self, data):
        self.inbox += data
        while len(self.inbox) >= 12:
            n = struct.unpack_from('<I', self.inbox, 8)[0]
            if len(self.inbox) < 12 + n:
                break
            packet = bytes(self.inbox[12:12 + n])
            del self.inbox[:12 + n]
            self.take(packet)
        return True

    def usbread(self, resplen=None, maxtimeout=100, w_max_packet_size=None):
        if not self.out:
            return b''
        if resplen is None:
            return self.out.pop(0)
        data = self.out.pop(0)
        assert len(data) == resplen, (len(data), resplen)
        return data

    def take(self, p):
        text = p.rstrip(b'\0').decode('latin-1')
        s = self.state
        if s == 'dead':
            return
        if s == 'cmd':
            m = re.search(r'<command>CMD:WRITE-FLASH</command>.*<offset>(0x[0-9a-f]+)</offset>.*:(0x[0-9a-f]+)<',
                          text)
            if not m:
                self.stray.append(text)
                self.state = 'dead'
                return
            self.addr, self.want, self.got = int(m[1], 16), int(m[2], 16), bytearray()
            self.send('OK')
            self.xml('CMD:FILE-SYS-OPERATION', '<key>FILE-SIZE</key><file_path>MEM://0x0:0x0</file_path>')
            self.state = 'fs-ack'
        elif s == 'fs-ack' and text == 'OK':
            self.state = 'fs-size'
        elif s == 'fs-size' and text == f'OK@{hex(self.want)}':
            self.xml('CMD:DOWNLOAD-FILE', '<checksum>CHK_NO</checksum><info>x</info>'
                     f'<source_file>MEM://0x0:{hex(self.want)}</source_file><packet_length>0x1000</packet_length>')
            self.state = 'dl-ack'
        elif s == 'dl-ack' and text == 'OK':
            self.state = 'dl-size'
        elif s == 'dl-size' and text == f'OK@{hex(self.want)}':
            self.send('OK')
            self.state = 'status'
        elif s == 'status' and text == 'OK@0x0':
            self.send('OK')
            self.state = 'data'
        elif s == 'data':
            self.got += p
            self.send('OK')
            if len(self.got) < self.want:
                self.state = 'status'
            elif self.wants_extra_ok:
                self.state = 'extra'
            else:
                self.end()
        elif s == 'extra' and text == 'OK':
            self.end()
        elif s == 'end-ack' and text == 'OK':
            self.xml('CMD:START', '')
            self.state = 'start-ack'
        elif s == 'start-ack' and text == 'OK':
            self.state = 'cmd'
        else:
            raise AssertionError(f'unexpected {text[:40]!r} in state {s}')

    def end(self):
        self.flash[self.addr] = bytes(self.got)
        self.xml('CMD:END', '<result>OK</result>')
        self.state = 'end-ack'


def daxml(port):
    da = DAXML.__new__(DAXML)
    noop = lambda *a, **k: None  # noqa: E731
    da.error = da.info = da.debug = da.warning = noop
    da.usbwrite, da.usbread = port.usbwrite, port.usbread
    da.cmd = XMLCmd(None)
    da.config = SimpleNamespace(uartlog=[])
    da.mtk = SimpleNamespace(config=SimpleNamespace(guiprogress=None))
    da.daconfig = SimpleNamespace(storage=SimpleNamespace(get_storage=lambda t, n: [None, 'UFS-LUA2', n]))
    return da


@unittest.skipIf(DAXML is None, 'needs mtkclient')
class Protocol(unittest.TestCase):
    DATA = bytes(range(256)) * 40

    def test_mtkclient_writeflash_leaves_one_ok_too_many(self):
        port = FakeDA()
        da = daxml(port)
        self.assertTrue(DAXML.writeflash(da, 0x1000, len(self.DATA), '', wdata=self.DATA, parttype='user',
                                         display=False))
        self.assertEqual(port.flash[0x1000], self.DATA)
        self.assertEqual(port.stray, ['OK'], 'the "OK" after the last packet lands where a command is due')
        with self.assertRaises(qi.SessionLost):
            qi.da_write(da, 0x8000, len(self.DATA), [self.DATA], lambda n: None, None)

    def test_da_write_keeps_the_session_for_the_next_write(self):
        port = FakeDA()
        da = daxml(port)
        sizes = []
        self.assertEqual(qi.da_write(da, 0x1000, len(self.DATA), [self.DATA[:5000], self.DATA[5000:]],
                                     sizes.append, None), 'direct')
        self.assertEqual(sum(sizes), len(self.DATA))
        self.assertEqual(qi.da_write(da, 0x8000, 4096, [b'x' * 4096], lambda n: None, 'direct'), 'direct')
        self.assertEqual(port.flash, {0x1000: self.DATA, 0x8000: b'x' * 4096})
        self.assertEqual(port.stray, [])

    def test_da_write_gives_the_extra_ok_to_a_da_that_waits_for_it(self):
        port = FakeDA(wants_extra_ok=True)
        da = daxml(port)
        self.assertEqual(qi.da_write(da, 0x1000, len(self.DATA), [self.DATA], lambda n: None, None), 'extra-ok')
        self.assertEqual(qi.da_write(da, 0x8000, 4096, [b'y' * 4096], lambda n: None, 'extra-ok'), 'extra-ok')
        self.assertEqual(port.flash[0x8000], b'y' * 4096)
        self.assertEqual(port.stray, [])


if __name__ == '__main__':
    unittest.main()
