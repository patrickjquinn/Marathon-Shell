#!/usr/bin/env python3
"""Marathon QEMU automation driver.

One module that owns the QMP socket, the SSH session, and the screenshot
pipeline. Scenarios script against this — they don't poke QMP directly.

Lifecycle:
    drv = QemuDriver(qmp_sock=Path, ssh_port=int, ssh_password=str)
    drv.connect()                  # negotiates QMP capabilities
    drv.wait_for_ssh(timeout=120)  # spins until sshd answers
    drv.screenshot("home")         # → tests/screenshots/<run>/home.png
    drv.tap(x, y)                  # absolute pointer via virtio-tablet
    drv.swipe(x1, y1, x2, y2)      # drag via stepped pointer events
    drv.key("KEY_ENTER")           # send a keysym from virtio-keyboard
    drv.ssh("journalctl --since boot")     # returns (rc, stdout, stderr)
    drv.assert_no_coredumps_since(time_iso)
    drv.assert_no_journal_errors_since(time_iso, allowlist=[...])
    drv.shutdown()

Resolution: the screen geometry comes from the QMP `query-display-options`
result — we don't hardcode it. The virtio-tablet device uses absolute
coords in the 0..32767 range; we translate (x, y) pixel coords into that
space using the queried resolution.

Anti-pattern check: if QMP isn't reachable in 5 s the driver fails loud,
not silent — the whole point of this harness is to surface issues fast.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


# virtio-tablet uses absolute coords in the 0..32767 range per axis.
QEMU_ABS_MAX = 32767


@dataclass
class QemuDriver:
    qmp_sock: Path
    ssh_port: int
    ssh_password: str = "marathon"
    ssh_user: str = "root"
    run_dir: Path = field(default_factory=lambda: Path("tests/screenshots/last"))
    width: int = 720
    height: int = 1440
    _qmp: socket.socket | None = None
    _qmp_f = None

    def connect(self):
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self._qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._qmp.settimeout(5)
        for attempt in range(60):
            try:
                self._qmp.connect(str(self.qmp_sock))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.5)
        else:
            raise RuntimeError(f"QMP socket {self.qmp_sock} unreachable after 30 s")
        self._qmp_f = self._qmp.makefile("rwb", buffering=0)
        # Drain QMP greeting + negotiate capabilities.
        self._qmp_f.readline()
        self._cmd("qmp_capabilities")
        # Try to learn the actual resolution (best-effort; fall back to ctor).
        try:
            for d in self._cmd_return("query-display-options").get("ui-info", []):
                if "width" in d and "height" in d:
                    self.width, self.height = d["width"], d["height"]
        except Exception:
            pass

    def _cmd(self, execute: str, args: dict | None = None):
        self._cmd_return(execute, args)

    def _cmd_return(self, execute: str, args: dict | None = None):
        msg = {"execute": execute}
        if args is not None:
            msg["arguments"] = args
        self._qmp_f.write((json.dumps(msg) + "\n").encode())
        self._qmp_f.flush()
        while True:
            line = self._qmp_f.readline()
            if not line:
                raise RuntimeError("QMP closed mid-call")
            reply = json.loads(line)
            if "event" in reply:
                # Stash + ignore async events for now.
                continue
            if "error" in reply:
                raise RuntimeError(f"QMP {execute} failed: {reply['error']}")
            return reply.get("return", {})

    # -------- Screenshots --------

    def screenshot(self, label: str) -> Path:
        png = self.run_dir / f"{label}.png"
        # QEMU 8+ supports format=png natively — no PPM/ImageMagick dance.
        # Matches what GNOME openQA-tests use.
        try:
            self._cmd("screendump", {"filename": str(png), "format": "png"})
            if png.exists():
                return png
        except RuntimeError:
            pass
        # Fallback for older QEMU: PPM + convert.
        ppm = self.run_dir / f"{label}.ppm"
        self._cmd("screendump", {"filename": str(ppm)})
        if ppm.exists():
            try:
                subprocess.run(["convert", str(ppm), str(png)], check=True,
                               stderr=subprocess.DEVNULL)
                ppm.unlink()
                return png
            except (FileNotFoundError, subprocess.CalledProcessError):
                return ppm
        raise RuntimeError(f"screendump wrote no file at {png}/{ppm}")

    def visual_diff(self, label: str, golden: Path, threshold: float = 0.03) -> bool:
        """Compare a labelled screenshot against a golden PNG via odiff.

        Returns True if the diff is under `threshold` (0.0..1.0 fraction of
        pixels). odiff is preferred over ImageMagick — 6× faster, SIMD-first,
        single static binary; falls through to compare/AE if odiff isn't on
        PATH. Either way, a diff overlay lands at <run_dir>/<label>.diff.png.
        """
        shot = self.run_dir / f"{label}.png"
        if not shot.exists():
            print(f"  FAIL  no screenshot at {shot}")
            return False
        if not golden.exists():
            # First run: bootstrap the golden silently.
            golden.parent.mkdir(parents=True, exist_ok=True)
            golden.write_bytes(shot.read_bytes())
            print(f"  OK    bootstrapped golden {golden}")
            return True
        diff_out = self.run_dir / f"{label}.diff.png"
        # odiff: returns 0 = identical, 21 = pixel diff exceeds threshold.
        try:
            r = subprocess.run(
                ["odiff", "--threshold", str(threshold),
                 "--diff-image-path", str(diff_out),
                 str(golden), str(shot)],
                capture_output=True)
            if r.returncode == 0:
                print(f"  OK    visual match: {label}")
                return True
            print(f"  FAIL  visual diff: {label} → {diff_out}")
            print(f"          {r.stdout.decode(errors='replace').strip()}")
            return False
        except FileNotFoundError:
            # No odiff. Compute the differing-pixel fraction directly
            # rather than parsing ImageMagick's AE metric.
            #
            # AE was unreliable across builds: this host's `magick
            # compare -metric AE` returns "4.74723e+09 (4.74723e+09)" for
            # a 720x1440 image whose true differing-pixel count is
            # 343631. Both numbers are a channel-difference sum, not a
            # count, so dividing by width*height reported 457873% and the
            # threshold check was meaningless in either direction.
            #
            # Same metric the interaction scenario uses: per-pixel max
            # channel delta, thresholded at 12/255 to ignore antialiasing
            # and PNG quantisation noise.
            try:
                from PIL import Image
                import numpy as np
            except ImportError:
                print(f"  WARN  no visual-diff backend (odiff / Pillow) "
                      f"-- skipping {label}")
                return True
            a = np.asarray(Image.open(golden).convert("RGB"), dtype=np.int16)
            b = np.asarray(Image.open(shot).convert("RGB"), dtype=np.int16)
            if a.shape != b.shape:
                print(f"  FAIL  visual diff: {label} -- size mismatch "
                      f"{a.shape[1]}x{a.shape[0]} vs {b.shape[1]}x{b.shape[0]}")
                return False
            delta = np.abs(a - b).max(axis=-1)
            differing = int((delta > 12).sum())
            frac = differing / max(1, delta.size)
            ok = frac <= threshold
            tag = "OK" if ok else "FAIL"
            print(f"  {tag}  visual diff: {label}  {differing}px ({frac:.3%})")
            return ok

    # -------- Input injection --------

    def _abs(self, x: int, y: int):
        ax = int(x * QEMU_ABS_MAX / max(1, self.width))
        ay = int(y * QEMU_ABS_MAX / max(1, self.height))
        return ax, ay

    # Input strategy:
    #   Prefer marathon-touchctl (python-evdev) inside the guest — produces
    #   real ABS_MT touch events the Wayland compositor sees identically
    #   to a real touchscreen. Falls back to QMP virtio-tablet pointer
    #   events if the helper isn't installed (older images).
    #
    #   The pointer fallback DOES NOT exercise touch-specific paths —
    #   MouseArea will receive press/release, but PinchHandler / multi-
    #   finger gestures / per-touch tracking will silently no-op. Track
    #   this in test reports so it's clear which fixtures depend on which.
    _touchctl_available: bool | None = None

    def _has_touchctl(self) -> bool:
        # OPT-IN, not auto-detect. marathon-touchctl is present in the image
        # and exits 0 under QEMU while injecting nothing the compositor ever
        # sees, so "command -v" said yes and every tap silently did nothing —
        # scenarios ran green against a screen they were not touching. The
        # QMP virtio-tablet path below is the one that demonstrably works
        # here. Set MARATHON_USE_TOUCHCTL=1 on real hardware, where the
        # evdev injector is the only option.
        if self._touchctl_available is None:
            if os.environ.get("MARATHON_USE_TOUCHCTL") != "1":
                self._touchctl_available = False
                return False
            rc, _, _ = self.ssh("command -v marathon-touchctl >/dev/null")
            self._touchctl_available = (rc == 0)
            if self._touchctl_available:
                # Push the screen geometry so coords match what we screenshot.
                self.ssh(
                    f"echo 'export MARATHON_TOUCH_WIDTH={self.width}; "
                    f"export MARATHON_TOUCH_HEIGHT={self.height}' "
                    "> /tmp/marathon-touchctl.env")
        return self._touchctl_available

    def _touchctl(self, cmd: str):
        return self.ssh(
            f". /tmp/marathon-touchctl.env 2>/dev/null; "
            f"marathon-touchctl {cmd}")

    # 80 ms was too short for the compositor to resolve a synthetic press
    # into a click — taps landed on the right pixel and did nothing. 300 ms
    # registers reliably; it is still far quicker than a human tap.
    def tap(self, x: int, y: int, hold_ms: int = 300):
        if self._has_touchctl():
            self._touchctl(f"tap {x} {y}")
            return
        ax, ay = self._abs(x, y)
        self._cmd("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": ax}},
            {"type": "abs", "data": {"axis": "y", "value": ay}},
        ]})
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": True}},
        ]})
        time.sleep(hold_ms / 1000.0)
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": False}},
        ]})

    def swipe(self, x1: int, y1: int, x2: int, y2: int, steps: int = 24, duration_ms: int = 400):
        if self._has_touchctl():
            self._touchctl(f"swipe {x1} {y1} {x2} {y2} {steps}")
            return
        ax1, ay1 = self._abs(x1, y1)
        ax2, ay2 = self._abs(x2, y2)
        self._cmd("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": ax1}},
            {"type": "abs", "data": {"axis": "y", "value": ay1}},
        ]})
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": True}},
        ]})
        per = duration_ms / 1000.0 / max(1, steps)
        for i in range(1, steps + 1):
            tx = int(ax1 + (ax2 - ax1) * i / steps)
            ty = int(ay1 + (ay2 - ay1) * i / steps)
            self._cmd("input-send-event", {"events": [
                {"type": "abs", "data": {"axis": "x", "value": tx}},
                {"type": "abs", "data": {"axis": "y", "value": ty}},
            ]})
            time.sleep(per)
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": False}},
        ]})

    def key(self, keysym: str):
        # QMP key naming follows QEMU's QKeyCode table (e.g. "ret", "esc",
        # "spc", "a"). Pass either a QKeyCode string or a list of them.
        if isinstance(keysym, str):
            keysyms = [keysym]
        else:
            keysyms = list(keysym)
        self._cmd("send-key", {"keys": [{"type": "qcode", "data": k} for k in keysyms]})

    # -------- SSH --------

    def ssh(self, cmd: str, timeout: int = 30) -> tuple[int, str, str]:
        return self._ssh_raw(cmd, timeout=timeout)

    def _ssh_raw(self, cmd: str, timeout: int = 30) -> tuple[int, str, str]:
        argv = ["sshpass", "-p", self.ssh_password, "ssh",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "ConnectTimeout=10",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-p", str(self.ssh_port),
                f"{self.ssh_user}@127.0.0.1",
                cmd]
        env = os.environ.copy()
        env.pop("SSH_ASKPASS", None)
        env.pop("DISPLAY", None)
        env["SSH_ASKPASS_REQUIRE"] = "never"
        r = subprocess.run(argv, capture_output=True, timeout=timeout, env=env)
        return r.returncode, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace")

    def wait_for_ssh(self, timeout: int = 180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", self.ssh_port), timeout=2):
                    pass
            except OSError:
                time.sleep(2)
                continue
            try:
                rc, _, _ = self._ssh_raw("true", timeout=20)
                if rc == 0:
                    return
            except subprocess.TimeoutExpired:
                pass
            time.sleep(3)
        raise TimeoutError(f"sshd on :{self.ssh_port} never accepted password auth")

    # -------- Assertions --------

    def assert_no_coredumps_since(self, since: str):
        rc, out, _ = self.ssh(
            f"coredumpctl list --since '{since}' --no-pager 2>/dev/null | tail -n +2")
        cores = [ln for ln in out.splitlines() if ln.strip()]
        if cores:
            print(f"  FAIL  {len(cores)} coredump(s) since {since}:")
            for c in cores[:10]:
                print(f"          {c}")
            return False
        print(f"  OK    no coredumps since {since}")
        return True

    def assert_no_journal_errors_since(self, since: str, allowlist: list[str] | None = None):
        allow = allowlist or []
        rc, out, _ = self.ssh(
            f"journalctl --since '{since}' --no-pager -p err 2>/dev/null")
        bad = []
        for ln in out.splitlines():
            if not ln.strip():
                continue
            if any(a in ln for a in allow):
                continue
            bad.append(ln)
        if bad:
            print(f"  FAIL  {len(bad)} journal error(s) since {since}:")
            for b in bad[:15]:
                print(f"          {b}")
            return False
        print(f"  OK    no fresh journal errors since {since}")
        return True

    def shutdown(self):
        try:
            self._cmd("quit")
        except Exception:
            pass
        if self._qmp_f:
            try:
                self._qmp_f.close()
            except Exception:
                pass
        if self._qmp:
            try:
                self._qmp.close()
            except Exception:
                pass


# ---------- standalone CLI for quick interactive use ----------

def main():
    p = argparse.ArgumentParser(description="Marathon QEMU driver — CLI shim")
    p.add_argument("--qmp", required=True, help="path to QMP unix socket")
    p.add_argument("--ssh-port", type=int, default=2228)
    p.add_argument("--ssh-password", default="marathon")
    p.add_argument("--ssh-user", default="root")
    p.add_argument("--run-dir", default="tests/screenshots/last")
    sub = p.add_subparsers(dest="action", required=True)
    sub.add_parser("screenshot").add_argument("name")
    s = sub.add_parser("tap"); s.add_argument("x", type=int); s.add_argument("y", type=int)
    s = sub.add_parser("swipe")
    s.add_argument("x1", type=int); s.add_argument("y1", type=int)
    s.add_argument("x2", type=int); s.add_argument("y2", type=int)
    s = sub.add_parser("key"); s.add_argument("code")
    s = sub.add_parser("ssh"); s.add_argument("cmd")
    sub.add_parser("wait-ssh")

    args = p.parse_args()
    drv = QemuDriver(
        qmp_sock=Path(args.qmp), ssh_port=args.ssh_port,
        ssh_password=args.ssh_password, ssh_user=args.ssh_user,
        run_dir=Path(args.run_dir),
    )
    drv.connect()
    try:
        if args.action == "screenshot":
            p = drv.screenshot(args.name)
            print(p)
        elif args.action == "tap":
            drv.tap(args.x, args.y)
        elif args.action == "swipe":
            drv.swipe(args.x1, args.y1, args.x2, args.y2)
        elif args.action == "key":
            drv.key(args.code)
        elif args.action == "ssh":
            rc, out, err = drv.ssh(args.cmd)
            sys.stdout.write(out)
            sys.stderr.write(err)
            sys.exit(rc)
        elif args.action == "wait-ssh":
            drv.wait_for_ssh()
            print("ssh ready")
    finally:
        # Don't call shutdown() from CLI — we don't want to kill QEMU.
        if drv._qmp_f: drv._qmp_f.close()
        if drv._qmp: drv._qmp.close()


if __name__ == "__main__":
    main()
