#!/usr/bin/env python3
"""Smoke scenario — boot, confirm shell is alive, screenshot, no crashes.

Used as the cheapest possible regression gate: if this fails, every other
scenario will fail too. Times the boot phases so we can spot regressions
in startup latency.

Run via run_scenarios.py — don't invoke standalone, that path doesn't
own the QEMU process and the harness will hang.
"""

from __future__ import annotations

from pathlib import Path
import sys

# Allow `python -m scenarios.01_boot_smoke` from the automation/ dir.
sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


def run(drv: QemuDriver, since: str) -> int:
    fails = 0

    drv.screenshot("00-firstframe")

    print("==> 1. user@1000 systemd target")
    rc, _, _ = drv.ssh("systemctl is-active --quiet user@1000.service")
    if rc != 0:
        print("  FAIL  user@1000.service not active"); fails += 1
    else:
        print("  OK    user@1000.service active")

    print("==> 2. marathon-shell-bin running")
    rc, out, _ = drv.ssh("pgrep -af marathon-shell-bin | head -3")
    if "marathon-shell-bin" not in out:
        print("  FAIL  marathon-shell-bin not running"); fails += 1
    else:
        print(f"  OK    {out.strip().splitlines()[0]}")

    print("==> 3. wayland compositor socket exposed")
    rc, _, _ = drv.ssh("test -S /run/user/1000/wayland-0 -o "
                        "-S /run/user/1000/marathon-wayland-0")
    if rc != 0:
        print("  FAIL  no wayland socket under /run/user/1000"); fails += 1
    else:
        print("  OK    wayland socket present")

    print("==> 4. no fresh coredumps")
    if not drv.assert_no_coredumps_since(since):
        fails += 1

    print("==> 5. no fresh journal errors (allowlisted)")
    # Allowlist things that fire on every cold boot and aren't actionable.
    # Each entry is a substring; one hit excludes the line.
    allow = [
        "Failed to look up info handle",       # sd-machined w/o machine
        "WARNING: CPU: ",                       # kernel sched warnings
        "ratelimit",
        "pulseaudio.service: Skipped because",  # ConditionUser=!root
        # systemd-veritysetup nags about TPM2 on QEMU (no vTPM attached).
        "TPM2 support disabled",
        # systemd-growfs tries to grow an already-grown partition.
        "systemd-growfs",
        # avahi-daemon's chroot path differs from the Alpine default.
        "chroot.c: open() failed",
        # gnome-keyring runs as the same user as sshd; no auto-unlock.
        "gkr-pam: couldn't unlock",
        "gkr-pam: unable to locate daemon",
        # auditd nuisances on a sandboxed PAM stack.
        "audit:",
        # The QEMU kernel is built without BPF LSM, so systemd cannot
        # link its restrict_filesystems program. Nothing to fix here --
        # it is a kernel capability, not a failure of the image.
        "bpf-restrict-fs",
        # gpt-auto sees the pmOS_root partition and tries to open it as
        # LUKS. It is not encrypted, so this fails. The unit is masked on
        # the kernel cmdline, but these two lines come from the INITRD,
        # which has already run by the time any mask applies -- so they
        # cannot be suppressed, only recognised. Harmless: root mounts
        # fine immediately afterwards.
        "Failed to load LUKS superblock",
        "Failed to start Cryptography Setup for root",
    ]
    if not drv.assert_no_journal_errors_since(since, allowlist=allow):
        fails += 1

    drv.screenshot("99-final")
    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py, not standalone")
    sys.exit(2)
