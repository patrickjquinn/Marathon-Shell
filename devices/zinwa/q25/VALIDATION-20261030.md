# Q25 device validation, 2026-10-30

The full 783-package mutable ext4 Duranium root boots with native keyboard and
touch input. The user confirmed clean, smooth rendering at 1.5× scale. Graphics
use Panfrost through a Q25 KMSRO shim and firmware SimpleDRM scanout; native
MediaTek display takeover remains unfinished.

The tested AUXADC correction reports 4.182–4.183 V instead of an overflowing
conversion. The kernel still exports no measured capacity. Shell and Settings
therefore show an unknown level, and the Battery page independently shows
“Charging”. Genuine measured zero remains distinct from unknown in unit tests.
See `kernel/README.md` for the tested kernel and its packaging limitation.

The deployed Shell at this checkpoint is SHA256
`742a38a0677e2b977325582f1e47c5ed77cd1281f30499d3dffa704cefe1edcc`;
the app runner is
`058fa0dff08b03d626528c184282961cfab49730e2f38f7d79e7cc5fd56e15a9`.
All 12 selected Settings/runner/compatibility-QML paths matched their delivery
hashes after atomic installation. Target native-loader checks passed.

A 16-swipe Settings test produced five complete active 240-swap windows:

| Metric | Range |
| --- | --- |
| Median compositor swap-notification interval | 5.992–6.068 ms |
| P99 interval | 7.547–7.939 ms |
| Maximum interval | 7.929–8.760 ms |

An initial window spanning idle and active rendering is excluded explicitly.
These are Qt `frameSwapped` notification intervals, **not physical refresh rate,
dropped-frame counts or input-to-photon latency**. No new GPU fault appeared
during this run, and the post-test capture remained clean. GPU policy remained
390 MHz with runtime PM held on; GUI affinity remained CPUs 4–7.

One Shell crash occurred during screenshot validation. The exact core and
matching ELF resolve the fault to `QWaylandXdgToplevel::appId()`, called by
`WaylandCompositor::showsSecureContent()` through a stored raw role pointer.
The core is truncated; stale role lifetime versus prior object corruption is
not fully distinguished. This is an open validation failure until the lifecycle
fix and close/reopen/capture regression have been tested. Private core files,
device identifiers and full journals are retained outside this repository.

Two warm Shell starts reached first frame in 1.057 and 1.138 seconds; a third
restart reached it in 1.173 seconds. An earlier 166.7-second start remains
unexplained. These observations do not establish cold-boot performance.

Accurate state of charge, dynamic GPU power, full RAM enablement, native display,
modem/SIM/data/calls, suspend and battery life remain separate qualification work.
