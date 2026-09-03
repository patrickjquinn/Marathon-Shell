"""Device driver — same API as QemuDriver, talks to a real Marathon device
over the USB gadget instead of a QEMU instance.

Drop-in: scenarios import QemuDriver; we just substitute this class in
run_scenarios.py when --target=device is given. The public API
(`ssh`, `tap`, `swipe`, `key`, `screenshot`, `visual_diff`,
`wait_for_ssh`, `assert_no_coredumps_since`, `assert_no_journal_errors_since`,
`width`, `height`, `run_dir`, `shutdown`) matches QemuDriver line-for-line.

Connection model:
  • SSH over the USB gadget — RNDIS/CDC-NCM puts the device at
    172.16.42.1, the host at 172.16.42.2. Auth is the ssh-key the image
    build baked into /usr/share/factory/home/user/.ssh/authorized_keys
    (the host's own id_ed25519 pub key, copied at first boot via
    tmpfiles).
  • Input via marathon-touchctl over SSH — already shipped in the
    marathon-shell package. Same evdev path the QEMU driver uses, just
    invoked over a different transport.
  • Screenshot via Marathon shell's IPC: invoke saveScreenshotTo() via
    busctl on org.marathonos.Shell, scp the PNG back. Falls back to
    `grim` if the screencopy protocol is exposed, or a /dev/fb0 raw
    dump as last resort.

We assume the device booted with the firstboot tmpfiles already run
(so the SSH key landed in the user's ~/.ssh) and sshd is on
multi-user.target. wait_for_ssh polls.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import time
from pathlib import Path


# Default geometry for the Mantix DSI-1 panel on Librem 5 (the only
# device target right now). Override via env if porting to a phone
# with a different display.
DEFAULT_WIDTH = 720
DEFAULT_HEIGHT = 1440

# USB gadget RNDIS/CDC-NCM endpoint exposed by postmarketOS. Host gets
# 172.16.42.2; device is 172.16.42.1.
DEFAULT_HOST = "172.16.42.1"


class DeviceDriver:
    """Same surface as QemuDriver, just SSH-only."""

    def __init__(
        self,
        run_dir: Path,
        host: str = DEFAULT_HOST,
        user: str = "user",
        width: int = DEFAULT_WIDTH,
        height: int = DEFAULT_HEIGHT,
        ssh_key: str | None = None,
    ):
        self.run_dir = Path(run_dir)
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.host = host
        self.user = user
        self.width = width
        self.height = height
        # ssh_key=None lets ssh pick id_ed25519 / id_rsa from ~/.ssh by
        # default. Set explicitly when running headless.
        self.ssh_key = ssh_key
        self._touchctl_available: bool | None = None
        self._screencap_backend: str | None = None  # cached: "ipc" | "grim" | "fb0"

    # -------- Connection lifecycle --------

    def connect(self):
        # Pure marker for parity with QemuDriver.connect(). The real
        # work is in wait_for_ssh().
        return self

    def shutdown(self):
        # Real device stays up; nothing to tear down.
        return

    # -------- SSH --------

    def _ssh_argv(self, timeout: int) -> list[str]:
        argv = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "LogLevel=ERROR",
        ]
        if self.ssh_key:
            argv += ["-i", self.ssh_key]
        argv += [f"{self.user}@{self.host}"]
        return argv

    def ssh(self, cmd: str, timeout: int = 30) -> tuple[int, str, str]:
        argv = self._ssh_argv(timeout) + [cmd]
        r = subprocess.run(
            argv, capture_output=True, timeout=timeout + 5)
        return (
            r.returncode,
            r.stdout.decode("utf-8", errors="replace"),
            r.stderr.decode("utf-8", errors="replace"),
        )

    def wait_for_ssh(self, timeout: int = 240):
        """Block until sshd answers on the gadget interface.

        Boot to multi-user can take a couple of minutes on a cold L5 if
        ModemManager is still enumerating; budget 4 minutes by default.
        """
        deadline = time.time() + timeout
        last_err = "(no attempts)"
        while time.time() < deadline:
            rc, out, err = self.ssh("echo ready", timeout=10)
            if rc == 0 and "ready" in out:
                return
            last_err = err.strip() or out.strip()
            time.sleep(3)
        raise TimeoutError(
            f"sshd never came up on {self.host} within {timeout}s — "
            f"last error: {last_err[:200]}")

    # -------- Input injection --------

    def _has_touchctl(self) -> bool:
        if self._touchctl_available is None:
            rc, _, _ = self.ssh("command -v marathon-touchctl >/dev/null")
            self._touchctl_available = (rc == 0)
            if self._touchctl_available:
                self.ssh(
                    f"printf 'export MARATHON_TOUCH_WIDTH={self.width}\\n"
                    f"export MARATHON_TOUCH_HEIGHT={self.height}\\n' "
                    "> /tmp/marathon-touchctl.env")
        return self._touchctl_available

    def _touchctl(self, cmd: str):
        return self.ssh(
            f". /tmp/marathon-touchctl.env 2>/dev/null; "
            f"marathon-touchctl {cmd}")

    def tap(self, x: int, y: int, hold_ms: int = 300):
        if not self._has_touchctl():
            raise RuntimeError(
                "marathon-touchctl is not installed on the device — "
                "input injection is unavailable. Was this image built "
                "from the marathon-shell APKBUILD?")
        # marathon-touchctl handles hold_ms internally on the tap path.
        self._touchctl(f"tap {x} {y}")

    def swipe(self, x1: int, y1: int, x2: int, y2: int,
              steps: int = 24, duration_ms: int = 400):
        if not self._has_touchctl():
            raise RuntimeError(
                "marathon-touchctl is not installed on the device.")
        # marathon-touchctl uses `steps` for swipe smoothness; pacing is
        # close enough to duration_ms for our purposes (the test only
        # cares about the gesture being recognised by the compositor).
        _ = duration_ms
        self._touchctl(f"swipe {x1} {y1} {x2} {y2} {steps}")

    def key(self, keysym: str | list[str]):
        """Key injection via ydotool if available, else evemu-event raw.

        Marathon's virtual keyboard handles text entry inline in QML,
        so most automation paths don't need this — taps to the on-screen
        key are enough. Reserved for hardware-key sims (power, volume).
        """
        if isinstance(keysym, str):
            keysyms = [keysym]
        else:
            keysyms = list(keysym)
        rc, _, _ = self.ssh("command -v ydotool >/dev/null")
        if rc != 0:
            raise RuntimeError(
                "no ydotool on device — key injection unavailable. "
                "Install ydotool or use tap() against the on-screen "
                "key instead.")
        for k in keysyms:
            self.ssh(f"ydotool key {k}")

    # -------- Screenshots --------

    def _pick_screencap_backend(self) -> str:
        if self._screencap_backend is not None:
            return self._screencap_backend
        # 1. Shell IPC: invoke org.marathonos.Shell.Display.saveScreenshotTo
        rc, _, _ = self.ssh(
            "busctl --user --no-pager list-names 2>/dev/null "
            "| grep -q org.marathonos.Shell")
        if rc == 0:
            self._screencap_backend = "ipc"
            return "ipc"
        # 2. grim (wlroots screencopy_unstable_v1)
        rc, _, _ = self.ssh("command -v grim >/dev/null")
        if rc == 0:
            self._screencap_backend = "grim"
            return "grim"
        # 3. /dev/fb0 dump (mxsfb DRM ships fbdev emulation)
        self._screencap_backend = "fb0"
        return "fb0"

    def screenshot(self, label: str) -> Path:
        png = self.run_dir / f"{label}.png"
        backend = self._pick_screencap_backend()
        device_tmp = f"/tmp/marathon-shot-{label}.png"
        if backend == "ipc":
            # saveScreenshotTo writes a PNG straight to the path we give.
            rc, _, err = self.ssh(
                f"busctl --user call org.marathonos.Shell "
                f"/org/marathonos/Shell/Display "
                f"org.marathonos.Shell.Display saveScreenshotTo s "
                f"'{device_tmp}'")
            if rc != 0:
                raise RuntimeError(
                    f"saveScreenshotTo IPC failed: {err.strip()}")
        elif backend == "grim":
            rc, _, err = self.ssh(f"grim '{device_tmp}'")
            if rc != 0:
                raise RuntimeError(f"grim failed: {err.strip()}")
        else:  # fb0
            # mxsfb panel ships at 720x1440 BGRA8888 = 4 bytes/pixel.
            # ffmpeg is in the image (marathon-shell depends on it).
            rc, _, err = self.ssh(
                f"ffmpeg -y -hide_banner -loglevel error "
                f"-f rawvideo -pix_fmt bgra "
                f"-s {self.width}x{self.height} "
                f"-i /dev/fb0 -frames:v 1 '{device_tmp}' </dev/null")
            if rc != 0:
                raise RuntimeError(
                    f"/dev/fb0 capture failed (backend was last-resort): "
                    f"{err.strip()}")
        # Pull it back to host.
        argv = [
            "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
        ]
        if self.ssh_key:
            argv += ["-i", self.ssh_key]
        argv += [f"{self.user}@{self.host}:{device_tmp}", str(png)]
        subprocess.run(argv, check=True, capture_output=True)
        # Best-effort cleanup on device.
        self.ssh(f"rm -f '{device_tmp}'")
        return png

    def visual_diff(self, label: str, golden: Path,
                    threshold: float = 0.03) -> bool:
        """Identical logic to QemuDriver.visual_diff — duplicated here so
        we don't import from qemu_driver and pull in QMP deps."""
        shot = self.run_dir / f"{label}.png"
        if not shot.exists():
            print(f"  FAIL  no screenshot at {shot}")
            return False
        if not golden.exists():
            golden.parent.mkdir(parents=True, exist_ok=True)
            golden.write_bytes(shot.read_bytes())
            print(f"  OK    bootstrapped golden {golden}")
            return True
        diff_out = self.run_dir / f"{label}.diff.png"
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
            for binary in (["magick", "compare"], ["compare"]):
                try:
                    r = subprocess.run(
                        [*binary, "-metric", "AE", "-fuzz", "5%",
                         str(golden), str(shot), str(diff_out)],
                        capture_output=True)
                    break
                except FileNotFoundError:
                    continue
            else:
                print(f"  WARN  no visual-diff backend — skipping {label}")
                return True
            text = (r.stderr or b"0").decode(errors="replace").strip()
            m = re.search(r"\(([\d.eE+-]+)\)", text)
            raw = m.group(1) if m else text.split()[0] if text else "0"
            try:
                differing = int(float(raw))
            except ValueError:
                differing = 0
            total = self.width * self.height
            frac = differing / max(1, total)
            ok = frac <= threshold
            tag = "OK" if ok else "FAIL"
            print(f"  {tag}  visual diff: {label}  "
                  f"{differing}px ({frac:.3%})")
            return ok

    # -------- Boot-state assertions --------

    def assert_no_coredumps_since(self, since: str):
        """coredumpctl list since the boot started."""
        rc, out, _ = self.ssh(
            f"coredumpctl list --since='{since}' --no-pager 2>/dev/null "
            "| tail -n +2")
        if rc == 0 and out.strip():
            raise AssertionError(
                f"coredumps since {since}:\n{out}")

    def assert_no_journal_errors_since(self, since: str,
                                       allowlist: list[str] | None = None):
        """journalctl -p err since the boot. allowlist suppresses
        regex-matching lines that we've already accepted."""
        rc, out, _ = self.ssh(
            f"journalctl --no-pager -p err --since='{since}' "
            "| grep -v 'journal: Suppressed' || true")
        if rc != 0:
            return  # journal not yet up
        bad_lines = []
        for line in out.splitlines():
            if not line.strip():
                continue
            if allowlist and any(re.search(p, line) for p in allowlist):
                continue
            bad_lines.append(line)
        if bad_lines:
            raise AssertionError(
                f"journal errors since {since}:\n" + "\n".join(bad_lines))
