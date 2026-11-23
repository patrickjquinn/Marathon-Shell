# The GPU as the e-paper timing controller (MP01)

Status: design, nothing implemented. Device: Minimal Phone MP01 (MT6789, Mali-G57 MC2 on
Panfrost, mainline Linux 7.0, Marathon's Qt Quick/Wayland compositor). The 4.3" 800×600, 16-grey
E Ink panel sits behind a Pango PGC4KL CPLD (`mipi2tcon_top`, fw 0x36), which is fed by 4-lane
MIPI DSI. Related notes:

- `reports/Fast E Ink refresh for MP01.md` and `research_notes/Fast E Ink refresh for MP01/` in
  the main checkout: research on the shipped CPLD, waveforms and products.
- `~/q25-build/mp01-cpld-firmware-assessment.md`: flash safety and why a Caster port does not fit.
- `docs/design/EPAPER_DISPLAY_CLASS.md` (branch `feat/mp01-eink`): shell policy for the
  e-paper display class. This document builds on it and supersedes its "Refresh scheduling"
  section once Tier A lands.
- `devices/minimal/mp01/kernel/eink-refresh-api.md` (branch `feat/mp01-eink`): the interim
  `refresh_mode`/`full_refresh` ABI and the KMS property it should become.

Numbers marked *est.* are engineering estimates. Numbers marked *sim* come from
`tools/epaper-tcon-sim/epd_sim.py`, a toy ink model. Neither kind is an MP01 measurement. §4 is
the plan that replaces them.

## 0. Summary

**What the physics allows.** A black/white pixel settles in roughly 100–150 ms. Sixteen greys
take 450–750 ms at ±15 V. E Ink's own mode table at 25 °C and 85 Hz lists A2 at 120 ms
(~10 frames), DU at 260 ms and GC16/GL16 at 450 ms
([E Ink mode declaration](https://www.waveshare.net/w/upload/c/c4/E-paper-mode-declaration.pdf)).
No controller makes ink faster. The best ones stop making pixels *wait*:

- every pixel starts its own transition the moment its target changes;
- a pixel whose target changes mid-flight is turned around instead of being finished
  (early cancel);
- moving content is drawn in binary, and greys are refined only where content has stopped;
- nothing is driven when nothing changes.

That is how Modos Caster gets its smoothness
([Caster `pixel_processing.v`](https://github.com/Modos-Labs/Caster/blob/master/rtl/pixel_processing.v),
[Glider README](https://github.com/Modos-Labs/Glider)). This document applies the same ideas
twice.

**Tier A: shipped CPLD, no flashing.** The CPLD stays a black box. Marathon owns everything
upstream of it: input, composition, the exact bytes of every pixel, and when each change
reaches the link. That control is enough to get most of Caster's *policy*:

- switch to the fast waveform on input;
- draw binary-first and refine greys through content;
- dither anchored to content;
- binarise text with edge awareness;
- late-latch paced frames with prediction;
- a per-pixel ghost-debt map driving idle cleans.

Which techniques are safe or useful depends on five unknown CPLD behaviours (§3.1). A two-hour,
three-look camera experiment settles them (§4).

**Tier B: the GPU is the TCON.** A new, *minimal* CPLD bitstream becomes a line-buffered
DSI-to-EPD bridge, in the reMarkable 2 style. The Mali GPU then holds per-pixel state (32 bits per
pixel) in DRAM and runs a compute pass at 85 Hz. The pass looks up the waveform, early-cancels,
applies hybrid greys, temperature and DC bookkeeping, and emits 2-bit drive codes. Those codes
are packed 12 pixels per RGB888 DSI pixel: a 68×601 frame, 10.4 MB/s, an eighth of today's link
payload.

When no pixel is in transition, the loop stops and the link goes to 0 Hz. A touch-down
re-arms it before the first changed frame exists.

The memory wall that made the firmware assessment NO-GO for a Caster port does not apply to
this design. State lives in SoC DRAM, so the bridge needs two 204-byte line buffers, which fit
in one of the PGC4K's eleven 9 Kbit DRMs. Tier B is still gated on:

- waveform data;
- the CPLD pinout;
- a licensed Pango toolchain;
- a proven flash-recovery path (§5.16, §8).

All of the Tier B GPU work can be built and measured on the phone in shadow mode, and on a Pi 5
dev rig, before anything is flashed.

**Carry-over.** Tier A is not a throwaway. Every compositor piece of Tier A is the front half
of Tier B (§6). The target pass, interaction state machine, region classes, ghost-debt map,
prediction, measurement rig and kernel property all survive unchanged. Tier B adds one compute
pass behind them.

## 1. Physics and platform budget

| Quantity | Value | Source |
|---|---|---|
| Panel scan rate (typical) | 85 Hz, 11.76 ms per frame | WBF header byte `0x85`; rM2 `FBIOPAN_DISPLAY` blocks ~11.87 ms ([rM2-stuff porting notes](https://github.com/timower/rM2-stuff/blob/master/doc/swtcon_porting.md)) |
| Drive levels per pixel per frame | 3 (+15 V, −15 V, VCOM; plus Hi-Z) | `00` VCOM, `01` −15 V, `10` +15 V, `11` Hi-Z ([Glider README](https://github.com/Modos-Labs/Glider)) |
| Binary transition | ~10 frames (120 ms) A2 | [E Ink mode declaration](https://www.waveshare.net/w/upload/c/c4/E-paper-mode-declaration.pdf) |
| 16-grey transition | ~38 frames (450 ms); 46 on the rM2's ED103TC2 | ibid.; [yobert/swtcon](https://github.com/yobert/swtcon) |
| DC balance | Waveforms are DC-balanced; imbalance leaves remnant voltage that decays over ~10 min | [US 11935495](https://patents.google.com/patent/US11935495), [US 9564088](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9564088) |
| MP01 link today | 800×600 RGB888, 60 Hz video, 4 lanes, ~210 Mbit/s per lane | vendor `panel-z10-eink-vdo.c` |
| MP01 CPLD | PGC4KL: 3,968 LUT5, 11 × 9 Kbit DRM (~12.4 KB), MIPI input through IO buffers at up to 810–900 Mbit/s per lane, UWG81 package with 64 user IO | Pango DS03001 v1.5, UG030005 (in `~/q25-build/mp01-inventory/cpld/artefacts/`) |
| MP01 GPU | Mali-G57 MC2 (Valhall), Panfrost, GLES 3.1 compute | `socs/mt6789.toml` |
| MP01 touch | FocalTech on i2c0 0x38, scan rate unknown | `devices/minimal/mp01/README.md` (branch `feat/mp01-device`) |

The panel's gate and source orientation, film generation, PMIC and native frame rate are
unknown. This document assumes 800 source columns × 600 gate rows, matching the DSI mode, and
flags every place that depends on it.

## 2. Architecture

```
            ┌──────────────────────── Marathon compositor (one process) ─────────────────────────┐
 evdev ───► │ Interaction FSM ──► Policy ──► Region classes (64×64 tiles) ──┐                     │
 (touch,    │   idle/press/drag/fling/type      per-tile: grey | binary | text | video          │
  keys)     │        │                                                       ▼                   │
            │        │  prediction        Qt Quick scene (cached layer, re-rendered on damage)   │
            │        └──────────────► scroll/pan offsets ──► TARGET PASS (fragment shader)       │
            │                            quantise · content-anchored blue noise · edge-aware text │
            │                            · hybrid gate (binary while moving, grey when quiet)     │
            │                            · ghost-debt map                                         │
            │                                        │ target texture (800×600, R8+quiet)         │
            │          ┌─────────────────────────────┴──────────────────┐                        │
            │   Tier A │ scanout as RGB888 via eglfs_kms,               │ Tier B  TCON PASS      │
            │          │ + mode/clear in the same atomic commit         │ (compute, 85 Hz while  │
            │          │                                                │ active) per-pixel      │
            │          │                                                │ state 4 B/px → packed  │
            │          │                                                │ 2-bit drive 68×601     │
            └──────────┴───────────────────┬────────────────────────────┴───────────┬────────────┘
                                           │ DSI 4-lane video                       │ DSI, burst, 85 Hz or off
                               shipped CPLD (diff + LUT + mode)        minimal bridge CPLD (line buffer,
                                           │                           header check, gate/source timing)
                                           ▼                                        ▼
                                       E Ink panel                              E Ink panel
```

The compositor has two clocks:

- **The scene clock.** It runs only on damage: input, client commits, timers. It renders the
  Qt Quick scene into a cached layer, and the target pass turns that into a target image. At
  rest it does no work.
- **The panel clock.** In Tier A this is the CPLD's internal one, which the compositor feeds by
  committing frames. In Tier B it is a TCON loop in the compositor: it ticks at 85 Hz while any
  pixel is in transition and stops otherwise.

## 3. Tier A: the shipped CPLD as a black box

### 3.1 The CPLD behaviours that matter

Everything Tier A can do depends on how the CPLD treats a change. The interface it exposes is
four modes on 0x8C and a clear on 0x8E=5.

| ID | Behaviour | Possible answers | Experiment |
|---|---|---|---|
| **K1 Concurrency** | Does a change wait for an update already in flight elsewhere on the panel? | *global* (everything waits: one update at a time), *region* (bounding boxes queue or merge, as the i.MX EPDC and m-weigand EBC scheduler do), *per-pixel* (independent, as in Caster and hrdl's `pixel_scheduling`) | E2 |
| **K2 Mid-flight change** | What happens when a pixel's input changes while that pixel is being driven? | *restart/retarget* (Caster-style cancel), *queue* (finish, then drive to the newest value), *ignore-until-done then diff* (equivalent to queue if it diffs against the displayed state), *lost* (it diffs against the last *received* frame, so a change during the update is never drawn) | E3 |
| **K3 Diff domain** | What the CPLD compares: 24-bit RGB, 8-bit luma, or the quantised 4-bit level. Which channels feed luma. | | E4, E5 |
| **K4 Mode semantics** | Does a mode switch affect pixels already in flight? What is stored as the "current" level after a fast-mode draw: the received grey or the binarised result? Does returning to quality redraw fast-drawn pixels by itself? Does fast mode threshold greys, dither them, or ignore them? | | E6, E7 |
| **K5 Timing** | Waveform length per mode and per transition; the internal frame clock (locked to DSI vsync, or a free-running ~85 Hz?); pipeline delay from frame arrival to first drive; a readable busy flag in 0x89/0x8B/0x8D; whether the CPLD tolerates a stopped DSI stream | | E1, E8, E9, E13 |

**A correction to the earlier report.** The report says stock Hybrid rests on `clean` and that
this causes its flicker. LuneOS writes registers with 1-based values: stock Hybrid uses
register 1 at rest and 4 while moving, which is waveform 0 ↔ 3, the silent pair. The double flash
belongs to *entering* waveform 1 (`clean`), which stock never does automatically. The "flickers a
lot" complaint more likely comes from the re-draw of fast-drawn pixels when Hybrid returns to
quality, which LuneOS calls unavoidable. That is K4, and E6b measures it.

### 3.2 Techniques and what each depends on

| # | Technique | Depends on | Decision rule after §4 |
|---|---|---|---|
| A1 | **Input-first mode switch.** Switch to `fast` on touch-down, then to binary rendering at drag slop or fling start. Return to `quality` after the refine delay. Switch to `text` while the OSK is up. Never auto-enter `clean`. | K4 (does an in-flight pixel change speed?) | Always on. If E6a shows the switch affects in-flight pixels, delay it until the next idle boundary (from K5). |
| A2 | **Quantise to the CPLD's own bins**, using thresholds from E5, so anti-aliasing jitter and sub-level colour changes never cause a drive | K3 | Always on. It costs nothing, even if the CPLD already compares 4-bit levels. |
| A3 | **Binary-first, refine through content** (Caster's hybrid emulated by the diff). While a region is moving, the target pass emits only the two rail values (0 and 15). Once the region is quiet, it emits the true greys. The CPLD's own diff then re-drives exactly the pixels whose grey differs from their binary stand-in, starting from a rail state it knows. | K2, K4, E7 (accuracy of a rail-to-grey transition after fast history) | On if E7's residue is below the ghost budget. If K4 says the CPLD re-draws fast-drawn pixels on return anyway, align the content refine with that one pass, so the panel does one refine, not two. |
| A4 | **Content-anchored blue noise.** Dither greys to binary with a 64×64 blue-noise mask indexed by *content* coordinates, so the pattern moves rigidly with scrolled content and only true content changes cause drive | none (any diffing TCON gains) | Always on in binary regions. Snap scroll offsets to whole pixels. A sub-pixel offset re-dithers every pixel. |
| A5 | **Edge-aware text binarisation.** In binary regions, threshold the neighbourhood instead of dithering it when it is bimodal (text, line art), using local min/max contrast in a 3×3 or 5×5 window. Dither only smooth regions. Apply a slight stem-darkening bias before the threshold so thin strokes survive. | none | Always on. Tune the threshold on device captures. |
| A6 | **Pacing with late latch.** Present at most one new content state per measured binary period. Render it as late as possible before the CPLD can accept it, at the predicted position. Accumulate scroll deltas; never drop them. | K1, K2, K5 | *global*: mandatory. A frame sent mid-update either waits or is lost (K2), so the freshest frame must arrive just as the update ends. Use E9's busy bit if one exists, else the E1 timing model. *per-pixel + restart*: only cap the rate at the binary period, which trades blur for crisp steps (see A8). *queue*: mandatory, or lag accumulates. |
| A7 | **Region scheduling.** Keep the OSK, caret and pressed states spatially separate from content refines, and split a large grey refine into tiles that start independently | K1 | *per-pixel/region*: on. *global*: off, because splitting serialises. Defer grey refines until input is unlikely instead (finger up, no fling, 300 ms quiet), because a 450–750 ms grey update blocks every input change behind it. |
| A8 | **Overdrive / pre-compensation.** (a) *Sprint*: send a rail value first, then the grey once the rail is reached. This is the same as A3 applied to page changes. (b) *Ghost-aware targets*: when the ghost-debt map predicts a residue, nudge the next grey target by one level to cancel it, in the spirit of Ghostbuster's history-aware pre-compensation ([Hu et al., EMSOFT 2024](https://web.eng.fiu.edu/gaquan/Papers/ESWEEK24Papers/EMSOFT/EMSOFT_40_Hu)). | K2 *restart* for anything mid-flight; E7/E11 residue model for (b) | (a) on whenever A3 is on. (b) is research. Enable it only if the E11 residue proves repeatable to ±1 level. |
| A9 | **Input prediction.** Draw the content where the finger *will* be when ink moves. For drags, extrapolate the last 2–3 touch samples by the measured flip-to-ink latency, damped and clamped to 30–60 px. Flings need no prediction because the compositor computes them. | lookahead from E1/E14 | On for the shell's own scrollers. For apps, see A11. |
| A10 | **Ghost-debt map and idle clean.** Keep a per-pixel (or per-4×4) counter of fast transitions since the last clean, with the error predicted from E11. Clean when the debt passes a threshold *and* the screen is idle for ≥1 s, on app switch, unlock, or before display-off. Prefer a local two-step re-drive (rail, then target) of high-debt tiles to a full-screen clear when the debt is local and K1 allows region updates. | E10, E11 | Always on. The threshold comes from E11. |
| A11 | **App cooperation.** Keel apps on an e-paper display dither and binarise in the toolkit, where content coordinates are known. They report scroll offsets through a private `marathon_epaper_v1` surface hint (offset, moving/settled, preferred class). Foreign apps get compositor-side vertical block matching, so the dither phase follows their scroll. | none | Keel and the protocol first. Block matching is the fallback. |
| A12 | **Correctness guard for K2 = *lost*.** If a change made during an update can be lost, the compositor must re-assert a region's content after the update ends: one re-commit of the damaged area with a one-level toggle and back, or a full-frame re-send once the busy window ends. | K2 | Only if E3 shows *lost*. Without it, the shell would sometimes show stale content indefinitely. |
| A13 | **Idle link rate.** At rest the scene clock already does no work, but DSI keeps scanning the unchanged buffer at 60 Hz. Stopping the link saves SoC and link power only. | K5 (E13) | Optional, after E13. It needs the panel to stay prepared while CRTC ACTIVE=0. |

A1–A5 and A9–A10 help whatever the CPLD turns out to be. A6–A8, A12 and A13 are where the
experiments change the design.

### 3.3 Target pass (shared with Tier B)

This is a single fragment shader over the composed scene. Its output is the panel-resolution
target, in panel orientation. Inputs per pixel:

- composed luminance `L` (sRGB → linear → panel gamma from E5);
- tile class (from the region map);
- content coordinate `c`. The shell's own layers set `c` per item. Client surfaces use their
  surface-local coordinates plus the reported or estimated scroll offset.

```glsl
// Target pass (Tier A writes this to the scanout buffer; Tier B writes level + quiet to a texture)
uniform sampler2D uScene;          // composed, cached layer
uniform usampler2D uTileClass;     // 13×10 tiles: 0 grey, 1 binary, 2 text, 3 video
uniform sampler2D uBlueNoise;      // 64×64 void-and-cluster mask, values in (0,1)
uniform sampler2D uContentOffset;  // per-tile content offset (px), from scroll hints/estimation
uniform float uBins[17];           // CPLD level boundaries measured in E5 (Tier A); uniform for Tier B

uint level16(float L) { /* binary search uBins → 0..15 */ }

void main() {
    ivec2 p = ivec2(gl_FragCoord.xy);
    float L = panelGamma(texelFetch(uScene, p, 0).r);
    uint cls = texelFetch(uTileClass, p / 64, 0).r;
    if (cls == GREY) { out = level16(L); return; }
    // Binary classes: edge-aware choice between threshold and ordered blue noise.
    float lo = min3x3(uScene, p), hi = max3x3(uScene, p);
    bool edge = (hi - lo) > 0.45;                       // bimodal neighbourhood: text, line art
    vec2 c = vec2(p) + texelFetch(uContentOffset, p / 64, 0).xy;
    float t = edge ? mix(lo, hi, 0.55)                  // stem-darkening bias
                   : texelFetch(uBlueNoise, ivec2(mod(c, 64.0)), 0).r;
    out = (L > t) ? 15u : 0u;
}
```

Cost: one full-screen pass at 800×600 with nine taps, a fraction of a millisecond on the G57.
It runs only when the scene changed.

### 3.4 Interaction state machine

```
          touch-down                 slop exceeded / fling            finger up, no fling
 IDLE ───────────────► PRESSED ─────────────────────────► MOVING ─────────────────────► SETTLING
  ▲   (mode→fast now;      │ release without motion              │ fling ends                │ quiet ≥ T_refine
  │    pressed state       │ (tap): state change drawn           ▼                           ▼ (300 ms est.)
  │    drawn binary)       └──────► REFINE ◄──────────────── SETTLING ──────────────────► REFINE
  │                                   │ greys emitted (A3); mode→quality at the boundary
  └────────── idle ≥ 1 s & debt>θ ──► CLEAN (A10) ◄───────────┘
```

- The waveform mode changes at most once per 200 ms. Stock drops a change inside that window;
  Marathon defers it to the end of the window instead.
- On e-paper, mode and content are committed together: the waveform is a KMS connector property
  set in the same atomic commit (§3.6).
- Typing (OSK or the hardware keyboard) uses the `text` class for the input field's tiles and
  never triggers a full refine of the rest of the screen.

### 3.5 Tier A latency budget (est.)

| Stage | Time |
|---|---|
| Touch scan, IRQ, evdev | 4–10 ms (FocalTech rate unknown; E14) |
| Scene update + target pass | 2–4 ms |
| Wait for vblank (60 Hz DSI) | 0–16.7 ms; late-latching the render cuts the average to ~3 ms |
| Frame transfer to CPLD | up to 16.7 ms, if the CPLD diffs whole frames before starting (E1 shows this) |
| CPLD start delay | unknown (E1) |
| Ink first visible movement | ~2–3 panel frames, ~25–35 ms |
| **Touch to first visible ink** | **~40–80 ms, if no update is in flight** |
| Binary settled | +~120 ms |
| If K1 = global and a grey refine is in flight | + up to 450–750 ms. A7's deferral exists to make this rare. |

### 3.6 Kernel interface (Tier A)

The interim sysfs pair (`refresh_mode`, `full_refresh`) on branch `feat/mp01-eink` is enough for
§4 and for a first policy. The target is the KMS shape already written up in
`eink-refresh-api.md`:

- a connector enum property `epd waveform` (`quality`/`clean`/`text`/`fast`), applied in the
  commit tail, so mode and frame land together;
- a one-shot `epd full refresh` property;
- a read-only `panel type`;
- temperature from 0x8F as hwmon.

That follows H1: the compositor never pokes registers, and the kernel owns the panel.

### 3.7 Qt Quick integration (Tier A, carried into Tier B)

- The shell's root scene renders into a cached layer (`layer.enabled` on the root content
  item). The layer re-renders only when its subtree is dirty, so a static screen costs nothing.
- A C++ `EpaperOutputItem` (a `QQuickItem` with a `QSGRenderNode`, recording `QRhi` passes) sits
  above the layer and draws the target pass into the window's render target. eglfs_kms scans
  that out. The class map, blue-noise mask and per-tile content offsets are `QRhiTexture`s
  updated from the GUI thread through `updatePaintNode`.
- Mode changes go out with the frame. `WaylandCompositor` already holds the DRM master fd and CRTC
  from eglfs_kms for the Doze ACTIVE commits (`shell/src/wayland/waylandcompositor.cpp`). The
  connector-property write joins that path once the property exists. Until then, sysfs is
  written from `beforeRendering` for the frame that needs it.
- The shell already rotates the scene to the panel's DRM orientation (branch `feat/eink-mode`,
  `743a96068`), so the target pass works in panel coordinates.

## 4. Experiment plan: characterising the shipped CPLD

**Goal:** fill §3.1 with measurements and the §3.2 decision column with outcomes. Use three human
looks and no flashing.

### 4.1 Rig

- **Device side: `epdprobe`.** A small static C client (libdrm and libevdev, about 600 lines),
  run as root after `systemctl stop marathon-shell`. Never `pkill`.
  - It takes DRM master and allocates three XRGB8888 dumb buffers at 800×600.
  - It page-flips with `DRM_MODE_PAGE_FLIP_EVENT` and logs every flip's vblank timestamp
    (CLOCK_MONOTONIC) and sequence.
  - It runs a scripted trial list (§4.3) from a TOML file.
  - Mode and clear go through the driver's `refresh_mode`/`full_refresh` only. The regmap there
    allows writes to 0x8C (0–3) and 0x8E (5) and nothing else.
  - It polls 0x89, 0x8B, 0x8D and 0x8F through `/sys/kernel/debug/regmap/7-004b/registers`. These
    reads are inside the driver's read table and never write.
  - It logs evdev events with `EVIOCSCLOCKID(CLOCK_MONOTONIC)`.
- **Time sync: the frontlight as a strobe.** Trials run at a fixed frontlight level L0 (~30%).
  - Before each trial, `epdprobe` writes the `disp_pwm` backlight node to send a sync code: a
    50 ms start pulse to 100%, then 8 bits of trial ID at 25 ms per bit (6 camera frames per bit at
    240 fps), each write timestamped.
  - The analysis fits `camera_time = a + b·monotonic` over all strobes by least squares, which
    also fits clock drift, and decodes trial IDs.
  - Error budget: about ±2 ms. That is half a camera frame plus the PWM period; check that
    `disp_pwm` runs in the kHz range so it averages within one exposure.
  - Ink reflectance is normalised by a reference patch, so the strobes do not bias it.
- **Camera.** A phone at 240 fps (4.17 ms per frame) on a clamp, square to the panel. Lock
  exposure at ≤1/480 s, lock focus, white balance fixed. Every pattern carries four corner
  fiducials (solid 40 px squares) for homography, plus one always-white reference patch.
- **Host side: `epdanalyze.py`.**
  - Decode with `ffmpeg -vf scale=960:-1,format=gray -f rawvideo` streamed frame by frame, so
    memory stays at a few MB. Read per-frame PTS from `ffprobe`; never assume 240 fps.
  - Find the panel by its fiducials and map each trial's patch ROIs, which are known in panel
    coordinates.
  - Produce a normalised reflectance curve R(t) per ROI.
  - Measure: start latency t₁₀ (10% of the step) relative to the flip; t₉₀; settle t₉₈; overshoot;
    flash (any excursion beyond both endpoints); final error against a post-clear reference.
  - Output one JSON per trial and a summary table per experiment. A decision script maps the
    summaries onto the §3.2 rules and prints the resulting Tier A configuration.
- **Layout.** A 6×4 grid of 96×96 patches with 24 px gutters, numbered P0–P23 in the scripts.
  At ~1.2 camera px per panel px this gives ~100×100 camera px per patch, plenty for a mean.

**Human looks:**

1. Mount the camera, start 240 fps recording, and touch the panel. The touch is `epdprobe`'s
   start signal.
2. When the panel shows "SWITCH CAMERA TO 4K" (its only text), switch to 4K 30 fps for the
   static captures (E5, E7b) and touch again.
3. When the panel shows "DONE", stop recording and copy both files to the host.

An optional fourth look repeats E1 cold (§4.3, E12).

Run time is about 15 minutes, with each trial repeated 8–10 times at randomised phase against
vblank.

### 4.2 Test-client conventions

- Every trial starts from a known state: `full_refresh`, then 1.5 s idle in the trial's mode,
  then the trial's base frame, then 1 s settle.
- **A "change" is one atomic flip.** A patch's value comes in 8-bit grey as (v, v, v) unless the
  trial sets channels on purpose.
- Values used: `L(k) = round(255·k/15)` for the 16 levels until E5 replaces them with measured bin
  centres.
- Δ offsets are drawn uniformly from ±2 ms around the nominal value, plus a random vblank phase,
  so quantisation shows up as a distribution.

### 4.3 Experiments

| ID | Question | Procedure | Readout → decision |
|---|---|---|---|
| **E0** | Rig sanity | Ten strobes alone; a static screen for 5 s | Clock fit residual < 2 ms, PTS jitter, and ROI noise floor σ. All later thresholds are 5σ. |
| **E1** | Waveform length, pipeline delay, internal clock (K5) | In each mode 0, 2, 3, drive patch transitions 0→15, 15→0, 0→7, 7→0, 15→7, 7→15, 3→12, 12→3, ten repeats each | Table of t₁₀/t₉₀/t₉₈/flash per (mode, transition). The spread of t₁₀ across random vblank phases shows whether the CPLD starts on frame arrival or on its own frame grid (uniform spread of one internal period). Sets the A6 period and the A9 lookahead. |
| **E2** | Concurrency (K1) | Mode 0: P7 goes 15→0 at T. Then at T+Δ, Δ ∈ {12, 35, 70, 140, 280, 420} ms, change one of: (a) P16, far away; (b) P9, which lies *inside the bounding box* of a two-patch update P7+P11 started at T; (c) P8, adjacent. Repeat in mode 3 with Δ ∈ {12, 35, 70, 105}. | B's t₁₀ against Δ. **Constant** → per-pixel. **≈ T_end(A) − Δ** → global. **Waits only in (b)/(c)** → region/bounding box. Configures A6 and A7. |
| **E3** | Mid-flight change (K2) | Mode 3 and mode 0: P3 goes 15→0 at T, then at T+Δ (Δ = 25, 50, 75, 100, 200 ms) returns to 15 or goes to 7. Also five flips 20 ms apart, then hold. Watch for 3 s. | **Reverses within one internal frame** → restart (A8 allowed). **Reaches 0, then returns** → queue (A6 mandatory). **Stays at 0** → *lost*, so enable the A12 guard and file it as a CPLD defect. |
| **E4** | Diff domain (K3) | Mode 0, settled patches; each pair alternates 5 times at 300 ms: (128,128,128)↔(129,129,129); ↔(135,135,135); two values inside one E5 bin; across a bin edge; R-only ±16; G-only ±16; B-only ±16 | Any driven movement (>5σ) on sub-bin pairs → the CPLD diffs before quantising, so A2 becomes critical. Per-channel responses → luma weights for the target pass. |
| **E5** | Quantiser and tone curve | After a clear in mode 0, show a 256-step ramp (16×16 cells of 32×24 px) and a 16-level ramp. 4K static capture. | Bin edges (`uBins`) and L* per level. Gamma table for the target pass. |
| **E6** | Mode semantics (K4) | (a) Mid-way through a mode-0 15→0, switch to mode 3: does the trajectory change? (b) Draw a 16-level ramp and a text block in mode 3, switch to mode 0 *without changing content*, and watch 2 s: is nothing, the fast-drawn pixels, or everything re-drawn? (c) The flash matrix, one trial each: 3→0, 0→3, 2→0, 3→2, 0→2, then x→1 last. | (a) sets A1's switch timing. (b) settles LuneOS's "unavoidable redraw" and what the CPLD stores, which is the precondition for A3. (c) confirms the silent set and resolves the einkd/LuneOS contradiction. |
| **E7** | Fast-mode greys and refine accuracy | (a) Mode 3 and mode 2: show the 16-level ramp and a dithered ramp (content-anchored blue noise from A4). (b) 4K static of both. (c) Draw a checkerboard of rails in mode 3 for 5 s, then switch to mode 0 and change those pixels to level 7. Compare the result with a clean 0→7 and 15→7 reference. | Does mode 3 threshold, dither or ignore greys? This explains the reviewers' "half resolution". The refine residue (ΔL between ex-black and ex-white pixels at level 7) decides A3, and feeds A8b. |
| **E8** | Throughput and drops | Mode 3: a 24 px bar moves 4 px per DSI frame for 2 s; then the same path with one change every k frames, k = 1…8 | Rendered positions over time, effective updates per second, and whether lag grows (queue), stays bounded (drop) or alternates (restart). Sets the A6 rate. |
| **E9** | Busy flag | During E1, E2 and E3, poll the three status registers at the I2C rate (~2 kHz at 1 MHz) | Cross-correlate each bit with the optical "any patch moving" signal. A bit that rises within one frame of a flip and falls at t₉₈ is a free busy flag for A6. |
| **E10** | Clear anatomy | `full_refresh` alone, and the stock sequence (clear, mode 2, restore after 100 ms), on a text page | Duration, flash count, whether the post-clear image is the current DSI frame, and whether the mode-2 step is needed |
| **E11** | Ghost accumulation | Scroll a text-and-image page by 24 px steps, k ∈ {1, 5, 20, 50} steps, in mode 3 with A4/A5 targets, then return to mode 0. Compare with the same content after a clear. Repeat once with the CPLD seeing un-dithered greys, which is stock-like. | Residue L* RMS against k gives the A10 threshold and the per-transition debt weight. Also measures A4/A5 against stock content directly. |
| **E12** | Temperature (optional fourth look) | Log 0x8F on every trial. Repeat E1 (modes 0 and 3, four transitions) after 20 min in a fridge (~5 °C). | Whether the CPLD compensates (durations change) or not. Sets the cold scaling of A6 and A10. |
| **E13** | Stopped link (optional, separate kernel build) | With the panel held prepared, set CRTC ACTIVE=0 for 1, 3 and 10 s, then ACTIVE=1, on a settled screen and once mid-update | Does the image hold, is it re-driven on resume, does the CPLD recover? A power-cycle reload from eflash is the recovery, so there is no persistent risk. Do the first trial on a settled screen, and keep windows ≤10 s until the mid-update behaviour is known. Gates A13 and Tier B's link-off idea. |
| **E14** | Touch to ink, end to end | Shell running with the Tier A policy build. A human does 20 taps on a button and 10 drags on a list. The camera sees finger and panel; evdev and flips are logged. | Touch-down → first ink, and slop → first scroll ink. Compares against the E1 chain to find the input-side cost. Run it after Tier A M-A2, as its acceptance test. |

**Safety rules.**

- Run nothing but the probe's own reads and the two allowed writes.
- Never write 9, 16 or 17 to anything, never write 0x89, 0x8B or 0x8D, and never write 0x8E with
  anything but 5.
- No DSI timing changes in the default suite. E13 is opt-in.
- After the suite, restart the shell with `systemctl restart marathon-shell`.

### 4.4 What the outcomes do to the design

```
K1 per-pixel ─┬─ K2 restart ──► Tier A ≈ Caster policy: no pacing cap needed beyond A8 choice;
              │                 A7 region split on; A8 sprint/overdrive on.
              └─ K2 queue ────► A6 pacing mandatory (rate = 1/binary period), A7 on.
K1 region ───────────────────► A7: keep OSK/feedback regions disjoint from content refines;
                               A6 pacing per region; full clears only when idle.
K1 global ────┬─ K2 queue/ignore ► A6 late-latch to the busy edge (E9) or timing model (E1);
              │                    A7 off; refine deferred to ≥300 ms quiet + finger up.
              └─ K2 lost ─────► everything above + A12 guard.
```

## 5. Tier B: a software TCON on the Mali GPU

### 5.1 Why this fits where a Caster port did not

Caster keeps 16 bits of state per pixel in DDR3 next to the FPGA, because its input is plain
video. The reMarkable 2 has no TCON chip at all: the i.MX7's LCDIF clocks pre-computed 2-bit
drive codes straight into the panel's source and gate drivers, and a CPU thread computes them.
Waved's `display.hpp`, for example, packs 8 pixels into 2 bytes per 4-byte framebuffer pixel and
carries gate and source sync patterns in the third byte
([waved display.hpp](https://github.com/matteodelabre/waved/blob/main/lib/display.hpp),
[display.cpp](https://github.com/matteodelabre/waved/blob/main/lib/display.cpp)).

The MP01 cannot reach its panel directly; the CPLD is in the way. But a bridge that only
*re-times* lines needs no frame memory: one line of 800 two-bit codes is 200 bytes. Every byte
of per-pixel state then lives in LPDDR4X on the SoC side, where the GPU reads and writes it at a
fraction of a percent of available bandwidth (§5.9).

### 5.2 The bridge bitstream (minimal by design)

| Block | Job | Size (est.) |
|---|---|---|
| D-PHY RX ×4 lanes + clock | `GTP_IOBUF_RX_MIPI` HS/LP inputs (UG030005 §12), byte alignment, lane merge | The bulk of the design. The shipped `mipi2tcon_top` proves it fits this part. |
| DSI packet parser | Video-mode long packets (RGB888), ECC/checksum check, VSS/HSS sync packets | ~300–500 LUT |
| Header check | Line 0 of each frame is a 204-byte header: magic `EPD1`, u32 sequence, flags, first/last active gate row, header CRC-16 | ~150 LUT |
| Line buffer | 2 × 204 B ping-pong in one 9 Kbit DRM | 1 DRM |
| Source/gate timing | SDCLK, SDLE, SDOE, SD[7:0] at 4 px per clock; GDCLK, GDSP, GDOE. Registers set line and frame timing. | ~200 LUT |
| PMIC and VCOM | Enable and sequence the EPD rails; program VCOM | ~100 LUT, plus I2C master if the PMIC is I2C |
| I2C slave | Version, status, error counters, frame count, temperature (keeps today's 0x8F) | ~150 LUT |
| **Safety** | Drive a line only if (1) the frame's header is valid, (2) its sequence number is exactly last+1, and (3) the line's DSI checksum is good. Otherwise emit `00` (VCOM, no drive) for that line. No valid frame for 2 periods: gate off, then PMIC off after 100 ms. | ~100 LUT |

Rule (2) matters more than it looks. In video mode the SoC's display controller keeps scanning
the last committed buffer forever if the compositor stalls or crashes. Without the sequence check,
one stuck drive frame would be applied 85 times a second, a DC hazard. With it, a stuck buffer
is inert after one frame.

Garbage on the link fails the same check, and so does the bootloader's ordinary RGB logo: LK
drives the panel as a plain DSI video LCM. A header-less frame never drives the panel. The
consequence is that the LK logo will not draw. Marathon draws its boot image *before shutdown*
instead, and a bistable panel keeps it through power-off, so the logo is still there at the next
boot.

Not in the bridge: waveform tables, temperature compensation, frame memory, diffing, mode logic.
All of these live on the GPU.

### 5.3 Data path and bandwidth

**Packing.** Each panel pixel gets 2 bits: `00` no drive (VCOM), `01` toward black (−15 V),
`10` toward white (+15 V), `11` Hi-Z or reserved, following Glider's coding. Twelve pixels fit in
one RGB888 DSI pixel, so a panel line of 800 px is 1,600 bits = 200 B, which is 66⅔ DSI pixels.

The DSI line is **68 pixels** (204 B, the last 4 B are padding). Bit order within the 24 bits is
fixed by the bridge spec: pixel 0 in bits 23:22 of the first byte on the wire, and so on. The
shader packs to match.

**DRM mode (panel driver):**

```
HACTIVE 68   VACTIVE 601 (row 0 = header, rows 1..600 = gate rows)
VTOTAL ≈ 611 (VFP 4, VSA 2, VBP 4)   frame 85 Hz → line period 1 / (611·85) = 19.26 µs
HTOTAL chosen for a legal D-PHY rate (mtk_dsi sets lane rate = pclk·24/lanes):
  4 lanes, HTOTAL 480 → pclk 24.9 MHz → 150 Mbit/s per lane (long LP blanking)
  or 2 lanes, HTOTAL 240 → pclk 12.5 MHz → 150 Mbit/s per lane
framebuffer: XRGB8888 (or RGB888 if the plane supports it), 68×601, linear, one BO per frame
```

**Bandwidth.** The payload is 204 B × 601 × 85 = **10.4 MB/s (83 Mbit/s)**. Today's link
carries 800×600×3×60 = 86 MB/s, so the drive stream is 8.3× smaller than the video Tier A sends.

The bridge re-times each line through its ping-pong buffer. The DSI line period has to match the
panel's gate line period *on average*; jitter within one line is absorbed. Whether the panel needs
85 Hz with ~19 µs lines, or tolerates other rates, is a property of the waveform data and the
gate-on time. Waveforms are counted in frames, so the frame rate is fixed by the waveform file
(the WBF header records it), not by preference.

**Partial gate scan (power).** The header names the first and last gate rows that carry any
drive. The bridge clocks rows outside that range through the gate driver with SDOE low. That
saves source-driver power on small updates, such as a caret or a key. The frame period does not
change.

### 5.4 Per-pixel state and LUT

```
state  : R32UI, 800×600 (1.92 MB)
  [3:0]   src     level at start of the current transition (0..15)
  [7:4]   dst     level being driven to
  [15:8]  frame   index into the waveform; 0xFF = idle
  [18:16] wf      0 none, 1 BIN (A2-like), 2 DU, 3 GL16, 4 GC16-local, 5 CLEAN, 6 BIN-long (history)
  [22:19] dwell   log2(frames since last settle), saturating; picks history-aware variants
  [23]    greyPending  binary stand-in shown; grey refine owed
  [31:24] dc      signed net drive frames since the last balanced point (int8, saturating)

target : RG8UI, 800×600, written by the target pass (§3.3)
  R[3:0] grey level   R[4] binary stand-in (dithered/thresholded)   R[6:5] class
  G      quiet        frames since this pixel's grey target last changed (saturating)

lut    : R8UI 2D array; texel (frame, src·16+dst) = 2-bit code; layer = wf·NT + temperature bucket
         (256 × 256 × 1 B = 64 KB per layer; a full WBF set is a few MB, sampled through cache)
len    : UBO, uint8 length[wf][T][src][dst]; also uint8 safe[wf][T][src][dst][frame/8] bitmask
         of DC-neutral cancel points (partial sum of drive = 0)
```

### 5.5 TCON pass (GLSL ES 3.1 compute, pseudocode)

```glsl
#version 310 es
layout(local_size_x = 8, local_size_y = 8) in;           // one invocation = 12 pixels = 1 DSI pixel
layout(binding = 0, r32ui)   uniform highp uimage2D  uState;
layout(binding = 1, rg8ui)   uniform readonly highp uimage2D uTarget;
layout(binding = 2)          uniform highp usampler2DArray uLut;
layout(binding = 3, rgba8ui) uniform writeonly highp uimage2D uDrive;   // 68×601; row 0 written by CPU
layout(std430, binding = 4)  buffer Stats { uint active; uint rowMin; uint rowMax; uint tiles[]; };
layout(std140, binding = 5)  uniform P { uint tempLayer; uint quietFrames; uint allowGrey;
                                         uint cancelAdd; /* + len/safe tables */ };

const uint IDLE = 0xFFu, BIN = 1u, GL16 = 3u;

uint stepPixel(inout uint st, uvec2 tg) {
    uint src = st & 15u, dst = (st >> 4) & 15u, frame = (st >> 8) & 255u, wf = (st >> 16) & 7u;
    int  dc  = int(st) >> 24;
    uint grey = tg.r & 15u, stand = ((tg.r >> 4) & 1u) * 15u, quiet = tg.g;

    // 1. What this pixel should show now: Caster-style hybrid, decided per pixel.
    bool moving = quiet < quietFrames || allowGrey == 0u;
    uint want   = moving ? stand : grey;

    // 2. Retarget.
    if (want != dst) {
        if (frame == IDLE) {
            wf = (moving || isRail(want) && isRail(dst)) ? BIN : GL16;
            if (wf == GL16 && !isRail(dst)) { wf = BIN; want = nearestRail(grey); }  // grey from a known rail
            src = dst; dst = want; frame = 0u;
        } else if (wf == BIN && isRail(want)) {
            // Early cancel, Caster/hrdl rule: reverse for the frames already applied (+cancelAdd).
            uint applied = frame + 1u;
            src = dst; dst = want; frame = len(BIN, src, dst) - min(applied + cancelAdd, len(BIN, src, dst));
        } else if (isSafe(wf, src, dst, frame)) {
            // A grey waveform at a DC-neutral point: finish via the nearest rail, refine later.
            uint r = nearestRail(want); src = dst; dst = r; wf = BIN; frame = 0u;
        }   // else: non-cancellable grey phase; keep going (as Caster does)
    }

    // 3. Emit one frame of drive.
    uint code = 0u;
    if (frame != IDLE) {
        code = texelFetch(uLut, ivec3(int(frame), int(src * 16u + dst), int(wf * NT + tempLayer)), 0).r;
        dc += (code == 2u) ? 1 : (code == 1u) ? -1 : 0;
        frame += 1u;
        if (frame >= len(wf, src, dst)) { frame = IDLE; src = dst; }
    }
    st = src | dst << 4 | frame << 8 | wf << 16 | uint(clamp(dc, -128, 127)) << 24;
    return code;
}

void main() {
    ivec2 g = ivec2(gl_GlobalInvocationID.xy);                 // g.x in [0,67), g.y in [0,600)
    if (g.x >= 67 || g.y >= 600 || !tileActive(g)) return;     // indirect dispatch skips idle tiles
    uint word = 0u; bool any = false;
    for (int i = 0; i < 12; ++i) {
        ivec2 p = ivec2(g.x * 12 + i, g.y);
        if (p.x >= 800) break;
        uint st = imageLoad(uState, p).r;
        uint c  = stepPixel(st, imageLoad(uTarget, p).rg);
        imageStore(uState, p, uvec4(st));
        word |= c << (22 - 2 * i);
        any = any || ((st >> 8 & 255u) != IDLE);
    }
    imageStore(uDrive, ivec2(g.x, g.y + 1), uvec4(word >> 16, word >> 8 & 255u, word & 255u, 0u));
    if (any) { atomicAdd(active, 1u); atomicMin(rowMin, uint(g.y)); atomicMax(rowMax, uint(g.y)); }
}
```

The `uDrive` byte order follows the plane format, so for XRGB8888 the shader stores B, G, R. Pin
it in the first bring-up test.

**Pixel state machine:**

```
             want≠dst                     frame = len
  IDLE ───────────────────► DRIVING(wf) ───────────────► IDLE(src = dst)
   ▲                          │  ▲
   │       BIN & rail target  │  │ mirror: remaining = applied + cancelAdd   (DC-reversing)
   │                          ▼  │
   │                        DRIVING(BIN, reversed)
   │                          │
   │   GL16 at a safe point   ▼
   └────── refine later ◄── DRIVING(BIN → nearest rail), greyPending = 1
                              then, when quiet ≥ Q and allowGrey: DRIVING(GL16 from the rail)
```

### 5.6 Early cancel and DC balance

- **Binary.** Use Caster's and hrdl's rule. When a mid-flight input flips, reverse for roughly the
  frames already applied. Caster sets the new counter to `b2wframe − remaining + 1`
  ([Caster RTL](https://github.com/Modos-Labs/Caster/blob/master/rtl/pixel_processing.v)). hrdl's
  A2 cancel uses `frame_num = last_phase − frame_num − early_cancellation_addition`, with the
  commit noting that "1 seems to result in less ghosting than 0"
  ([hrdl `pixel_scheduling`](https://github.com/hrdl-github/linux/tree/pixel_scheduling/drivers/gpu/drm/rockchip)).
  Reversal is DC-neutral by construction, and `cancelAdd` is the same knob.
- **Grey.** Use vendor LUT transitions, which are DC-balanced as delivered. Cancel only at the
  precomputed DC-neutral points, via a rail. Never start a long grey waveform while
  `allowGrey == 0`, which the compositor sets while a finger is down or a fling runs. That is
  Caster's "quiet barrier", applied per pixel and gated globally.
- **Accounting.** `dc` is kept per pixel. Unit tests assert that every LUT transition nets to
  zero. Field telemetry samples a histogram of |dc| over the panel. A pixel past ±48 frames
  is forced through a balanced CLEAN waveform at the next idle.
- **The sim, honestly.** The host simulation retargets from a *modelled* optical state rather
  than by reversal. It ends a 3.2 s scroll with a mean |net DC| of about 7 frames and a maximum of
  34. A simple "repay at the rail" rule made that worse in the sim. This is why the design uses
  reversal and balanced LUTs, and keeps model-based retargeting as research.

### 5.7 Modes, hybrid, regions, temperature

- **Per pixel, not per mode.** "Fast", "quality" and "text" stop being global states. The target
  pass decides each pixel's stand-in and grey value, and the TCON picks BIN or GL16 per pixel from
  `quiet`. Region classes (OSK = text: binary always; video = binary dithered always; reader page
  = grey) are tile classes.
- **Page change without a flash.** Changed pixels go BIN to the rail nearest their grey target,
  then GL16 from that rail. This is the sprint of A8 with exact source states. Glider's survey
  says no 16-level mode avoids flashing. A sprint flashes only the pixels whose grey is far from
  their rail, and only toward the closer rail, which is the least visible version.
- **History-aware variants.** `dwell` selects BIN-long for pixels that sat at one rail for
  minutes. Ghostbuster's finding is that fast-mode colour is "N-step-history-dependent"
  ([Hu et al.](https://web.eng.fiu.edu/gaquan/Papers/ESWEEK24Papers/EMSOFT/EMSOFT_40_Hu)). The
  variant lengths come from E11-style camera calibration on the Tier B hardware.
- **Temperature.** The LUT layer is chosen per frame from hwmon: today's 0x8F NTC, kept in the
  bridge. WBF files carry per-range tables; waved re-reads temperature every 30 s.

### 5.8 Idle, the 0 Hz floor and the instant ramp

```
ACTIVE (85 Hz TCON ticks) ──active==0 for 2 frames──► DRAIN: commit one all-00 frame,
   ▲                                                   header flag DRIVE_OFF; stop the loop
   │                                                          │ 2 s hold-off, no input
   │ touch-down (evdev, before any                            ▼
   │ content change): CRTC ACTIVE=1,              LINK OFF: CRTC ACTIVE=0 with the bridge
   │ header PMIC_ON; first TCON tick              kept powered (panel "hold": no unprepare);
   └────────── on the next vblank ◄──────────────  bridge powers the EPD PMIC down
```

- At rest nothing renders, nothing scans, and the PMIC is off. This is a true 0 Hz. The bistable
  panel holds the image at zero power.
- **Ramp.** The input thread wakes the link on *touch-down*. A drag needs 30–60 ms to pass slop,
  which hides link enable and PMIC rail-up (*est.* 5–15 ms each, to measure). A tap's pressed
  state is the only change that can catch the link still waking, so it is at most one frame late.
- **Kernel work.** The panel driver must separate "CRTC inactive" from "panel unprepared". Today
  ACTIVE=0 cuts the CPLD's rails (`fpga_power_off`), which Tier B must not do between bursts.
  Doze and suspend still unprepare.

### 5.9 GPU cost (est.)

Per pixel per tick, worst case with the whole panel in transition:

- state read and write: 8 B;
- target read: 2 B;
- drive write: 0.25 B;
- LUT fetch: cached.

That is about 10 B/px, so 4.9 MB per frame and **~415 MB/s at 85 Hz**. MT6789's LPDDR4X has well
over 10 GB/s, so this is under 4%. Compute is about 50 instructions per pixel, giving
480k × 50 × 85 ≈ 2 G instructions/s. A Mali-G57 MC2 at ~1 GHz does on the order of 10¹¹ FP32
ops/s, so this is a few percent. That works out to **~0.3–1 ms per tick** at a low DVFS point,
plus about 50 µs of dispatch overhead.

Indirect dispatch over active 8×8 tiles makes the cost scale with the area in transition. A
caret blink is a few tiles; a full-screen page turn is the worst case for ~0.5 s.

For comparison, the rM2 CPU kernel runs at 35–53 Mpix/s on an A7
([rM2-stuff bench](https://github.com/timower/rM2-stuff/blob/master/real-dev-bench.txt)). The
MP01 at 85 Hz needs 41 Mpix/s, a whole little core. A NEON fallback on an A76 is possible (§5.13),
but the GPU is the right home.

### 5.10 Power (est.)

| State | SoC side | Panel side |
|---|---|---|
| Idle (most of the time) | 0: no render, no scan, link off | 0 (PMIC off) |
| Transition burst (e.g. 0.5 s page turn) | GPU ~5–10% duty at low OPP, DSI at 150 Mbit/s per lane for 85 frames | Source/gate drivers and ink. Same energy as any TCON for the same transitions; less with partial gate scan and `00` on unchanged pixels. |
| Continuous scrolling | GPU ~5–10% duty; display DMA reads 10.4 MB/s instead of 86 MB/s | As above |

Against Tier A, Tier B removes today's 60 Hz full-frame DSI stream at rest, which runs at 86
MB/s whether or not anything changes. Against any TCON, the gain is that the drive stops entirely
between bursts.

### 5.11 Latency budget, touch to first ink (est.)

| Stage | Time |
|---|---|
| Touch scan, IRQ, evdev | 4–10 ms |
| Scene update + target pass | 2–4 ms (overlaps the wait below) |
| Wait for the TCON tick: **late latch** (the TCON pass reads the newest target ~1.5 ms before vblank) | 0–11.8 ms, avg ~6 |
| TCON pass | 0.3–1 ms (inside the latch margin) |
| Scan to the pixel's row | 0–11.8 ms, avg ~6 |
| Ink first visible movement | ~2–3 drive frames, ~25–35 ms |
| **Touch to first visible ink** | **~40–65 ms, and never queued behind other pixels** |
| Binary settled | +~120 ms; a reversal costs only the frames already applied |

Prediction (A9) then removes most of the *perceived* lag for drags. The finger and the content
line up at the moment ink moves.

### 5.12 Compositor integration

- **Threads.** The scene thread (Qt Quick render loop) produces the target texture on damage and
  double-buffers it with a fence. A **TCON thread**, a `SCHED_FIFO` exception under B13 justified
  by a hard panel deadline, owns three drive BOs.
  - On each tick it waits to `vblank_next − 1.5 ms` and takes the newest target.
  - It dispatches the compute pass, updates the header row, and issues a non-blocking atomic
    page flip of the drive plane.
  - It reads back the previous tick's `Stats`.
- **API.** Use QRhi compute on the GLES 3.1 backend, or Vulkan if Marathon moves the MT6789 to
  PanVK. The TCON thread uses its own QRhi with the target texture shared by EGLImage/dma-buf. The
  Doze code's DRM-master access in `WaylandCompositor` grows into the TCON's KMS commit path.
- **eglfs.** On the e-paper class, eglfs_kms no longer scans out the scene. The window renders
  offscreen, through `QQuickRenderControl` or a redirected render target, and the TCON thread is
  the only KMS client for the panel's CRTC. That is a contained change in the shell's output setup,
  keyed on `displayTechnology == "epaper"` together with a kernel-advertised `drive` mode.
- **Shadow mode** (§8 M-B1). Run the whole TCON thread on today's MP01 with the shipped CPLD,
  writing the drive into an offscreen BO instead of KMS. The full GPU cost, power and timing get
  measured on the real Mali before any flash decision.

### 5.13 Kernel shape and rule H1

The kernel owns the panel:

- power and the hold state;
- the DSI mode (68×601 at 85 Hz) and the header contract, documented in the binding;
- temperature (hwmon);
- the waveform blob, loaded with `request_firmware`, CRC-checked, and exposed read-only;
- a connector property `epd drive format` = `cooked` | `raw-2bpp-v1`.

The waveform *engine* is rendering, in the same sense that Mesa is rendering. It lives in a
userspace library, `libepdtcon`, with a GPU path and a NEON path. reMarkable's `libqsgepaper` sits
in the same place. That puts the hardware enablement in the kernel and the pixel computation in
the renderer, which is how H1 reads.

The NEON path serves Plymouth and recovery, which have no compositor. **Open question for the
maintainer:** whether that split is acceptable under H1, or whether a kernel-side NEON engine,
like the Rockchip EBC's direct mode
([RFC 12/16](https://lkml.iu.edu/hypermail/linux/kernel/2204.1/07946.html)), is wanted for plain
KMS clients.

### 5.14 Waveform source

In order of preference:

1. **The shipped tables.** The CPLD reports waveform version 16. The bitstream RE effort
   (`~/q25-build/mp01-inventory/cpld/re/`) is pulling DRM initialisation contents (`drmextract.py`,
   `wfdecode.py`). If the LUTs are on-chip, Tier B can use the exact waveforms Minimal's panel
   shipped with.
2. **A panel-side waveform flash**, if the FPC carries one. Board photos would show it.
3. **Empirical binary waveforms** (A2/DU class: single-polarity runs) calibrated with the §4 rig.
   This is enough for a binary-plus-dither Tier B. Sixteen greys without vendor data is a long
   calibration project and is not planned.

### 5.15 A dev rig that needs no MP01 flash

A Raspberry Pi 5's DPI output can be the LCDIF of the rM2 design. The scheme:

- PCLK → SDCLK, D0–7 → SD0–7, HSYNC → SDLE/CKV, VSYNC → GDSP;
- extra control bits come from spare data bits per line, as waved's sync byte does;
- the DPI lines go into an [epdiy](https://github.com/vroland/epdiy) v7 board's EPD connector and
  PMIC, in place of its ESP32-S3, driving an 800×600 ED060-class panel with a known WBF.

The Pi 5 runs Marathon and has a GLES 3.1 GPU, so the same `libepdtcon` shader, packing (with a
different line format), scheduler and measurement rig get end-to-end validation, including
latency, ghosting and DC telemetry. The cost is a board and a panel. The risk is level and timing
bring-up, using epdiy's display definitions as the reference. The rig is optional, but it turns
B4 from "first light on the phone" into "port a known-good pipeline".

### 5.16 Gates before any MP01 flash

These are unchanged from the firmware assessment §5, plus what this design adds:

- the CPLD pinout to the panel and PMIC, from the bitstream IO configuration or board probing;
- the waveform tables (§5.14);
- a PDS/Fabric Compiler licence, on an x86 host;
- the Pango UG030004/UG030006 behaviour of an *unconfigured* PGC4KL over I2C, proven on a second
  unit, with the identical-image rehearsal done first;
- a programmer that fixes the vendor defects (single shot, erase as required, error-checked,
  RESET only after full readback);
- the bridge verified in simulation against captured DSI traffic;
- **a recovery story that does not need the display.** SSH over USB already exists on Marathon
  images.

## 6. Bridge from Tier A to Tier B

| Built for Tier A | Role in Tier A | Role in Tier B |
|---|---|---|
| Interaction FSM (§3.4) | Picks the global waveform; times the refine | Sets `allowGrey`, pre-wakes the link, sets per-tile classes |
| Target pass (§3.3) | Its output *is* the scanout | Its output is the TCON input (adds the `quiet` channel) |
| Region classes | Reduced to one global mode, the max over tiles | Used per tile, directly |
| Content-anchored dither, edge-aware text | Picks which pixels change, so the CPLD's diff is the hybrid | The binary stand-in per pixel |
| Prediction, late latch | Aligns content to the CPLD's acceptance edge | Aligns content to the TCON tick |
| Ghost-debt map | Decides global or local cleans | Seeds `dwell`; decides CLEAN scheduling |
| `marathon_epaper_v1` hint + Keel support | Dither phase follows app scroll | Same |
| Camera rig + `epdanalyze` | Characterises the black box | Validates the bridge, waveforms, DC and latency |
| KMS properties (`epd waveform`, `full refresh`, `panel type`, hwmon) | Mode and clear | Mode becomes per-pixel policy; `epd drive format` added |
| `EpaperOutputItem` (QRhi pass in the scene graph) | The target pass's home | Moves to the TCON thread; same shaders |
| Doze DRM-master code | Mode property writes | TCON page flips, link on/off |

The only Tier A work that Tier B retires is the CPLD-specific behaviour table (§3.1) and the
global-mode scheduling. Both are kept for unflashed phones.

## 7. Simulation

Run `tools/epaper-tcon-sim/epd_sim.py` (numpy and Pillow, ~2 s, ~160 MB RSS). It produces a GIF
comparing three controllers on the same scroll: a 0.5 s drag at 330 px/s, a fling, then rest, on
a 192×144 crop of text and greys.

The sim dithers with an 8×8 Bayer mask anchored to content, standing in for blue noise.
The ink model is reflectance `x` with a slow history term. A pixel that sat at one rail moves
away from it more slowly, so fixed-length waveforms leave residue. The parameters are
illustrative.

| Controller | Mean error while moving | Settle to < 0.04 after scroll stops | Error at rest (3.2 s) |
|---|---|---|---|
| `global-stock`: one update in flight, stock Hybrid detection | 0.290 | never (residue) | 0.080 |
| `global-tierA`: same TCON, Tier A policy (A1, A3, A4, A6, A9) | 0.256 | never (residue) | 0.117 |
| `gpu-tierB`: per-pixel, early cancel, per-pixel hybrid | **0.175** | **400 ms** | **0.013** |

*sim* only. Error is the mean |reflectance − ideal| over the crop.

What the sim supports:

- **Tier A beats stock during motion**, from earlier fast entry and late-latched predicted frames,
  even on a global-counter CPLD.
- **Tier B tracks motion best.** Its fast scrolls look softer: pixels reverse before reaching full
  contrast, which is Caster's "motion blur" character. A per-region pacing cap in Tier B can trade
  that for crisp steps.
- **The danger in A3.** Tier A's flashless dither-to-grey refine *inherits* fast-mode residue,
  because the CPLD assumes the pixel reached its rail. In the model it ends worse than stock,
  whose blobs are coarser. That is why E7 gates A3 and why A10's idle clean stays in Tier A.

What it does not support:

- Tier B's resting accuracy comes from retargeting off a model with the same *form* as the
  simulated ink, with parameters 5–25% off. Real ink departs from any model. The robust part of
  the Tier B advantage is that nothing waits and that reversals are cheap.

## 8. Milestones

Durations assume one engineer with agent help and the MP01 on the desk.

| ID | Milestone | Duration | Exit criterion |
|---|---|---|---|
| **M-A0** | `epdprobe` (C) + `epdanalyze.py` + trial TOML | 3–4 days | Full suite runs in QEMU against a virtual DRM device. The analyser passes on a synthetic video generated from the sim's ink model with known K1–K5. |
| **M-A1** | Run §4 on the MP01; publish the behaviour report; fill §3.2's decision column | 1 day device + 1–2 days analysis | E0 residual < 2 ms; E1–E11 tables; the decision script's Tier A configuration |
| **M-A2** | Tier A core: `EpaperController`, interaction FSM, mode property (or interim sysfs), target pass with A2/A4/A5, idle clean with ghost-debt (A10) | 1.5–2 weeks | E11 rerun: residue ≤ stock at equal scroll distance; no flash during interaction; device-snap visual checks |
| **M-A3** | A6 pacing/late latch, A9 prediction, A7 per K1, A12 if needed; `marathon_epaper_v1` + Keel dithering (A11) | 2 weeks | E14: touch→first ink and drag smoothness measured against the stock-like baseline (E11 second run) |
| **M-A4** | Tuning: temperature policy (E12), thresholds, connector-property kernel patch posted | 1 week | Camera metrics stable across 3 sessions; dri-devel RFC sent |
| **M-B0** | `libepdtcon`: the §5.5 shader in QRhi compute + NEON reference; golden tests against `epd_sim.py` | 1.5 weeks | Bit-exact drive streams for scripted scenarios on host GLES (Mesa) and NEON |
| **M-B1** | Shadow mode on the MP01: TCON thread live, output offscreen | 1 week | Measured GPU ms per tick, power delta (battery telemetry) and timing jitter at 85 Hz on Panfrost |
| **M-B2** | Optional: Pi 5 DPI + epdiy rig with a known-WBF panel | 2–4 weeks | End-to-end SWTCON on real ink; §4 metrics measured; DC histogram bounded |
| **M-B3** | **Gate** (§5.16): pinout, waveforms, licence, recovery proven on a second unit | external; unknown | Written GO decision, in the style of the firmware assessment |
| **M-B4** | Bridge RTL: soft D-PHY RX + DSI parser + header/safety + timing; cocotb/Verilator testbench fed by captured DSI | 4–6 weeks after GO | Timing closure in PDS; testbench passes, including fault injection (stale sequence, bad checksum, no frames) |
| **M-B5** | Flash on the second unit (identical-image rehearsal first); binary-only bring-up | 1–2 weeks | Binary pages and scroll with camera-verified latency |
| **M-B6** | Greys, temperature, history variants, idle/link power, tuning | 3–4 weeks | Beats the Tier A metrics on E11/E14; DC telemetry within bounds over a week of use |

Tier A is about six weeks to a tuned result. Tier B's own work (B0, B1, B4–B6) is about three to
four months, and none of B4–B6 starts until B3 says GO.

## 9. Risks

| Risk | Tier | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| The CPLD is global-counter with *lost* mid-flight changes | A | medium | Stale content; heavy pacing needed | E3 finds it on day one; A12 guard; A6 late latch |
| Frontlight sync is too slow or PWM aliases at 240 fps | A | low | Timing error > 5 ms | E0 checks; fall back to 100%/0% strobes and longer bits |
| Fast-mode residue makes A3's refine worse than stock (the sim says this can happen) | A | medium | Visible dither ghost after scrolls | E7 gates A3; A10 clean; keep stock-like grey handling as fallback |
| App dither shimmer (foreign apps scroll without hints) | A/B | high for non-Keel apps | Crawling dither while scrolling | A11 block matching; worst case, screen-anchored noise as Caster and hrdl ship |
| Panfrost compute or KMS timing jitter misses 85 Hz deadlines | B | low–medium | A dropped tick repeats the last drive frame, but the bridge's sequence check makes it inert, so the cost is one frame of lost drive time | Late-latch margin; FIFO thread; M-B1 measures jitter before any flash |
| DC imbalance from early cancel or history variants | B | medium | Image retention, panel ageing | Reversal-only cancels; balanced LUTs; per-pixel `dc` with forced CLEAN; telemetry |
| **The bridge flash bricks the display** | B | **the dominant risk** | Display dead; phone otherwise boots (LK does not use the CPLD's I2C) | §5.16 gates; second unit; no flash until a recovery path is shown on an unconfigured part |
| Waveform tables cannot be recovered | B | medium | Tier B limited to binary + dither | §5.14 option 3; Tier A remains the grey path |
| Pinout cannot be recovered without destructive probing | B | medium | Tier B blocked | RE of IO configuration first; board photos; Pi 5 rig keeps the software useful |
| The panel needs a frame rate or gate timing the 68×601 mode cannot produce on mtk_dsi | B | low | Re-plan the mode | The bridge re-times lines; choose lanes and HTOTAL from mtk_dsi's PLL range |
| H1 objection to a userspace waveform engine | B | low | Design churn | §5.13 split; NEON engine could move into the kernel if required |
| LK logo no longer drawn after a Tier B flash | B | certain | Cosmetic | Draw the boot image at shutdown; the bistable panel keeps it |

## 10. Prior art

- **reMarkable 2 SWTCON.** No TCON chip: the i.MX7 LCDIF drives source and gate directly at
  85 Hz, from CPU-computed 2-bit codes packed 8 px per 2 bytes, with sync patterns in a third
  byte.
  - [waved](https://github.com/matteodelabre/waved) (Mattéo Delabre): WBF parser, region FIFO with
    bounding-box merging, double-buffered vsync thread.
  - [rM2-stuff SWTCON notes](https://github.com/timower/rM2-stuff/blob/master/doc/swtcon_architecture.md):
    xochitl's per-pixel transition index, overlapping updates ORed into a 16-slot frame ring,
    35–53 Mpix/s NEON kernels.
  - [rm2fb](https://github.com/ddvk/remarkable2-framebuffer), [yobert/swtcon](https://github.com/yobert/swtcon)
    (GC16 ≈ 330 ms + 12 ms per phase measured).
- **[epdiy](https://github.com/vroland/epdiy).** 64-byte LUT frames indexed `(to<<4)|from`,
  2 bpp at 4 px per byte, dirty-row skipping, global updates with no early cancel.
- **Modos [Caster](https://github.com/Modos-Labs/Caster)/[Glider](https://github.com/Modos-Labs/Glider).**
  16-bit per-pixel state, mirror early cancel, auto-LUT hybrid (mono, then grey behind a quiet
  barrier), screen-anchored 64×64 blue noise.
- **Rockchip EBC.**
  - [Holland RFC direct mode](https://lkml.iu.edu/hypermail/linux/kernel/2204.1/07946.html): CPU
    LUT lookups, "limits the frame rate below the panel's ideal 85 Hz".
  - [m-weigand area scheduler](https://github.com/m-weigand/linux/blob/branch_pinenote_6-12_v1/drivers/gpu/drm/rockchip/rockchip_ebc.c).
  - [hrdl `pixel_scheduling`](https://github.com/hrdl-github/linux/tree/pixel_scheduling/drivers/gpu/drm/rockchip):
    per-pixel frame numbers, NEON A2 early cancel, blue-noise Y4 conversion.
  - [be3 PR #592](https://github.com/blockeditor-org/be3/pull/592): dithered Y1 while hurried,
    then Y2 on settle.
- **NXP i.MX EPDC.** 16/64 hardware LUTs and collision masks, AUTO-waveform resubmission, update
  markers ([mxc_epdc_fb.c](https://coral.googlesource.com/linux-imx/+/27bb6b1851294273e2573c67b5c73b61092b8200/drivers/video/fbdev/mxc/mxc_epdc_fb.c),
  [Kemnade DRM RFC](https://lkml.iu.edu/hypermail/linux/kernel/2202.0/05533.html),
  [FBInk mxcfb headers](https://github.com/NiLuJe/FBInk/blob/master/eink/mxcfb-kindle.h)).
- **REAGL.** Kindle `WAVEFORM_MODE_REAGL` "ghost compensation", Kobo GLR16/GLD16. E Ink's spec
  says these are GL16 voltage lists used "in conjunction with an image preprocessing algorithm"
  ([mode declaration](https://www.waveshare.net/w/upload/c/c4/E-paper-mode-declaration.pdf)). So
  REAGL is host-side processing, which is what A5/A8b and the target pass are.
- **Waveform and ghosting papers.**
  - He et al., *Micromachines* 2020, [10.3390/mi11050498](https://doi.org/10.3390/mi11050498):
    activation from the brightness-curve inflection point; −180 ms activation.
  - Shen et al., *Micromachines* 2018, [10.3390/mi9040143](https://doi.org/10.3390/mi9040143):
    fringing-effect elimination.
  - Wang et al., *Frontiers in Physics* 2021, [10.3389/fphy.2021.723106](https://doi.org/10.3389/fphy.2021.723106):
    DC-balanced two-stage waveform, ~50% shorter.
  - Wang et al., *Micromachines* 2022, [10.3390/mi13020275](https://doi.org/10.3390/mi13020275):
    ghost −80%; notes that earlier fixes broke DC balance.
  - Lin et al., *Micromachines* 2024, [10.3390/mi15091076](https://doi.org/10.3390/mi15091076).
  - Hu et al., "Ghostbuster", EMSOFT/TCAD 2024
    ([PDF](https://web.eng.fiu.edu/gaquan/Papers/ESWEEK24Papers/EMSOFT/EMSOFT_40_Hu)):
    history automaton plus source pre-compensation.
  - Ricoh [US 8,130,192](https://patents.google.com/patent/US8130192B2/en): error diffusion with
    LUT-predicted display error.
- **Dithering.** Ulichney, "Dithering with Blue Noise", *Proc. IEEE* 1988, DOI 10.1109/5.3288.
  Wolfe et al., "Spatiotemporal Blue Noise Masks", EGSR 2022, DOI
  [10.2312/sr.20221161](https://research.nvidia.com/publication/2022-07_spatiotemporal-blue-noise-masks).
  Temporal variation is the *wrong* axis for e-paper: every change is a drive and a ghost. The
  design uses spatial masks anchored to content (A4), which is not covered by the e-paper sources
  found; Caster and hrdl anchor to the screen.
