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

The first deployed Shell at this checkpoint was SHA256
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
not fully distinguished. The role-destruction cleanup fix was then deployed as
Shell SHA256 `8bba46ae1a43c92ce8bac433a4e10aedecabe9f37964ee11a2cd4a5e7ecabdc7`.
Three normal task-card close/reopen/capture cycles passed with the same Shell
PID and no new GPU faults. A forced-runner-death test also survived capture,
but immediate relaunch timed out once; a later retry worked. That separate
launch-recovery issue remains open. Private core files,
device identifiers and full journals are retained outside this repository.

Two warm Shell starts reached first frame in 1.057 and 1.138 seconds; a third
restart reached it in 1.173 seconds. An earlier 166.7-second start remains
unexplained. After the final fix, a reboot through the default ADC entry passed:
GPU readiness was observed after 18.4 seconds of host polling and the Shell's
first frame took 2.017 seconds from its own launch. The userspace ESP read-only
guard succeeded, and no system units were failed. This is one reboot result;
it does not explain the earlier slow start or establish repeated cold-boot
performance. The stopped snapshot diagnostic was not autoloaded.

The final status bar shows the charging glyph without a question-mark
percentage placeholder. It still does not claim a measured battery percentage.
The temporary native PMIC diagnostic successfully read current twice (0 and
50.087 mA) with no cleanup errors. The configured charger ceiling is 4.208 V,
below the stock profile's approximately 4.39 V top point, so charger termination
alone is not nominal 100% SOC. No charge-limit increase was made.

Accurate state of charge, dynamic GPU power, full RAM enablement, native display,
modem/SIM/data/calls, suspend and battery life remain separate qualification work.
