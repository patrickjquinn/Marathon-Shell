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

## Later battery and display qualification

The deployed Shell advanced to `48fa0938c677c308d52d08d9a0b4f966fdf012bc135baf5d62e2fc6faa33ecd5`.
The provisional native gauge now exposes measured current, signed hardware charge
counter and temperature on the existing fuel-gauge supply. Its stock-profile
model seeded an estimated 82%; UPower and Settings agreed. This is not calibrated
SOC. A redundant charger configuration supply is explicitly ignored by a patched
UPower; one battery reports 13.32 Wh rather than counting it twice. Shell's
experimental-model guard and UPower's `Ignore` critical action remain necessary.
An actual 12.5-second producer pause removed capacity and displayed “Battery level
unavailable”; resumption and an ordinary service restart both reseeded correctly.
Battery-only boot and physical battery-life qualification remain incomplete.

Sleep appeared to freeze the GPU session because the generic ACTIVE-only DRM
commit left SimpleDRM's plane attached. A Q25/SimpleDRM-specific transaction now
retains a framebuffer and mode blob, tests and atomically detaches the plane,
connector and mode, then restores them before Qt resumes. Other drivers retain
their existing path. Deployed candidate
`a71655b371dae61cdbf477550ebe87db6247304cedea6fb27f09da81f9edc323`
passed 20 power-key detach/wake cycles with one Shell process and no new kernel
log entries. Five seconds blanked used approximately 0.20% of one CPU core.
Wake-to-frameSwapped notifications were approximately 3.7–4.7 ms; these are
software notifications, not measured panel or photon latency. One retained
framebuffer is expected; framebuffer count did not grow with every cycle.

**Physical illumination is not fixed:** the operator confirmed that both the
screen backlight and keyboard light remain on. Clearing the retained picture is
only a partial fix, not proof of display power-off, usable standby or battery
life. A controlled software-renderer comparison is recorded on USB; no physical
result is assumed without an operator observation. The known OCP2131 bias-voltage
registers are not treated as brightness controls. The keyboard's verified
brightness register reads 255; a standard LED driver is being qualified
separately. No blind AW99706/RT4831 binding or guessed panel-voltage write was made.

All three system power profiles were exercised on both CPU clusters: saver used
`powersave`, balanced used `ondemand`, and performance used `performance`.
Balanced was restored. GPU runtime PM and its temporary fixed-frequency/rail
workaround remain separate unresolved power-saving limits.

Connectivity priority is Wi-Fi, then Bluetooth, then cellular. A same-SoC source
port produced matched-tree WMT, BTIF and adapter modules with joint modpost and
40 focused host tests passing, without fake exports or unused SDIO imports.
They have not been loaded: CONSYS power/EMI ownership and native firmware
bootstrap remain unqualified, and the AXI WLAN backend is still required.
No native Wi-Fi interface, Bluetooth controller or functional cellular radio is
claimed. Prototype sources, module hashes and logs are under USB
`q25/wifi-bringup/joint-linux7-port/`; this is not a canonical package delivery.
