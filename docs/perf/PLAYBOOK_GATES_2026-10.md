# Proof gates, HackberryPi, 2026-10-24

Run with `scripts/gates/gates.py` against deckard r15, marathon-shell r493
and pacific r7–r8 on the 6.12.85-0-rpi kernel (no uclamp). Raw results are
under `/mnt/deckard-build/gates-run/` on the build host.

| Gate | Verdict | What was measured | Action |
|---|---|---|---|
| 1 keyboard | INCONCLUSIVE | The harness could not raise the on-screen keyboard: the HackberryPi has a hardware keyboard, so a tap in an Android editor shows none. | None. The proposed change (IME off the GUI thread) already exists. |
| 2 hidden apps | PROCEED | With 8 hidden Android apps, Android used 12.9 % of a core with the screen on and 11.4 % with it off (idle: 0.2 %); GPU 21.5 % busy. All of it is one app: Open Camera keeps drawing (about 150 wakeups/s), driving SurfaceFlinger and the composer. The other seven are idle. | Open. Android is never told a window is hidden, so a hidden app that animates keeps rendering. The playbook's BINDER_FREEZE path can't work here (binder matches host pids, the container has its own pid namespace). |
| 3 hidden render | PROCEED | A hidden Android video still renders at 31 fps, and the shell composited at 60 fps for it on the home grid. | Shell side fixed in r494: commits from surfaces no view shows no longer wake the compositor. Android side is gate 2's open item. |
| 4 render thread | PROCEED (marginal) | GUI thread busy over 16 ms in 9 of 10 launch peeks, longest 19.7 ms; render thread never stalled; 0.1 missed frames per peek on average. | None yet: one missed frame at most per launch. |
| 5 bridge footprint | RECORD | Release-gate record for comparison with the next bridge build. | None. |
| 6 Python patcher | DONE | The image patcher is Rust (`deckard-image-tools`). | None. |
| 7 host guards | DONE | 11/11 host-side checks hold. | None. |

## Harness fixes made during the run

- `analyse.py` crashed on ftrace's `-------` placeholder tgid after gate 2's
  80-minute run.
- Busybox tar refused the touch FIFO in the result archive (gate 4).
- F-Droid uninstalls in the undo step report failure because Android writes
  `packages.list` late; the apps were removed.
