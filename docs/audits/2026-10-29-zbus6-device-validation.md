# zbus 6 deployment and device validation — 29 October 2026

Runtime sources: Marathon Shell `68565216`, including zbus 6, readable Event
Hub source names and ordered foreground CPU/I/O priorities; Deckard
`d5c317833bbe0844eb2809a8ecf873e09379cafe`, including initial foreground
protection, cancellable idle reclaim, disabled Android window transitions,
and authenticated foreground resource profiles.

## Device and deployment

HackberryPi / Raspberry Pi Compute Module 5 Lite, four CPU cores, 16 GiB RAM,
Nura edge, kernel `6.12.85-0-rpi`, 720×720 display at 60 Hz.

Built native aarch64/musl APKs using Alpine edge:

| Payload | Revision |
| --- | --- |
| Marathon Shell and icon theme | 1.0.0-r516 |
| Deckard | 0.1.0-r26 |
| Pilot | 0.1.0-r5 |
| pilotd | 0.1.0-r15 |
| Reef | 0.1.0-r2 |
| keel-mcp | 0.1.0-r6 |

This image has no `apk` executable. Deployment used the APKs' `/usr` payloads,
atomic file replacement, backups and hash verification. It did not update
the image's APK database. The I/O delegation drop-in from base-config
1.0.0-r60 was deployed separately; the full base-config payload was not
installed. Existing configuration and application data were
preserved. After replacing Deckard's `/usr` payload, the root
`deckard-container.service` was restarted so its overlay/font synchronization
steps ran before Android booted. A simple Android stop/start through D-Bus
had left the generated startup overlay stale; the final check caught this,
and the service restart corrected it. Both live scales were already zero
during the timing runs; the corrected Android startup file was then read
back inside the restarted runtime and both scales checked again.

Shell/icon deployment verified 11,939 files and symlinks, the
Pilot/Reef/MCP deployment 75, and Deckard 70. Deployment receipts and rollback
archives remain under `/var/lib/marathon-deploy/zbus6-20261029` on the device.

The running Shell executable matched its staged APK payload at SHA-256
`959e499134ca704df945ee818c1073cfccde05acae44bc5e66b93d029be2178f`.
The running Deckard bridge matched the installed r26 binary at
`4e511a263154f99113ae79c57f458b17eb9e95563d902420c5765c517cd2bf8e`.
A scan of deployed executable/library mappings found no replaced deployment
files still mapped from deleted inodes. Both system and user failed-unit
lists were empty after the restart, and Android reported boot completed.
The display was awake with backlight power 0 and brightness 8/10.

## Tests and security

| Workspace | Normal | With CPU workers | Ignored |
| --- | ---: | ---: | ---: |
| Shell main workspace | 679 passed | 679 passed | 4 |
| Deckard | 181 passed | 181 passed | 0 |
| Reef | 38 passed | 38 passed | 0 |
| Pilot frontend | Builds/checks pass | Builds/checks pass | No Rust tests |

The final 679-test main-workspace load run measured 99.98% CPU over 256.64
seconds, including Cargo recompilation. Deckard's final 181-test load run
measured 100.00% over 12.40 seconds.
Load runs used eight host CPU workers. All four
workspaces passed formatting and strict Clippy across all targets. The Hub
regression suite passed 28/28 tests with the real Silica plugin and Qt 6.11.1. Deckard's
Alpine release package passed all 172 tests selected by its package check;
the complete host workspace adds nine tests outside that package selection. Shell tests ran with
`MARATHON_TEST_STRICT=1`, including private D-Bus and PipeWire/WirePlumber
integration tests. See [test counts](2026-10-29-zbus6/tests.json).

An additional full normal repetition stalled in Pilot's private-bus test
`the_shell_names_a_marathon_apps_process`. Its mock bus still answered
introspection and a debugger showed the Tokio/zruntime threads waiting.
That extra run was terminated; it is not counted as a pass. Diagnostic phase
logging was added temporarily, and the affected test passed 100 isolated
repetitions plus 100 complete four-test fixture groups with normal parallel
test execution. The diagnostic edits were then removed and a fresh full
679-test normal workspace run passed with the original test source. The
679-test loaded run also passed. The cause of that one stalled repetition
has **not** been established; this report does not claim it was fixed or
proven unrelated to the migration. See [fixture follow-up](2026-10-29-zbus6/fixture-follow-up.json).

Shell's four intentional ignores are a generated action that modifies real
data, a Flathub catalogue test, a DST subprocess test invoked by its parent
test, and a documentation example. The separate factory-reset suite passed
all 11 tests after build-disk writes settled; its first run timed out in a
host-wide `sync` while that disk was busy.

RustSec reported zero known vulnerabilities in all four workspaces. Deckard,
Pilot and Reef have no maintenance warnings. Main retains five transitive
maintenance warnings: `basic-toml` through current i18n dependencies, `paste`
through current Lofty, and `zbus_names`, `zvariant`, `zvariant_derive` through
current `secret-service`. The latter still uses zbus 5 internally. All of our
direct D-Bus code uses zbus 6 with defaults disabled and explicit features.
The refresh removed async-std and the previous rustybuzz/ttf-parser warnings.
The four machine-readable cargo-audit reports are retained in the measurement
directory. [Build source verification](2026-10-29-zbus6/source-inputs.json)
compared 1,373 Shell runtime files and 363 Deckard source files against
their committed trees with no mismatch.

## D-Bus latency

The same libdbus client binary ran before and after deployment. It uses one
persistent connection, excludes process startup and request construction,
warms up each endpoint with 20 requests, then measures 1,000 replies. Each
phase has three trials per endpoint. Figures below are medians of the three
trial percentiles, not percentiles of pooled samples.

Both phases temporarily selected `performance` at 2.4 GHz and restored the
previous `schedutil` governor afterward. Loaded runs used four CPU workers.

**Idle** — microseconds

| Endpoint | Before p50 / p95 | Final r516/r26 p50 / p95 |
| --- | ---: | ---: |
| bus-control | 33.37 / 34.42 | 33.41 / 34.26 |
| deckard-runtime | 107.80 / 115.78 | 99.98 / 108.26 |
| audio-properties | 97.11 / 105.59 | 97.94 / 105.15 |
| weather-properties | 113.67 / 153.42 | 111.68 / 150.48 |
| pilot-settings | 107.46 / 112.41 | 76.63 / 83.72 |

**Load** — microseconds

| Endpoint | Before p50 / p95 | Final r516/r26 p50 / p95 |
| --- | ---: | ---: |
| bus-control | 48.05 / 56.69 | 49.04 / 60.48 |
| deckard-runtime | 138.68 / 147.41 | 127.26 / 136.24 |
| audio-properties | 129.29 / 143.74 | 119.09 / 134.02 |
| weather-properties | 150.41 / 194.66 | 116.42 / 190.11 |
| pilot-settings | 101.37 / 109.74 | 106.96 / 117.17 |

All 30,000 final requests completed with 0 errors. Measured CPU busy: 97.18% over 2.13s

These measurements include the complete update and current running state.
The initial r515 sample had an idle audio regression of about 21/22 µs
at p50/p95; the earlier raw results are retained rather than discarded.
The loaded control also changed substantially, showing scheduler/running
state contributes to the difference. This does not isolate zbus overhead.

The control is `org.freedesktop.DBus.GetId`; application endpoints are
Deckard `GetRuntime`, Audio/Weather `Properties.GetAll`, and Pilot `Settings`.
These are end-to-end service measurements of the complete dependency update
and running state, not an isolated benchmark of zbus internals. Raw results
and CPU/frequency metadata are in [the measurement directory](2026-10-29-zbus6/).

## Display presentation and GUI activity

Private tracefs instances recorded DRM presentation events and GUI/render
thread scheduling during ten Hub edge gestures alone and ten during cold
Android Settings launches. No trace events overran the buffers. The previous
Shell binary was temporarily restored for comparison, then r514 was restored
and its running hash checked. Other components remained fixed during this
Shell-binary comparison; Deckard was r23 for both runs.

| Shell / phase | Presented frames | Missed intervals | Longest presentation gap | Longest GUI busy span |
| --- | ---: | ---: | ---: | ---: |
| Previous / idle gestures | 388 | 0 | 16.68 ms | 22.18 ms |
| r514 / idle gestures | 382 | 1 | 33.33 ms | 28.30 ms |
| Previous / launch gestures | 483 | 0 | 16.69 ms | 43.75 ms |
| r514 / launch gestures | 463 | 0 | 16.68 ms | 44.99 ms |

The frame gate is **not a stall-free pass**: GUI busy spans exceeded 16 ms in
10/10 previous-binary launch gestures and 9/10 r514 gestures. Neither run had
a render-thread busy span above 16 ms. Presentation stayed at approximately
60 Hz during the measured launch gestures, but GUI work remains a latency
limitation. The harness excludes gaps of 250 ms or longer as idle; these
numbers should not be read as a universal frame-drop rate.

See [r514 traces summary](2026-10-29-zbus6/frames-new/result.json),
[previous-binary summary](2026-10-29-zbus6/frames-old/result.json), and their
per-gesture CSVs.

A later three-repetition r514/r24 sample, after TikTok launch/trim tests and
with TikTok left in the background, was worse: 128 baseline frames with one
missed interval (33.33 ms maximum gap), and 136 launch-phase frames with nine
missed intervals (50 ms maximum gap). GUI busy spans reached 39.64/46.56 ms;
one launch gesture had a render busy span above 16 ms. Device I/O pressure
was then about 45% over the preceding ten seconds. This workload differs
from the earlier A/B and must not be hidden by the earlier zero-miss launch
sample. See [the later sample](2026-10-29-zbus6/frames-r24-background-video/result.json).

| Earlier r515/r25 phase | Presented frames | Missed intervals | Longest gap | Longest GUI / render busy span |
| --- | ---: | ---: | ---: | ---: |
| Idle gestures (10) | 372 | 0 | 16.68 ms | 1.03 / 1.76 ms |
| Cold-launch gestures (10) | 478 | 7 | 50.01 ms | 49.64 / 13.96 ms |

That r515 trace lost no events. Idle gestures had no GUI/render busy span
above 16 ms; all ten cold-launch gestures had a GUI span above 16 ms. The
frame gate returned **PROCEED**, not PASS. Seven missed launch-phase
presentation intervals and the 49.64 ms GUI busy span remain a real
limitation. This trace supports smooth warmed Hub gestures, not a claim that
all launch or app navigation jank has been eliminated. See
[the r515 trace summary](2026-10-29-zbus6/frames-r515-final/result.json).

A subsequent r515/r25 run after refreshing the Android startup overlay recorded
388 idle frames with no missed intervals, and 480 cold-launch frames with
four misses (maximum gap 33.36 ms). Its GUI busy spans were 27.22/45.31 ms,
render spans 9.16/15.58 ms, and trace overruns zero. The gate again returned
PROCEED. This run illustrates run-to-run variability, not a new stall-free
pass. See [post-overlay trace](2026-10-29-zbus6/frames-r515-post-overlay/result.json).

The final r516/r26 trace recorded **369 idle gesture frames, zero missed
intervals**, and GUI/render busy maxima of 1.08/5.34 ms. During ten cold
Android Settings launches it recorded **478 frames and eight missed
intervals**, a **66.66 ms** longest presentation gap, and GUI/render maxima
of **55.31/12.59 ms**. Trace overruns were zero; the gate remained **PROCEED**.
All ten launch gestures had a GUI busy span above 16 ms. Foreground scheduling
has not removed this cold-launch GUI stall; this final sample is worse than
the r515 post-overlay sample on these measures. See
[final r516 trace](2026-10-29-zbus6/frames-r516-final/result.json).

## Android startup, foreground protection and trimming

Full deployment testing exposed a startup race: Deckard watched future
foreground signals but never read the app already in front. Starting the
bridge after TikTok's launch left Android classified as idle and allowed a
trim while Shell reported TikTok in front. The initial timing run then
contained activity-service failures during an Android framework restart;
those failed trials are excluded from performance figures.

Deckard r24 subscribes before reading the current foreground, keeps listening
if that first read fails, and disables trimming while foreground state is
unknown or the watcher has ended. A private-bus regression starts the watcher
with an app already in front and sends no change signal. Device validation
then restarted the bridge while TikTok was already in front, reproducing the
ordering that exposed the bug.

With r24, restarting the bridge while TikTok was already in front left
Android resident memory stable at 1,950.9–1,955.5 MiB for 70 seconds, with no
trim. Leaving it on Home then reclaimed 1,968 → 290 MiB in 9.8 seconds. The r25
repeat and return-during-reclaim test are described in the navigation follow-up.
When allowed to finish on r25, idle trim reclaimed 1,334 → 308 MiB in 9.8
seconds; these different workloads do not establish a reclaim-speed improvement.

Three forced-stop launch waits before migration were 1,543 / 1,950 / 3,013 ms;
three valid r24 waits were 1,407 / 615 / 3,328 ms. Android reported a cold launch
with 1,392 ms TotalTime only for the first r24 trial, and UNKNOWN for the other
two. These small, noisy samples do not demonstrate a startup speedup, and
WaitTime is not a measured first-frame latency.

## Navigation follow-up

The Event Hub's old history could outlive an installed desktop entry, exposing
package IDs such as `deckard.com.nononsenseapps.feeder` and `org.kde.itinerary`.
The fix retains the notification sender's display name in existing persisted
metadata, resolves current/legacy desktop aliases, refreshes labels on registry
reloads even when its count is unchanged, and gives old unnamed history a
readable final-segment fallback (Feeder / Itinerary).

Android's window and activity transition scales were unset (the platform
default of 1). Deckard now sets both to zero at boot: Marathon owns the outer
window transition. App content animators retain their normal setting. The
seamless per-app Wayland backend remains enabled.

A separate idle-reclaim race allowed a single multi-second kernel reclaim
request to continue after Android returned to the foreground. Reclaim now runs
in requests of at most 32 MiB and checks the foreground generation between
requests, stopping on unknown state, foreground changes or exhausted reclaim.
Three new regression tests cover cancellation, exhausted reclaim and the
bounded total budget. On the r25 device, TikTok stayed at 1,436.7–1,437.1 MiB
for 70 seconds in front. After Home had been idle for 60.15 seconds, returning
to TikTok during reclaim ended that pass after 0.2 seconds (journal), retaining
about 1,294 MiB rather than completing a full trim. The launch API reply took
57.48 ms; this is not a first-frame measurement. Two inspected captures showed
video still advancing after the return. See [the cancellation trial](2026-10-29-zbus6/after-android-cancel-trim.jsonl).

Deckard's final suite passed 181 tests, including private-bus foreground
transitions and denial of a different process running under the same UID.
Its loaded run measured 100.00% CPU over 12.40 seconds; strict Clippy passed.

TikTok navigation remains a measured limitation. Five upward feed swipes,
using 24 input steps and a 1.5-second pause per swipe, produced:

| Configuration | Frames | Janky frames | CPU p50 / p95 / p99 | GPU p50 / p95 / p99 |
| --- | ---: | ---: | --- | --- |
| Original animation settings | 272 | 24 (8.82%) | 5 / 31 / 61 ms | 2 / 4 / 6 ms |
| Android window/activity transitions off | 272 | 24 (8.82%) | 5 / 31 / 77 ms | 2 / 4 / 8 ms |
| Temporary performance governor | 257 | 21 (8.17%) | 5 / 38 / 61 ms | 2 / 4 / 6 ms |
| Refreshed speed-profile compilation, app restarted | 288 | 29 (10.07%) | 5 / 36 / 73 ms | 2 / 5 / 8 ms |

These runs loaded different feed videos and are exploratory, not controlled
proof of a small performance difference. Animation removal and profile
compilation did not fix warm feed scrolling. The governor was restored.
Android reports hardware Broadcom V3D rendering and a 60 Hz display; cgroup
CPU is unrestricted, with no memory-high/max/oom events. An Android atrace
sample located 30–40 ms main-thread frame work, including 27–31 ms view
measurement. GPU percentiles were substantially lower. A separate 400 Hz
simpleperf sample recorded 1,746 samples with none lost; TikTok's bundled
ByteVC2 decoder accounted for about 22% of sampled app CPU. The temporary
profiling permission was restored. These findings do not establish that all
remaining jank is attributable to Deckard, or that it is resolved. Raw
[Android frame and process measurements](2026-10-29-zbus6/android-navigation/)
are retained separately from the compositor traces.

| Final r515/r25 navigation trial | Frames | Janky frames | CPU p50 / p95 / p99 | GPU p50 / p95 / p99 |
| --- | ---: | ---: | --- | --- |
| 1 | 297 | 26 (8.75%) | 5 / 30 / 65 ms | 2 / 4 / 7 ms |
| 2 | 287 | 21 (7.32%) | 5 / 25 / 57 ms | 2 / 4 / 7 ms |
| 3 | 306 | 20 (6.54%) | 5 / 28 / 53 ms | 2 / 5 / 8 ms |

Across the three final feed trials, 67 of 890 frames were janky (7.53%). This remains unresolved scrolling jank; different feed content prevents attributing the modest difference from the earlier single 8.82% trial to a specific fix. CPU p95 was 25–30 ms, while GPU p95 was 4–5 ms. The app was visually confirmed on its feed before the trials. Subsequent search-screen captures filled the client area without an outer window scale; the runtime's boot script and both scale settings were also checked after the overlay refresh.

The final r516/r26 automatic policy was then measured again, without manual
cgroup overrides. Warm trials used the restored schedutil governor; the loaded
trial temporarily used performance and restored schedutil afterward.

| Final r516/r26 trial | Frames / janky | Jank | CPU p50 / p95 / p99 | GPU p50 / p95 / p99 |
| --- | ---: | ---: | --- | --- |
| 1 | 290 / 29 | 10.00% | 5 / 40 / 61 ms | 2 / 4 / 7 ms |
| 2 | 283 / 21 | 7.42% | 5 / 29 / 81 ms | 2 / 4 / 7 ms |
| 3 | 250 / 23 | 9.20% | 5 / 31 / 57 ms | 2 / 3 / 6 ms |
| load | 272 / 30 | 11.03% | 5 / 40 / 61 ms | 2 / 4 / 6 ms |

Warm aggregate: **73/823 = 8.87% janky frames**. The loaded
trial measured **99.24% CPU** and **11.03% jank**. These final automatic-policy
results confirm that significant warm scrolling jank remains. Different feed
content prevents interpreting the change from r515's 7.53% as an isolated
policy regression or improvement. The final loaded result is consistent with,
but does not replace, the alternating contention experiment below. TikTok
was visually checked before and after the swipes and video was advancing.
See [final Android results](2026-10-29-zbus6/android-navigation/r516-summary.json).

## Foreground CPU and physical I/O scheduling

The physical SD card already used BFQ (`none mq-deadline kyber [bfq]`). Android
shares the host kernel and physical block queue; there is no separate Android
physical scheduler to select. Loop devices retaining `none` does not bypass
physical BFQ. `CONFIG_UCLAMP_TASK` is absent on this kernel, so the previous
uclamp-only foreground boost had no effect.

Deckard now follows Marathon's current foreground and subsequent changes,
subscribing before the initial snapshot. Its root service applies these
relative shares to the complete Android runtime:

| State | CPU weight | BFQ weight |
| --- | ---: | ---: |
| Android app foreground | 200 | 200 |
| Native app / Home foreground | 50 | 25 |
| Foreground state unavailable | 100 | 100 |

The policy adds no CPU quota or replacement for Android's per-thread nice and
real-time priorities. TikTok already had important threads at nice -20.
The D-Bus setter accepts root or the exact registered session-owner PID and
UID; a different process under that UID was denied on the device, leaving
weights unchanged. Runtime start reapplies the cached profile.

Native apps receive the same foreground/background shares. Systemd-managed
external scopes use asynchronous, serialized property updates that consult
the newest focus request, discarding requests for removed scopes. The device
kernel exposes BFQ weights rather than generic `io.weight`: systemd IOWeight
1200 maps to BFQ 200, while IOWeight 25 maps to BFQ 25. This conversion has a
regression test and was checked against live kernel readback. The base-config
drop-in delegates I/O to the user manager, and the session wrapper activates
I/O accounting. The running user manager was reexecuted to discover the newly
delegated controller; both failed-unit lists remained empty.

Device validation also exposed a native-to-Android lifecycle omission: Reef
kept CPU/BFQ 200/200 after TikTok took focus, even though native-to-native
switching correctly lowered the previous app to 50/25. Android surfaces do
not pass through the native foreground function. Shell `68565216` now
backgrounds that previous native app from the authoritative foreground event,
releasing its budget and allowing normal idle freezing. The original failing
readback is retained in [handoff-before.json](2026-10-29-zbus6/priorities/handoff-before.json).
`tools/bench/foreground-priorities.py` checks both sides of each switch on
the device and fails on the old retained-foreground behavior. The final run
passed all four switches, including Reef at 50/25 while TikTok held 200/200;
returning to Pilot restored its 200/200 and Android 50/25. See
[handoff-after.json](2026-10-29-zbus6/priorities/handoff-after.json).

Live r26 transitions were automatic: TikTok 200/200 → Pilot 50/25 → TikTok
200/200. This is actual cgroup readback, not just the API's requested state.

Four-CPU contention, four alternating five-swipe TikTok feed trials:

| Profile | CPU busy | Frames / janky | Jank | CPU p95 / p99 |
| --- | ---: | ---: | ---: | ---: |
| Previous 50/25 | 99.2–99.5% | 255 / 59 | 23.14% | 77 / 150 ms |
| Foreground 200/200 | 99.2–99.5% | 270 / 27 | 10.00% | 38 / 69 ms |
| Previous 50/25 | 99.2–99.5% | 250 / 51 | 20.40% | 69 / 105 ms |
| Foreground 200/200 | 99.2–99.5% | 273 / 28 | 10.26% | 42 / 69 ms |

These trials manually selected the same profiles now selected automatically.
GPU p95 remained 4–5 ms. Feed content varies and the first trial had 4,552
major faults, versus 136–229 afterward; the second alternating pair reduces
that cold-start confound but does not remove content differences. This is
strong evidence of improved CPU contention behavior, not elimination of jank.

A separate read-only physical-I/O test used two concurrent 4 KiB random
O_DIRECT readers of the same public Android system image for ten seconds,
one inside the Android cgroup and a background peer at BFQ weight 100.

| Android BFQ weight | Android MiB/s | Background MiB/s |
| --- | ---: | ---: |
| 25 | 2.017 | 7.214 |
| 200 | 6.621 | 4.069 |
| 25 | 2.479 | 8.239 |
| 200 | 6.459 | 4.253 |

Physical-device `io.stat` advanced, confirming that the cgroup shares reach
the SD-card queue. Android read p95 remained approximately 0.56 ms; the evidence
supports a bandwidth-share improvement, not a tail-latency improvement.
Temporary workers/cgroups were removed and the previous governor restored.
Raw [priority A/B results](2026-10-29-zbus6/priorities/) retain all four trials
of both experiments. Policy follows the [kernel BFQ documentation](https://docs.kernel.org/block/bfq-iosched.html),
[systemd's BFQ conversion](https://github.com/systemd/systemd/blob/main/src/basic/cgroup-util.h),
and [Android task-profile architecture](https://source.android.com/docs/core/perf/cgroups).

## Binary sizes and idle process measurements

Sizes are actual stripped device executables/modules, compared with backups
of the previous deployed files. This measures the combined dependency and
package refresh; compiler and dependency changes are not separated.

| Binary | Before bytes | Final bytes | Change |
| --- | ---: | ---: | ---: |
| `marathon-shell-bin` | 28,342,984 | 28,930,880 | +2.07% |
| `deckard-bridge` | 4,069,744 | 4,004,072 | -1.61% |
| `deckard-runtime` | 1,514,104 | 1,381,872 | -8.73% |
| `deckard-containerd` | 1,645,176 | 1,513,976 | -7.97% |
| `shoal-pilot` | 2,961,840 | 2,674,360 | -9.71% |
| `shipwright-reef` | 3,223,136 | 3,203,480 | -0.61% |
| `pilotd` | 7,166,560 | 6,969,688 | -2.75% |
| `keel-mcp` | 3,152,128 | 2,757,752 | -12.51% |

[Binary sizes and hashes](2026-10-29-zbus6/binary-sizes.json) come from the
verified APK payloads; baseline sizes were recorded before deployment.

| Process | Before PSS KiB | Final PSS KiB | Before / final threads | Before / final idle CPU (one core) |
| --- | ---: | ---: | ---: | ---: |
| `marathon-shell-bin` (1 / 1 processes) | 234,384 | 223,023 | 30 / 27 | 0.167% / 0.133% |
| `deckard-bridge` (1 / 1 processes) | 5,545 | 5,342 | 28 / 28 | 0.000% / 28.314% |
| `deckard-runtime` (1 / 1 processes) | 1,856 | 1,723 | 13 / 10 | 0.000% / 0.000% |
| `deckard-containerd` (1 / 1 processes) | 1,848 | 1,761 | 6 / 6 | 0.000% / 0.000% |
| `pilotd` (1 / 1 processes) | 25,652 | 20,540 | 5 / 2 | 0.000% / 0.000% |
| `marathon-audiod` (1 / 1 processes) | 2,563 | 2,391 | 6 / 4 | 0.000% / 0.000% |
| `marathon-weatherd` (1 / 1 processes) | 33,149 | 33,133 | 4 / 3 | 0.000% / 0.000% |
| `marathon-maild` (1 / 1 processes) | 3,404 | 3,980 | 4 / 4 | 0.000% / 0.000% |
| `marathon-telephonyd` (1 / 1 processes) | 2,999 | 2,791 | 6 / 4 | 0.033% / 0.000% |

Both snapshots cover approximately 30 seconds. Final capture followed the
controlled RPC tests with Home visible and Android in the background.
Per-PID data, including hashes, remain in the raw snapshots. Earlier r515
and post-overlay snapshots are also retained; absent processes are not
claimed as dependency-related memory savings.

Memory snapshots compare long-running old processes with restarted, warmed
new processes. Application caches and service restarts affect PSS; these
figures do not isolate the memory cost of zbus. CPU percentages use one core
as 100%. Raw snapshots retain executable hashes and thread counts.

## Build storage

The host root filesystem remained at approximately 3.2 GiB free. With the
user's permission, the removable 128 GB SanDisk at `/dev/sda` was reformatted
as ext4, labelled `marathon-build`, and mounted at
`/run/media/patrickquinn/marathon-build`. It retained more than 90 GiB free during final packaging. Host validation targets and the package builders' Podman storage use
that drive. Package workspaces initially used tmpfs. The final incremental
Shell build filled its 7 GiB tmpfs; its Rust target was moved to the USB
container storage and the build resumed without using the host root disk.
The existing `/dev/sdb` build disk and internal NVMe partitions were preserved.
After measurements, 1.31 GiB of this deployment's temporary `/run` staging
files were removed from device RAM. Device rollback archives/receipts were
retained (926 MiB on `/var`, with 5.5 GiB free); final APKs are mirrored on
USB. The staging cleanup followed the timing runs, so it is not represented
as a measured timing improvement.

## Visual and log checks

Inspected captured frames of the unlocked launcher, Pilot, Pilot's live cover
before/after a daemon restart, Reef's catalog and categories, Settings with
live radio state, and TikTok. Pilot's cover changed from a local capability
response to “Ask anything” after `pilotd` restarted, without restarting the
app. Those requests stayed on the phone. The native web renderer also
executed JavaScript in a local test document and returned the changed DOM.
After r515 deployment, Pilot's main page, Reef's loaded catalog hero and
Settings' live radio state were reopened and inspected again. Hub captures
showed Feeder and Itinerary instead of raw IDs in both filters and rows.
After the final r516 handoff fix, Reef's settled catalog was reopened and
inspected; returning Home read Android CPU/BFQ 50/25. The Hub was captured and inspected again;
its filters and rows retained readable names. Pilot was relaunched and its
settled main page inspected after five seconds. An earlier capture taken
immediately after the priority test still showed outgoing TikTok content;
it was not accepted as proof that Pilot had finished drawing.
Both Android window/transition settings read back as zero after this restart,
with `sys.boot_completed=1`.
A device D-Bus regression replaced a synthetic notification without sending
its display name; SQLite metadata retained the earlier sender name. Temporary
notifications were closed and the temporary desktop entry was removed.
See [the device source-name proof](2026-10-29-zbus6/notification-source-device-proof.json).

The user reported a dark physical screen during deployment and confirmed
that the device's top button restored its backlight. Captures alone were not
treated as proof of physical panel visibility. Driver checks showed DPI
connected, scanout active at 720×720/60 Hz, and backlight 8/10 after waking.

Journals were followed during deployment and the final validation window,
and both the kernel ring buffer and persisted kernel journal were inspected.
The r26 window beginning 14:25 UTC contained 1,768 kernel-log lines and
2,846 journal lines when checked. Searches found no OOM kills, V3D
fault/hang/reset messages, DRM errors, block-I/O errors, under-voltage,
thermal throttling, segfaults, fatal signals or coredumps. This is a bounded
log check, not proof that every Android feature is supported.

Warnings remain: Android boot reports unavailable vendor audio/camera HAL
paths, absent battery-health attributes, restricted BPF sysctls and missing
BPF features; Android process teardown also reports already-removed cgroup
paths. Systemd emitted “Failed to adjust io pressure threshold, ignoring:
Resource busy” while starting scopes. These did not produce failed units.
Earlier before/after Shell logs also contained a delayed callback TypeError
at Silica PageHeader.qml:119. An earlier loop-device busy startup retry
resolved, and an OTA protocol error preceded deployment. GeoClue's idle
shutdown was followed by a normal restart. None of these warnings is being
represented as a clean warning-free log.

Screenshots validate compositor output, not physical panel visibility.
The user-confirmed backlight event and sysfs readback are recorded separately.
Personal screenshots, network identifiers and full journals remain outside
the repository; the report retains aggregate checks and nonpersonal results.

The final r516 check repeated the failed-unit and stale-mapping scans: zero
failed system/user units and zero replaced deployment files still mapped.
The Android crash buffer was empty and ActivityManager reported no ANR since
boot. Its cgroup recorded zero memory-high/max/oom events; the final TikTok
foreground readback was CPU/BFQ 200/200. The governor had returned to
schedutil and the backlight read power 0, brightness 8. The final journal
window begins 15:17 UTC; kernel and journal signature counts are retained in
[final device checks](2026-10-29-zbus6/final-device-checks.json).

## Remaining performance work

The migration/deployment and foreground resource policy are implemented; smooth
navigation is not fully achieved. The next measurable targets are the Shell's
55.31 ms GUI busy span during cold Android launches and TikTok's 29–40 ms CPU
p95 during warm feed navigation, while GPU p95 is only 3–4 ms. Capture call
stacks during those exact workloads before changing another governor, compiler
profile or global nice policy. Compare the same launch/gesture repetitions and
constant app content where possible. A result with zero missed idle intervals
does not close the cold-launch or warm-feed findings above.

Recorded text/CSV exports normalize line endings and trailing whitespace;
measurement values are unchanged.

## Storage clarification

A subsequent sysfs check identified `mmcblk0/device/type=SD` and
`mmcblk0/device/name=SD32G`. The earlier eMMC description was incorrect.
The encrypted `/var` mapping is backed by `mmcblk0p6`, so Android's image/data
and the host share that SD card. `/proc/swaps` lists only `/dev/zram0`;
swap is compressed RAM, not an SD-backed swap file.

In the final three feed trials, TikTok recorded 11,149 / 774 / 286 major
faults; system-wide swap-ins were 11,963 / 791 / 316 pages. Those are
process-local versus system-wide counters, so individual faults cannot be
paired, but the swap-ins make it inappropriate to attribute all major faults
to SD reads. System-wide I/O PSI `some` totals increased approximately
29 / 70 / 45 ms during the respective ten-second trials. Short storage stalls
can still miss a frame deadline; these counters do not isolate their share
of the measured jank. Cold startup, file/database access and returning after
reclaim remain plausible storage-sensitive cases. An identical-image/data
A/B on faster storage is needed to quantify the card's contribution.
