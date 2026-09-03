#!/bin/sh
# Reports the QML ahead-of-time compile rate.
#
# qmlcachegen turns QML bindings into C++ where it can prove the types. What
# it cannot prove still works -- it just runs interpreted. So the useful
# number is a percentage, not a warning count: `qmllint --compiler=warning`
# prints one line per un-compiled binding (8500+ of them here), which buries
# every real finding and tells you nothing you can act on in aggregate.
#
# Usage: scripts/aot-report.sh [build-dir ...]   (default: build build-apps)
set -eu
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import json, os, sys, collections

roots = sys.argv[1:] or ["build", "build-apps"]
grand_t = grand_o = 0

for root in roots:
    if not os.path.isdir(root):
        print(f"{root}: not built -- skipping")
        continue
    total = ok = 0
    reasons = collections.Counter()
    for d, _, files in os.walk(root):
        for f in files:
            if not f.endswith(".aotstats"):
                continue
            try:
                with open(os.path.join(d, f)) as fh:
                    doc = json.load(fh)
            except (OSError, ValueError):
                continue
            for module in doc.get("modules", []):
                for mf in module.get("moduleFiles", []):
                    for e in mf.get("entries", []):
                        total += 1
                        # 0 = compiled to C++, 1 = skipped, 2 = failed
                        if e.get("codegenResult") == 0:
                            ok += 1
                        else:
                            reasons[e.get("message", "")[:64]] += 1
    if not total:
        print(f"{root}: no .aotstats -- build with Qt 6.6+ to get them")
        continue
    grand_t += total
    grand_o += ok
    print(f"{root}: {ok}/{total} bindings compiled to C++ = {100*ok/total:.1f}%")
    for msg, n in reasons.most_common(5):
        print(f"    {n:5d}  {msg}")

if grand_t:
    print(f"\nTOTAL: {grand_o}/{grand_t} = {100*grand_o/grand_t:.1f}%")
PY
