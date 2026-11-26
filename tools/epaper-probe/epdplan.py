#!/usr/bin/env python3
"""Compile experiments.toml into an epdprobe plan and a JSON manifest for epdanalyze.py."""

import argparse
import copy
import json
import random
import tomllib
from pathlib import Path

PW, PH = 800, 600
GRID_X, GRID_Y, PATCH, PITCH = 52, 72, 96, 120
REF = [352, 8, 96, 56]
FIDUCIALS = [[12, 12, 40, 40], [748, 12, 40, 40], [12, 548, 40, 40], [748, 548, 40, 40]]
PAGE = [52, 72, 696, 456]
RAMP_ROW = (80, 72, 40, 96)      # 16 cells of 40x96 on grid row 0
DRAMP_ROW = (80, 312, 40, 96)    # dithered ramp on grid row 2
LOREM = ("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG. PACK MY BOX WITH FIVE DOZEN "
         "LIQUOR JUGS. SPHINX OF BLACK QUARTZ, JUDGE MY VOW. HOW VEXINGLY QUICK DAFT "
         "ZEBRAS JUMP. 0123456789 - THE FIVE BOXING WIZARDS JUMP QUICKLY.")


def L(k):
    return round(255 * k / 15)


def patch_rect(i):
    return [GRID_X + (i % 6) * PITCH, GRID_Y + (i // 6) * PITCH, PATCH, PATCH]


def merge(a, b):
    return {**copy.deepcopy(a), **b}


class Trial:
    def __init__(self, exp, name, mode, section="fast"):
        self.exp, self.name, self.mode, self.section = exp, name, mode, section
        self.lines, self.flips, self.steps = [], [], []
        self.rois, self.features, self.params = set(), {}, {}
        self.patches = [255] * 24
        self.duration_ms = self.mark_ms = 0.0

    def emit(self, line):
        self.lines.append(line)

    def wait(self, ms):
        self.emit(f"sleep {ms:.1f}")
        self.duration_ms += ms

    def mark(self):
        self.emit("mark")
        self.mark_ms = self.duration_ms

    def at(self, ms):
        self.emit(f"at {ms:.2f}")
        self.duration_ms = max(self.duration_ms, self.mark_ms + ms)

    def note(self, text):
        self.emit(f"note {text}")

    def set_patch(self, i, v):
        self.patches[i] = v
        r = patch_rect(i)
        val = " ".join(map(str, v)) if isinstance(v, list) else str(v)
        self.emit(f"rect {r[0]} {r[1]} {r[2]} {r[3]} {val}")

    def draw_patches(self):
        self.emit("bg 255")
        for i, v in enumerate(self.patches):
            if v != 255:
                self.set_patch(i, v)

    def flip(self, role, patches=True):
        self.emit("flip")
        self.flips.append({"idx": len(self.flips), "role": role,
                           "patches": list(self.patches) if patches else None})
        self.duration_ms += 17
        return len(self.flips) - 1

    def step(self, roi, flip, frm, to):
        self.rois.add(roi)
        self.steps.append({"roi": roi, "flip": flip, "from": frm, "to": to})

    def start(self, conv, poll=False):
        self.emit("regsnap")
        if poll:
            self.emit("poll on")
        self.emit(f"mode {self.mode}")
        self.emit("clear")
        self.wait(conv["idle_ms"])

    def settle(self, conv, rng):
        self.wait(conv["settle_ms"] + rng.uniform(0, conv["phase_ms"]))

    def finish(self, watch_ms):
        self.wait(watch_ms)
        self.emit("poll off")

    def manifest(self, seq):
        return {"seq": seq, "id8": seq & 255, "exp": self.exp, "name": self.name,
                "mode": self.mode, "section": self.section, "flips": self.flips,
                "steps": self.steps, "rois": sorted(self.rois, key=lambda r: int(r[1:])),
                "features": self.features, "params": self.params}


def jit(rng, conv):
    return rng.uniform(-conv["jitter_ms"], conv["jitter_ms"])


def build_E0(c, conv, rng):
    t = Trial("E0", "E0-rig", "quality")
    t.params = {"strobes": c["strobes"]}
    t.start(conv)
    t.draw_patches()
    t.flip("base")
    t.wait(conv["settle_ms"])
    for k in range(c["strobes"]):
        t.emit(f"strobe {k}")
        t.duration_ms += 250
        t.wait(c["gap_ms"])
    t.note("win static0")
    t.wait(c["static_ms"])
    t.note("win static1")
    t.rois.update(f"P{i}" for i in range(24))
    return [t]


def e1_trials(exp, c, conv, rng):
    out = []
    for mode in c["modes"]:
        for r in range(c["repeats"]):
            t = Trial(exp, f"{exp}-{mode}-r{r}", mode)
            t.params = {"repeat": r}
            patches = rng.sample(range(24), len(c["transitions"]))
            t.start(conv, c.get("poll", False))
            for p, (a, _) in zip(patches, c["transitions"]):
                t.patches[p] = L(a)
            t.draw_patches()
            t.flip("base")
            t.settle(conv, rng)
            for p, (_, b) in zip(patches, c["transitions"]):
                t.set_patch(p, L(b))
            f = t.flip("T")
            t.mark()
            for p, (a, b) in zip(patches, c["transitions"]):
                t.step(f"P{p}", f, a, b)
            t.finish(c["watch_ms"])
            out.append(t)
    return out


def build_E1(c, conv, rng):
    return e1_trials("E1", c, conv, rng)


def build_E12(c, conv, rng):
    return e1_trials("E12", c, conv, rng)


def build_E2(c, conv, rng):
    out = []
    for mode, deltas in c["deltas"].items():
        for var, b in c["variants"].items():
            for d in deltas:
                for r in range(c["repeats"]):
                    t = Trial("E2", f"E2-{var}-{mode}-d{d}-r{r}", mode)
                    a = [c["a"], c["pair"]] if var == "inbox" else [c["a"]]
                    t.params = {"variant": var, "delta": d, "a": [f"P{p}" for p in a],
                                "b": f"P{b}"}
                    t.start(conv, c.get("poll", False))
                    t.draw_patches()
                    t.flip("base")
                    t.settle(conv, rng)
                    for p in a:
                        t.set_patch(p, 0)
                    fa = t.flip("A")
                    t.mark()
                    t.at(d + jit(rng, conv))
                    t.set_patch(b, 0)
                    fb = t.flip("B")
                    for p in a:
                        t.step(f"P{p}", fa, 15, 0)
                    t.step(f"P{b}", fb, 15, 0)
                    t.finish(c["watch_ms"])
                    out.append(t)
    return out


def build_E3(c, conv, rng):
    out = []
    p = c["patch"]
    for mode in c["modes"]:
        cases = [(d, tg) for d in c["deltas"] for tg in c["targets"]]
        if c["burst"]:
            cases.append(("burst", None))
        for d, tg in cases:
            for r in range(c["repeats"]):
                name = f"E3-{mode}-burst-r{r}" if d == "burst" else f"E3-{mode}-d{d}-to{tg}-r{r}"
                t = Trial("E3", name, mode)
                t.start(conv, c.get("poll", False))
                t.draw_patches()
                t.flip("base")
                t.settle(conv, rng)
                if d == "burst":
                    seq = c["burst"]
                    t.params = {"burst": seq, "gap_ms": c["burst_gap_ms"]}
                    prev = 15
                    for k, v in enumerate(seq):
                        if k:
                            t.at(k * c["burst_gap_ms"] + jit(rng, conv))
                        t.set_patch(p, L(v))
                        f = t.flip(f"burst{k}")
                        if not k:
                            t.mark()
                        t.step(f"P{p}", f, prev, v)
                        prev = v
                else:
                    t.params = {"delta": d, "target": tg}
                    t.set_patch(p, 0)
                    f1 = t.flip("T")
                    t.mark()
                    t.at(d + jit(rng, conv))
                    t.set_patch(p, L(tg))
                    f2 = t.flip("T2")
                    t.step(f"P{p}", f1, 15, 0)
                    t.step(f"P{p}", f2, 0, tg)
                t.finish(c["watch_ms"])
                out.append(t)
    return out


def build_E4(c, conv, rng):
    out = []
    for r in range(c["repeats"]):
        t = Trial("E4", f"E4-r{r}", c["mode"])
        t.params = {"pairs": c["pairs"], "period_ms": c["period_ms"]}
        t.start(conv)
        for pr in c["pairs"]:
            t.patches[pr["patch"]] = pr["a"]
            t.rois.add(f"P{pr['patch']}")
        t.draw_patches()
        t.flip("base")
        t.settle(conv, rng)
        for k in range(2 * c["cycles"]):
            if k:
                t.at(k * c["period_ms"] + jit(rng, conv))
            for pr in c["pairs"]:
                t.set_patch(pr["patch"], pr["b"] if k % 2 == 0 else pr["a"])
            t.flip(f"alt{k}")
            if not k:
                t.mark()
        t.rois.add("P0")
        t.finish(conv["watch_ms"])
        out.append(t)
    return out


def ramp_feature(name, cell, n=16, cols=16):
    x, y, w, h = cell
    return {name: {"type": "grid", "rect": [x, y, w * cols, h * (n // cols)], "nx": cols,
                   "ny": n // cols}}


def static_trial(exp, name, mode, conv, draw, features):
    t = Trial(exp, name, mode, section="static")
    t.start(conv)
    t.emit("bg 255")
    for line in draw:
        t.emit(line)
    t.flip("scene", patches=False)
    t.wait(conv["static_hold_ms"])
    t.features = features
    return t


def build_E5(c, conv, rng):
    return [
        static_trial("E5", "E5-ramp256", c["mode"], conv, ["ramp 144 108 32 24 16 16 256 0"],
                     {"ramp256": {"type": "grid", "rect": [144, 108, 512, 384], "nx": 16, "ny": 16}}),
        static_trial("E5", "E5-ramp16", c["mode"], conv, ["ramp 80 252 40 96 16 1 16 0"],
                     ramp_feature("ramp16", (80, 252, 40, 96))),
    ]


def text_block(t, x, y, lines, scale=2):
    words = LOREM.split()
    per = (PW - 2 * x) // (6 * scale)
    k = 0
    for i in range(lines):
        s = ""
        while len(s) + len(words[k % len(words)]) + 1 <= per:
            s += words[k % len(words)] + " "
            k += 1
        t.emit(f"text {x} {y + i * 10 * scale} {scale} 0 {s.strip()}")


def build_E6(c, conv, rng):
    out = []
    for d in c["a_deltas"] + [None]:
        for r in range(c["a_repeats"]):
            t = Trial("E6", f"E6a-{'ctl' if d is None else f'd{d}'}-r{r}", "quality")
            t.params = {"part": "a", "switch_ms": d}
            t.start(conv)
            t.draw_patches()
            t.flip("base")
            t.settle(conv, rng)
            t.set_patch(7, 0)
            f = t.flip("T")
            t.mark()
            if d is not None:
                t.at(d + jit(rng, conv))
                t.emit("mode fast")
            t.step("P7", f, 15, 0)
            t.finish(conv["watch_ms"])
            out.append(t)
    for r in range(c["b_repeats"]):
        t = Trial("E6", f"E6b-r{r}", "fast")
        t.params = {"part": "b"}
        t.start(conv)
        t.emit("bg 255")
        t.emit("ramp {} {} {} {} 16 1 16 0".format(*RAMP_ROW))
        text_block(t, 60, 320, 10)
        t.flip("base", patches=False)
        t.mark()
        t.at(conv["settle_ms"] + rng.uniform(0, conv["phase_ms"]))
        t.note("switch")
        t.emit("mode quality")
        t.finish(c["b_watch_ms"])
        t.features = {**ramp_feature("ramp", RAMP_ROW),
                      "text": {"type": "grid", "rect": [60, 320, 680, 200], "nx": 1, "ny": 1},
                      "white": {"type": "grid", "rect": [52, 192, 96, 96], "nx": 1, "ny": 1}}
        out.append(t)
    pairs = c["c_pairs"] + [c["c_last"]]
    for a, b in pairs:
        t = Trial("E6", f"E6c-{a}-{b}", a)
        t.params = {"part": "c", "from": a, "to": b}
        t.start(conv)
        for i in range(24):
            t.patches[i] = L((i * 7) % 16)
        t.draw_patches()
        t.flip("base")
        t.mark()
        t.at(conv["settle_ms"] + rng.uniform(0, conv["phase_ms"]))
        t.note("switch")
        t.emit(f"mode {b}")
        t.wait(c["c_watch_ms"])
        for i in range(24):
            t.set_patch(i, L(15 - (i * 7) % 16))
        f = t.flip("change")
        for i in range(24):
            t.step(f"P{i}", f, (i * 7) % 16, 15 - (i * 7) % 16)
        t.finish(c["c_watch_ms"])
        out.append(t)
    return out


def build_E7(c, conv, rng):
    out = []
    feats = {**ramp_feature("ramp", RAMP_ROW), **ramp_feature("dramp", DRAMP_ROW)}
    draw = ["ramp {} {} {} {} 16 1 16 0".format(*RAMP_ROW),
            "ramp {} {} {} {} 16 1 16 1".format(*DRAMP_ROW)]
    for mode in c["a_modes"]:
        for r in range(c["a_repeats"]):
            t = Trial("E7", f"E7a-{mode}-r{r}", mode)
            t.params = {"part": "a"}
            t.start(conv)
            t.emit("bg 255")
            t.flip("base", patches=False)
            t.settle(conv, rng)
            for line in draw:
                t.emit(line)
            t.flip("T", patches=False)
            t.mark()
            t.finish(conv["watch_ms"])
            t.features = feats
            out.append(t)
    for mode in c["b_modes"]:
        tr = static_trial("E7", f"E7b-{mode}", mode, conv, draw, feats)
        tr.params = {"part": "b"}
        out.append(tr)
    region = [172, 192, 216, 216]
    for r in range(c["c_repeats"]):
        t = Trial("E7", f"E7c-r{r}", "fast")
        t.params = {"part": "c", "level": c["c_level"]}
        t.start(conv)
        t.emit("bg 255")
        t.emit("checker {} {} {} {} {} 0 255".format(*region, c["c_cell"]))
        t.flip("base", patches=False)
        t.wait(c["c_hold_ms"])
        t.emit("mode quality")
        t.wait(200)
        t.emit("rect {} {} {} {} {}".format(*region, L(c["c_level"])))
        t.flip("T", patches=False)
        t.mark()
        t.wait(conv["watch_ms"])
        t.note("win final0")
        t.wait(800)
        t.note("win final1")
        t.emit("poll off")
        t.features = {"exblack": {"type": "checker", "rect": region, "cell": c["c_cell"], "parity": 0},
                      "exwhite": {"type": "checker", "rect": region, "cell": c["c_cell"], "parity": 1}}
        out.append(t)
        t = Trial("E7", f"E7c-ref-r{r}", "quality")
        t.params = {"part": "cref", "level": c["c_level"]}
        t.start(conv)
        t.patches[7], t.patches[8] = 0, 255
        t.draw_patches()
        t.flip("base")
        t.settle(conv, rng)
        t.set_patch(7, L(c["c_level"]))
        t.set_patch(8, L(c["c_level"]))
        f = t.flip("T")
        t.mark()
        t.step("P7", f, 0, c["c_level"])
        t.step("P8", f, 15, c["c_level"])
        t.wait(conv["watch_ms"])
        t.note("win final0")
        t.wait(800)
        t.note("win final1")
        t.emit("poll off")
        out.append(t)
    return out


def build_E8(c, conv, rng):
    out = []
    x0, y0, h = 100, 252, 96
    span = c["speed_px"] * c["frames"] + c["bar_w"]
    for k in c["ks"]:
        t = Trial("E8", f"E8-k{k}", c["mode"])
        t.params = {"k": k, "x0": x0, "speed_px": c["speed_px"], "frames": c["frames"],
                    "bar_w": c["bar_w"]}
        t.start(conv)
        t.emit("bg 255")
        t.flip("base", patches=False)
        t.settle(conv, rng)
        t.mark()
        t.emit(f"anim {x0} {y0} {c['bar_w']} {h} 0 {c['speed_px']} {c['frames']} {k}")
        for f in range(c["frames"]):
            t.flips.append({"idx": len(t.flips), "role": "anim", "patches": None,
                            "x": x0 + c["speed_px"] * k * (f // k)})
        t.duration_ms += c["frames"] * 16.7
        t.finish(c["watch_ms"])
        t.features = {"bar": {"type": "profile", "rect": [x0, y0 + 24, span, h - 48],
                              "nbins": span // 4}}
        out.append(t)
    return out


def build_E10(c, conv, rng):
    out = []
    for var in c["variants"]:
        for r in range(c["repeats"]):
            t = Trial("E10", f"E10-{var}-r{r}", "quality")
            t.params = {"variant": var}
            t.start(conv)
            t.emit("page 0 0")
            t.flip("base", patches=False)
            t.settle(conv, rng)
            change = [f"rect {x} {y} {w} {h} 0" for x, y, w, h in map(patch_rect, (0, 1, 2))]
            if var == "change-then-clear":
                for line in change:
                    t.emit(line)
                t.flip("change", patches=False)
            t.mark()
            t.emit("clear")
            if var == "change-during-clear":
                t.at(c["during_ms"])
                for line in change:
                    t.emit(line)
                t.flip("change", patches=False)
            t.wait(c["watch_ms"])
            t.note("win final0")
            t.wait(500)
            t.note("win final1")
            t.emit("poll off")
            t.rois.update({"P0", "P1", "P2", "P9"})
            out.append(t)
    return out


def build_E11(c, conv, rng):
    out = []
    for var in c["variants"]:
        for k in c["steps"]:
            d = int(var == "dithered")
            t = Trial("E11", f"E11-{var}-k{k}", "quality")
            t.params = {"variant": var, "steps": k}
            t.start(conv)
            t.emit(f"page 0 {d}")
            t.flip("base", patches=False)
            t.settle(conv, rng)
            t.emit("mode fast")
            t.mark()
            for s in range(1, k + 1):
                t.at(s * c["step_ms"])
                t.emit(f"page {s * c['step_px']} {d}")
                t.flip(f"scroll{s}", patches=False)
            t.wait(500)
            t.emit("mode quality")
            t.wait(c["settle_ms"])
            t.note("win A0")
            t.wait(800)
            t.note("win A1")
            t.emit("clear")
            t.wait(c["settle_ms"])
            t.note("win B0")
            t.wait(800)
            t.note("win B1")
            t.emit("poll off")
            t.features = {"page": {"type": "grid", "rect": PAGE, "nx": 29, "ny": 19}}
            out.append(t)
    return out


def build_E14(c, conv, rng):
    t = Trial("E14", "E14-observe", None, section="observe")
    t.params = {"observe_s": c["observe_s"]}
    t.emit(f"observe {c['observe_s'] * 1000}")
    t.duration_ms += c["observe_s"] * 1000
    return [t]


BUILDERS = {k[6:]: v for k, v in globals().items() if k.startswith("build_")}


def banner(lines, text):
    w = len(text) * 6 * 4
    lines += ["bg 255", f"text {(PW - w) // 2} {PH // 2 - 14} 4 0 {text}", "flip"]


def compile_plan(cfg, profile, seed):
    prof = cfg["profile"][profile]
    conv = merge(cfg["conventions"], prof.get("conventions", {}))
    rng = random.Random(seed)
    trials = []
    for exp in prof["experiments"]:
        trials += BUILDERS[exp](merge(cfg[exp], prof.get(exp, {})), conv, rng)

    observe = [t for t in trials if t.section == "observe"]
    static = [t for t in trials if t.section == "static"]
    fast = [t for t in trials if t.section == "fast"]
    first = [t for t in fast if t.exp == "E0"]
    last = [t for t in fast if t.name.endswith("-clean")]
    rest = [t for t in fast if t not in first and t not in last]
    rng.shuffle(rest)
    fast = first + rest + last

    lines = [f"plan 1 profile={profile} seed={seed}"]
    order, seq = [], 0
    if observe:
        for t in observe:
            for tag in ("start", "end"):
                seq += 1
                order.append((seq, t if tag == "start" else None))
                lines.append(f"trial {seq} {seq & 255} E14-{tag}")
                if tag == "start":
                    lines += t.lines
    else:
        wake = ["waittouch", f"sleep {conv['start_delay_ms']}"]
        lines += ["mode quality", "bg 255", "flip"] + wake
        for group, title in ((fast, None), (static, "SWITCH CAMERA TO 4K")):
            if not group:
                continue
            if title:
                banner(lines, title)
                lines += wake
            for t in group:
                seq += 1
                order.append((seq, t))
                lines.append(f"trial {seq} {seq & 255} {t.name}")
                lines += t.lines
                lines.append("end")
        banner(lines, "DONE")

    total_ms = sum(t.duration_ms + 250 for _, t in order if t) + 2 * conv["start_delay_ms"]
    manifest = {
        "version": 1, "profile": profile, "seed": seed, "panel": [PW, PH],
        "layout": {"patches": [patch_rect(i) for i in range(24)], "ref": REF,
                   "fiducials": FIDUCIALS, "fiducial_hole": 0, "page": PAGE},
        "levels": [L(k) for k in range(16)], "conventions": conv,
        "estimated_s": round(total_ms / 1000),
        "trials": [t.manifest(s) for s, t in order if t],
    }
    return "\n".join(lines) + "\n", manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", default=Path(__file__).with_name("experiments.toml"))
    ap.add_argument("--profile", default="full")
    ap.add_argument("--seed", type=int, default=None, help="default: random, recorded in the plan")
    ap.add_argument("--out", required=True, help="writes OUT.plan and OUT.json")
    a = ap.parse_args()
    seed = a.seed if a.seed is not None else random.SystemRandom().randrange(1 << 31)
    cfg = tomllib.loads(Path(a.config).read_text())
    plan, manifest = compile_plan(cfg, a.profile, seed)
    Path(a.out + ".plan").write_text(plan)
    Path(a.out + ".json").write_text(json.dumps(manifest, indent=1))
    n = len(manifest["trials"])
    print(f"{a.out}.plan: {n} trials, seed {seed}, about {manifest['estimated_s'] / 60:.1f} min")


if __name__ == "__main__":
    main()
