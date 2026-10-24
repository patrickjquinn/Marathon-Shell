#!/usr/bin/env python3
"""Proof-gate harness for the cross-OS architecture playbook.

Runs each gate's device script on the phone over ssh, collects its raw output
and analyses it on the host. Each gate measures a baseline and a pressure
phase and applies the playbook's go/no-go threshold. Every device step is
counted as ok, skip or fail, and the run undoes what it changed on the phone.

usage: gates.py [--host H] [--password P] [--out DIR] [--set KEY=VALUE ...] GATE...
  GATE: probe g1 g2 g3 g4 g5 g6 g7 | all | analyse RUN_DIR
  --set passes a G_* setting to the device scripts; each script's header
  lists its settings. g1 needs G_KEY and G_BKSP, a letter key and backspace
  of Marathon's keyboard in screen pixels.

probe, g6 and g7 only read. g1-g5 drive the phone (taps, app launches, F-Droid
installs, notifications, a power-key screen-off) and undo each change at exit:
Android stopped again if the run started it, installed apps removed, the
screen woken and unlocked if it was, the app in front restored.

Exit status: 0 when every step passed or was skipped with a reason, 2 when a
step failed, 3 when a gate was inconclusive.
"""
import argparse
import base64
import io
import json
import subprocess
import sys
import tarfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import analyse  # noqa: E402

DEVICE_GATES = ("probe", "g1", "g2", "g3", "g4", "g5")


def run_device(args, gate, raw):
    script = (HERE / "device/lib.sh").read_text() + (HERE / f"device/{gate}.sh").read_text()
    payload = base64.b64encode(script.encode()).decode()
    env = " ".join(f"{k}='{v}'" for k, v in (s.split("=", 1) for s in args.set))
    remote = f"{env} sh -c \"$(echo {payload} | base64 -d)\" gates-{gate}"
    cmd = ["sshpass", "-p", args.password, "ssh", "-n", "-o", "ConnectTimeout=10",
           "-o", "ServerAliveInterval=30", f"root@{args.host}", remote]
    started = time.time()
    with open(raw.parent / "device.log", "wb") as log:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=log)
    raw.mkdir(parents=True, exist_ok=True)
    try:
        with tarfile.open(fileobj=io.BytesIO(proc.stdout)) as tar:
            tar.extractall(raw, filter="data")
    except tarfile.TarError as e:
        (raw / "steps.tsv").write_text(f"transport\tfail\tno result archive: {e}; ssh exit {proc.returncode}\n")
    return time.time() - started


def static_gate6(out):
    """Gate 6: the PermissionController patcher's Python, in Marathon-Deckard."""
    deckard = Path.home() / "Developer/Marathon-Deckard"
    script = deckard / "image/tools/patch-permissioncontroller.sh"
    rows = []
    for path in [script, *sorted((deckard / "image/tools").glob("**/*"))]:
        if path.is_file() and ("python" in path.read_text(errors="ignore") or path.suffix == ".py"):
            rows.append(str(path.relative_to(deckard)))
    rust = (deckard / "image/deckard-image-tools/src/permission_view.rs").exists()
    status = "ok" if not rows and rust else "fail"
    depends = next((line for line in (REPO / "packaging/packages/deckard/APKBUILD").read_text().splitlines()
                    if line.startswith("depends=")), "")
    reasons = (["the patcher calls deckard-image-tools permission-view (Rust); no Python left in image/tools"]
               if status == "ok" else [f"Python remains: {rows}"])
    return {"gate": "g6", "verdict": "DONE" if status == "ok" else "PROCEED", "reasons": reasons,
            "steps": {"ok": int(status == "ok"), "skip": 0, "fail": int(status != "ok")},
            "metrics": {"python_files": rows, "rust_patcher": rust, "deckard_depends": depends}}


def static_gate7(out):
    """Gate 7, host side: build helpers that archive a dirty tree, and CI's
    skipped-test count."""
    checks = []
    for helper in sorted((REPO / "scripts/qemu/lib").glob("build-*-apk.sh")):
        text = helper.read_text()
        if "archive" in text and "HEAD" in text:
            checks.append({"step": f"dirty-guard:{helper.name}",
                           "status": "ok" if "require_clean" in text else "fail"})
    ci = (REPO / "scripts/ci/build-and-test.sh").read_text()
    checks.append({"step": "ci-counts-skips", "status": "ok" if "count-skips" in ci else "fail"})
    checks.append({"step": "ci-strict-tests", "status": "ok" if "MARATHON_TEST_STRICT=1" in ci else "fail"})
    for helper in ("crates/marathon-rt/src/testing.rs", "crates/marathon-audiod/tests/session.rs"):
        strict = "MARATHON_TEST_STRICT" in (REPO / helper).read_text()
        checks.append({"step": f"strict-skip:{helper}", "status": "ok" if strict else "fail"})
    apkbuild = (REPO / "packaging/packages/deckard/APKBUILD").read_text()
    checks.append({"step": "deckard-build-manifest", "status": "ok" if "build-manifest" in apkbuild else "fail"})
    options = next((line for line in apkbuild.splitlines() if line.startswith("options=")), "")
    checks.append({"step": "deckard-manifest-unstripped", "status": "ok" if "!strip" in options else "fail"})
    fails = sum(c["status"] == "fail" for c in checks)
    return {"gate": "g7", "verdict": "DONE" if not fails else "EXECUTE",
            "reasons": [c["step"] for c in checks if c["status"] == "fail"] or ["host-side guards in place"],
            "steps": {"ok": len(checks) - fails, "skip": 0, "fail": fails, "list": checks}, "metrics": {}}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="192.168.68.79")
    ap.add_argument("--password", default="027602")
    ap.add_argument("--out", type=Path, default=REPO / "build/gates")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    ap.add_argument("gates", nargs="+")
    args = ap.parse_args()
    for s in args.set:
        if not s.startswith("G_") or "=" not in s or "'" in s:
            ap.error(f"--set {s}: want G_NAME=value without single quotes")

    if args.gates[0] == "analyse":
        run_dir = Path(args.gates[1])
        gates = sorted(p.name for p in run_dir.iterdir() if (p / "raw").is_dir())
        reanalyse = True
    else:
        run_dir = args.out / time.strftime("%Y%m%d-%H%M%S")
        gates = list(DEVICE_GATES) + ["g6", "g7"] if args.gates == ["all"] else args.gates
        reanalyse = False
    summary = []
    for gate in gates:
        out = run_dir / gate
        out.mkdir(parents=True, exist_ok=True)
        if gate == "g6":
            result = static_gate6(out)
        elif gate == "g7":
            result = static_gate7(out)
            if (run_dir / "probe/result.json").exists():
                result["device"] = json.loads((run_dir / "probe/result.json").read_text())["reasons"]
        elif gate in DEVICE_GATES:
            if not reanalyse:
                print(f"== {gate}: running on {args.host}", file=sys.stderr)
                secs = run_device(args, gate, out / "raw")
                print(f"== {gate}: {secs:.0f} s", file=sys.stderr)
            subprocess.run([sys.executable, str(HERE / "analyse.py"), gate, str(out / "raw"), str(out)],
                           check=False, stdout=subprocess.DEVNULL)
            result = json.loads((out / "result.json").read_text())
        else:
            ap.error(f"unknown gate {gate}")
        (out / "result.json").write_text(json.dumps(result, indent=2, default=str))
        summary.append({"gate": gate, "verdict": result["verdict"], "reasons": result["reasons"],
                        "measured_verdict": result.get("measured_verdict"),
                        "steps": {k: result["steps"][k] for k in ("ok", "skip", "fail")}})
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    for s in summary:
        st = s["steps"]
        measured = f" (measured: {s['measured_verdict']})" if s["measured_verdict"] else ""
        print(f"{s['gate']:6} {s['verdict']:13} ok={st['ok']} skip={st['skip']} fail={st['fail']}  "
              + "; ".join(s["reasons"]) + measured)
    print(f"results: {run_dir}")
    if any(s["steps"]["fail"] for s in summary):
        return 2
    return 3 if any(s["verdict"] == "INCONCLUSIVE" for s in summary) else 0


if __name__ == "__main__":
    sys.exit(main())
