#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Applies a judge agent's verdicts to an evaluation run.

usage: merge-verdicts.py JUDGE_FILE VERDICTS_FILE

JUDGE_FILE is the judge-<stamp>.json the eval writes (rubric items keyed
"<run index>:<turn>"); VERDICTS_FILE is the agent's answer, a JSON object
{"<key>": {"pass": bool, "reason": "..."}}. A rubric item with no verdict
counts as a failure. Writes run-<stamp>.judged.json next to the run and
prints the summary the eval prints: per-task pass rates when tasks were
repeated, per category, and the total.
"""

import json
import os
import sys
from collections import defaultdict


def main():
    judge_path, verdicts_path = sys.argv[1:3]
    judge = json.load(open(judge_path))
    verdicts = json.load(open(verdicts_path))
    run_path = os.path.join(os.path.dirname(judge_path), judge["run"])
    run = json.load(open(run_path))
    for i, task in enumerate(run["tasks"]):
        for j in task.get("judgments", []):
            key = f"{i}:{j['turn']}"
            v = verdicts.get(key)
            if v is None:
                task["failures"].append(f"turn {j['turn']}: judge: no verdict")
            elif not v.get("pass"):
                task["failures"].append(f"turn {j['turn']}: judge: {v.get('reason', '')}")
        task["pass"] = not task["failures"]
    out = run_path.replace(".json", ".judged.json")
    json.dump(run, open(out, "w"), indent=1)

    rate = defaultdict(lambda: [0, 0])
    cats = defaultdict(lambda: [0, 0])
    for t in run["tasks"]:
        rate[t["id"]][1] += 1
        cats[t["category"]][1] += 1
        if t["pass"]:
            rate[t["id"]][0] += 1
            cats[t["category"]][0] += 1
    print("failures:")
    for t in run["tasks"]:
        if not t["pass"]:
            print(f"  {t['id']:<28} {' | '.join(t['failures'])[:300]}")
    print("\nper task (passes of runs), where any failed:")
    for k in sorted(rate):
        p, n = rate[k]
        if p < n:
            print(f"  {k:<28} {p}/{n}")
    print(f"\n{'category':<14} pass")
    for c in sorted(cats):
        print(f"{c:<14} {cats[c][0]}/{cats[c][1]}")
    passed = sum(1 for t in run["tasks"] if t["pass"])
    print(f"\n{passed}/{len(run['tasks'])} tasks passed (judged); written to {out}")


if __name__ == "__main__":
    main()
