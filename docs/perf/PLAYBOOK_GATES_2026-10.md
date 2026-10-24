# Proof gates, HackberryPi, 2026-10-24

Run with `scripts/gates/gates.py` against deckard r15, marathon-shell r493
and pacific r7–r8 on the 6.12.85-0-rpi kernel (no uclamp). Raw results are
under `/mnt/deckard-build/gates-run/` on the build host.

| Gate | Verdict | What was measured | Action |
|---|---|---|---|
| 1 keyboard | PROCEED | Under 1024 px image-data notification bursts the shell answered the editor in 494 ms p99 and 51 of 300 keystrokes got no report within 1 s; keyboard round trip p99 86 ms. | Fixed in r495: org.freedesktop.Notifications has its own D-Bus connection. Re-run: round trip p99 37 ms, the shell's answer time no longer flagged, 3.3 dropped frames (was 13). Idle p99 (21 ms) is above the playbook's 8 ms, not load-induced. |
| 2 hidden apps | PROCEED | With 8 hidden Android apps, Android used 12.9 % of a core with the screen on and 11.4 % with it off (idle: 0.2 %); GPU 21.5 % busy. All of it is one app: Open Camera keeps drawing (about 150 wakeups/s), driving SurfaceFlinger and the composer. The other seven are idle. | Open. Android is never told a window is hidden, so a hidden app that animates keeps rendering. The playbook's BINDER_FREEZE path can't work here (binder matches host pids, the container has its own pid namespace). |
| 3 hidden render | PROCEED | A hidden Android video still renders at 31 fps, and the shell composited at 60 fps for it on the home grid. | r494: commits from surfaces no view shows no longer wake the compositor (60 → 32 fps on the home grid). Still open: the hidden app's window item stays visible behind the home grid, so Qt repaints for each of its frames; the Android side is gate 2's item. |
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

## IO scheduler trial (2026-10-24)

A probe in the shell's cgroup (4 KiB O_DIRECT reads and 4 KiB write + fsync
every 50 ms) against a buffered and a direct writer in an app cgroup on the
HackberryPi's SD card (`/home` on dm-crypt); two runs each for mq-deadline and BFQ, one weighted:

| | mq-deadline | BFQ | BFQ + io.bfq.weight 1000/10 |
|---|---:|---:|---:|
| probe operations in 45 s | 5–6 | 31–47 | 39 |
| read p50 | 0.5–1.5 s | 66–117 ms | 71 ms |
| fsync p50 | 10–12 s | 0.4–0.6 s | 0.47 s |
| buffered writer | 20–21 MB/s | 16 MB/s | 13 MB/s |

Idle latency is the same under all three. Weights add nothing (writes likely
lose their cgroup through dm-crypt and writeback), so the io controller stays
off. marathon-base-config r57 sets BFQ on mmc devices.
