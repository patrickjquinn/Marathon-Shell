#!/usr/bin/env python3
"""Boot Marathon's QEMU image, run scripted UI scenarios, capture artifacts.

This is the loop we use INSTEAD of flash → eyeball → ssh-dance. Each run
produces tests/screenshots/<utc-stamp>/ containing:
  - PNG screenshot per scenario step
  - journal.txt   (full journalctl since boot)
  - failed.txt    (systemctl --failed)
  - coredumps.txt (coredumpctl list since boot)
  - report.md     (per-scenario pass/fail summary)

Exits 0 if every scenario passed, 1 otherwise. Designed for CI but cheap
enough to run locally on every meaningful change.

Usage:
    scripts/qemu/automation/run_scenarios.py            # all scenarios
    scripts/qemu/automation/run_scenarios.py 01 02      # specific ones
    scripts/qemu/automation/run_scenarios.py --keep-qemu  # leave VM up
                                                          # for poking
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from qemu_driver import QemuDriver  # noqa: E402

REPO_ROOT = HERE.parents[2]  # scripts/qemu/automation → Marathon-Shell
DURANIUM_DIR = Path(os.environ.get(
    "DURANIUM_DIR",
    str(Path.home() / ".cache/marathon-build/duranium")))
QEMU_OUT = DURANIUM_DIR / "mkosi.output/qemu-aarch64_marathon_edge"
EFI_CODE = Path("/usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2")
EFI_VARS_TEMPLATE = Path("/usr/share/edk2/aarch64/QEMU_EFI-qemuvars-pflash.qcow2")
EFI_VARS = Path("/tmp/marathon-auto-efivars.qcow2")
QMP_SOCK = Path("/tmp/marathon-auto-qmp.sock")
SERIAL_SOCK = Path("/tmp/marathon-auto-serial.sock")
SSH_PORT = 2229


def find_image() -> Path:
    raws = sorted(QEMU_OUT.glob("qemu-aarch64_marathon_edge_*.raw"),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    raws = [r for r in raws if r.name.count(".") == 1]  # not .usr-arm64.*.raw
    if not raws:
        sys.exit(f"no qemu image under {QEMU_OUT} — run scripts/build-qemu-image.sh first")
    return raws[0]


def extract_uki(cache: Path = Path("/tmp/marathon-auto-uki")):
    """Pull kernel+initrd out of the UKI so QEMU can boot them directly.

    Python port of scripts/qemu/lib/extract-uki.sh. The UEFI->systemd-boot
    ->UKI path has no root= and leans on gpt-auto, which duranium routes
    through the masked systemd-cryptsetup@pmOS_root; the initrd then waits
    for root forever while slirp still accepts :22, so the guest looks
    "booted" and ssh fails with a banner timeout.
    """
    ukis = sorted(QEMU_OUT.glob("qemu-aarch64_marathon_edge_*.efi"),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    if not ukis:
        sys.exit(f"no UKI (.efi) in {QEMU_OUT}")
    uki = ukis[0]
    cache.mkdir(parents=True, exist_ok=True)
    kernel, initrd = cache / "vmlinuz", cache / "initrd"
    stamp = cache / ".uki-source"
    have = kernel.exists() and initrd.exists() and kernel.stat().st_size > 0
    same = stamp.read_text().strip() == str(uki) if stamp.exists() else False
    fresh = have and uki.stat().st_mtime <= kernel.stat().st_mtime
    if not (have and same and fresh):
        print(f"==> extracting kernel+initrd from UKI: {uki.name}")
        for sect, out in ((".linux", kernel), (".initrd", initrd)):
            subprocess.run(["objcopy", "-O", "binary", f"--only-section={sect}",
                            str(uki), str(out)], check=True)
        stamp.write_text(str(uki) + "\n")
    return kernel, initrd


def launch_qemu(img: Path) -> subprocess.Popen:
    for s in (QMP_SOCK, SERIAL_SOCK):
        s.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "resize", "-f", "raw", "-q", str(img), "20G"],
                   check=False, stderr=subprocess.DEVNULL)
    kernel, initrd = extract_uki()
    # No SYSTEMD_SULOGIN_FORCE: headless, it turns a non-fatal early
    # failure into a hung emergency shell instead of a boot.
    direct_cmdline = (
        "root=LABEL=pmOS_root rw rootwait "
        "systemd.wants=network.target "
        "systemd.mask=systemd-repart.service systemd.mask=cryptsetup.target "
        "systemd.mask=systemd-cryptsetup@pmOS_root.service "
        # gpt-auto names the instance after the partition it finds, which
        # here is "root", not "pmOS_root" -- so the mask above never
        # matched and systemd-cryptsetup@root.service failed on every
        # boot, trying to load a LUKS superblock off an unencrypted
        # partition. That was the entirety of 01_boot_smoke's failure.
        "systemd.mask=systemd-cryptsetup@root.service module_blacklist=vmw_vmci "
        "loglevel=4 console=tty0 console=ttyAMA0,115200")
    cmd = [
        "qemu-system-aarch64",
        "-machine", "type=virt,memory-backend=mem", "-cpu", "host", "-accel", "kvm",
        "-smp", "2", "-m", "2048M",
        "-object", "memory-backend-memfd,id=mem,size=2048M,share=on",
        "-object", "rng-random,filename=/dev/urandom,id=rng0",
        "-device", "virtio-rng-pci,rng=rng0",
        "-device", "virtio-balloon",
        "-nic", f"user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:{SSH_PORT}-:22",
        "-drive", f"file={img},format=raw,if=none,id=hd0,cache=writeback,discard=unmap",
        "-device", "virtio-blk-pci,drive=hd0,bootindex=1",
        # virtio-gpu-pci (no -gl) exposes a host-readable framebuffer that
        # QMP screendump can consume. The -gl variant + egl-headless gave
        # "no surface" because GL surfaces never round-trip through QEMU's
        # display pipeline. SW rendering is fine here — Marathon's QML
        # scene-graph is small enough to render at >5 fps in software.
        "-device", "virtio-gpu-pci,xres=720,yres=1440",
        "-device", "virtio-keyboard-pci",
        "-device", "virtio-tablet-pci",
        "-display", "none",
        "-vnc", "127.0.0.1:7",  # :5907 — only for human poking, not the harness
        "-serial", f"unix:{SERIAL_SOCK},server,nowait",
        "-qmp", f"unix:{QMP_SOCK},server,nowait",
        "-kernel", str(kernel), "-initrd", str(initrd), "-append", direct_cmdline,
    ]
    log = open("/tmp/marathon-auto-qemu.log", "w")
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)


def collect_artifacts(drv: QemuDriver, run_dir: Path, since: str):
    for fname, cmd in [
        ("journal.txt", f"journalctl --no-pager --since '{since}'"),
        ("journal-err.txt", f"journalctl --no-pager -p err --since '{since}'"),
        ("failed.txt", "systemctl --failed --no-pager"),
        ("coredumps.txt", f"coredumpctl list --no-pager --since '{since}' 2>/dev/null || true"),
        ("dmesg-err.txt", "dmesg --level=err,crit,alert,emerg --color=never"),
    ]:
        _, out, _ = drv.ssh(cmd)
        (run_dir / fname).write_text(out)


def discover_scenarios(filter_args: list[str]) -> list[Path]:
    scs = sorted((HERE / "scenarios").glob("*.py"))
    if not filter_args:
        return scs
    want = set(filter_args)
    return [s for s in scs if any(s.name.startswith(w) for w in want)]


def run_scenario(path: Path, drv: QemuDriver, run_dir: Path, since: str) -> tuple[str, int]:
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not hasattr(mod, "run"):
        return path.name, -1
    scenario_run_dir = run_dir / path.stem
    scenario_run_dir.mkdir(exist_ok=True)
    prev_run_dir = drv.run_dir
    drv.run_dir = scenario_run_dir
    try:
        return path.name, mod.run(drv, since)
    finally:
        drv.run_dir = prev_run_dir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", help="prefix filter, e.g. 01 02")
    ap.add_argument("--keep-qemu", action="store_true",
                    help="leave the VM running after scenarios finish")
    ap.add_argument("--no-launch", action="store_true",
                    help="don't start QEMU — connect to an already-running instance "
                         "on the standard QMP/SSH sockets")
    ap.add_argument("--image", help="explicit raw image path")
    args = ap.parse_args()

    if args.no_launch:
        img_label = "(existing VM)"
    else:
        img = Path(args.image) if args.image else find_image()
        img_label = str(img)
    print(f"==> image:  {img_label}")
    print(f"==> qmp:    {QMP_SOCK}")
    print(f"==> ssh:    127.0.0.1:{SSH_PORT}")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REPO_ROOT / "tests" / "screenshots" / stamp
    run_dir.mkdir(parents=True, exist_ok=True)
    print(f"==> run dir:{run_dir}")

    if args.no_launch:
        proc = None
    else:
        proc = launch_qemu(img)
    qemu_started = time.monotonic()
    # Record the boot start so the journal allowlist filter only sees fresh entries.
    since = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    drv = QemuDriver(qmp_sock=QMP_SOCK, ssh_port=SSH_PORT,
                     run_dir=run_dir / "_setup")
    drv.run_dir.mkdir(exist_ok=True)
    try:
        print("==> waiting for QMP")
        drv.connect()
        print(f"==> resolution: {drv.width}x{drv.height}")
        print("==> waiting for sshd (up to 4 min)")
        drv.wait_for_ssh(timeout=240)
        print(f"==> boot ready in {time.monotonic() - qemu_started:.1f} s")
        time.sleep(15)  # let greetd auto-login + compositor settle

        results: list[tuple[str, int]] = []
        for sc in discover_scenarios(args.scenarios):
            print(f"\n=== {sc.name} ===")
            name, fails = run_scenario(sc, drv, run_dir, since)
            results.append((name, fails))
            print(f"=== {name}: {fails} fail(s)\n")

        collect_artifacts(drv, run_dir, since)

        # Write the report.
        total_fails = sum(max(0, f) for _, f in results)
        with open(run_dir / "report.md", "w") as fh:
            fh.write(f"# Marathon QEMU automation run — {stamp}\n\n")
            fh.write(f"image: `{img_label}`  ·  resolution: {drv.width}×{drv.height}\n\n")
            fh.write("| Scenario | Fails |\n|---|---|\n")
            for name, f in results:
                fh.write(f"| {name} | {f} |\n")
            fh.write(f"\n**Total: {total_fails} failure(s).**\n")
        print(f"\n==> report: {run_dir / 'report.md'}")
        print(f"==> total fails: {total_fails}")
        sys.exit(0 if total_fails == 0 else 1)
    finally:
        if proc is not None and not args.keep_qemu:
            try:
                drv.shutdown()
            except Exception:
                pass
            try:
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=10)
            except Exception:
                proc.kill()
        elif proc is not None:
            print(f"\n==> keeping QEMU alive (pid {proc.pid}, ssh :{SSH_PORT})")
        else:
            print(f"\n==> --no-launch: QEMU left as we found it")


if __name__ == "__main__":
    main()
