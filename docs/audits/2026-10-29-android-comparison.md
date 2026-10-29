# Android app comparison and connection recovery, 2026-10-29

The device connection was recovered and FOSS Browser tested alongside
TikTok. Normal browser scrolling is smooth. TikTok still has app-side jank;
this investigation does not declare it fixed.

## Deployed change and connection measurements

The Hackberry remained on kernel 6.12.85-1-rpi throughout. Its 2.4 GHz
connection had active TCP round-trip estimates of 5–9 seconds, repeated
retransmissions, and transfers progressing only a few KiB/s. Earlier kernel
logs also contained external authentication failures. Host LAN gateway
pings were approximately 4 ms.

NetworkManager reported a stronger 5 GHz access point on the same home
network. Activating that AP restored responsive SSH. Five subsequent pings
had no loss and min/mean/max 5.16/20.01/46.70 ms. Downloading and hashing
3,526,260 bytes over the LAN took 0.439 seconds, approximately 8.0 MiB/s.
The APK hash matched the existing local FOSS Browser artifact.

The existing home connection profile now has wireless band `a`, so it uses
5 GHz on reconnection. Other network profiles were not changed. Clearing
that profile's `802-11-wireless.band` restriction restores automatic band
selection. The root cause of the poor 2.4 GHz link was not established;
changing AP/band removed the observed connection problem.

No Shell or Deckard binary was replaced in this follow-up. CPU governor
remained schedutil. Load workers exited after each trial. Temporary Android
Perfetto tracing was disabled again afterward.

## Rendering patches verified

The installed composer exactly matches the local Android build containing
Deckard's task-layer naming, YV12-to-linear-BGRA conversion and retained
EGL image/texture cache:

- Composer SHA-256: `1d103ccc492df8756f06918d3d30b39d9b5275298fa00a3da152aa413f3d3e1b`.
- SurfaceFlinger SHA-256: `fc5489f2b6e0f29cc77bb98c82182b8665dd0b1be37b208094413a25e478b0a0`.
- GPU: V3D 7.1.10.2, OpenGL ES 3.1, Mesa 26.2.5.

Composer logs showed the same layer set retaining a six-entry buffer map
during TikTok playback. During the two normal TikTok trials, the composer
used 3.03% and 2.81% of one CPU core, respectively. SurfaceFlinger used
5.44% and 5.30%. These readings support the cached video path working;
they do not prove the absence of every possible rendering inefficiency.

## Comparison protocol and results

FOSS Browser 159 rendered a fixed local HTML document with 200 equal-height
rows, no JavaScript and no remote assets. Its prompts were dismissed and
the actual page visually confirmed before accepting measurements. A trial
performed while its first-run dialog was present was excluded.

Each accepted trial used five upward drags from (360,530) to (360,190),
120 touch steps, separated by 1.5 seconds. Android gfxinfo was reset per
trial. A private tracefs instance collected CRTC 0 presentation events,
with markers limiting interval statistics to the drags. Screenshots before
and after confirmed browser scrolling and TikTok feed changes. Load trials
used four CPU workers; observed busy percentages were 99.21–100.00%.
These gestures differ from the earlier 24-step kernel comparison; do not
use these as a causal before/after estimate of Wi-Fi or kernel effects.

| Trial | Android janky / rendered frames | CPU frame p99 | GPU frame p99 | Longest host presentation interval during drags |
|---|---:|---:|---:|---:|
| FOSS normal 1 | 0 / 215 | 8 ms | 5 ms | 16.672 ms |
| FOSS normal 2 | 0 / 210 | 9 ms | 5 ms | 16.669 ms |
| TikTok normal 1 | 28 / 272 (10.29%) | 77 ms | 6 ms | 16.687 ms |
| TikTok normal 2 | 19 / 259 (7.34%) | 57 ms | 7 ms | 16.697 ms |
| TikTok loaded | 26 / 267 (9.74%) | 69 ms | 6 ms | 16.683 ms |
| FOSS loaded 1 | 2 / 214 (0.93%) | 13 ms | 5 ms | **166.634 ms** |
| FOSS loaded repeat | 1 / 208 (0.48%) | 9 ms | 5 ms | 24.599 ms |

Normal pooled results: FOSS 0/425 janky frames; TikTok 47/531, 8.85%.
FOSS's 348 normal drag presentation intervals all stayed near 16.67 ms.
TikTok's normal presentation cadence also stayed near 16.67 ms, while its
app missed deadlines. Presentation cadence can continue through repeated
app content or independent video updates; it is not proof that every
app frame or scroll update was delivered.

The single 166.6 ms loaded browser presentation gap did not reproduce in a
second loaded trial with Shell scheduler events enabled. It remains an
unexplained outlier, not a fixed defect or a reason to discard that run.
The repeat reached 100% CPU busy and retained zero intervals above 25 ms.
Its filtered Shell scheduling trace contained 3,112 events: the longest
GUI busy span was 1.085 ms and the longest render-thread span 1.905 ms.
No hardware input-to-photon latency measurement was performed.

## TikTok scheduling trace

An additional 18-second Perfetto capture collected scheduling, application
view/gfx work, process state and FrameTimeline. No trace error counters
were reported. TikTok gfxinfo in the traced trial measured 24/281 janky
frames (8.54%). The container process PID and kernel thread IDs differ;
the main thread was identified by its name and doFrame slices, not by
assuming its TID equals the container PID.

The longest doFrame slices lasted 39.46, 39.40 and 38.66 ms. Their view
measurement work occupied approximately 30 ms. The first two spent about
32.2 ms running on CPU and 6.3–6.9 ms runnable waiting for CPU. The traced
RenderThread's longest DrawFrames slice was 9.59 ms. This identifies
TikTok's main-thread view work as the dominant cost in these slow frames;
scheduling delay contributes too. FrameTimeline labels were Unknown Jank
and mostly Unspecified Present, so they were not used to claim a more
precise deadline classification.

TikTok already had speed-profile compiled primary APKs. FOSS was only
verify compiled yet scrolled smoothly. No speculative ART recompile or
priority change was applied.

## Reopen checks and remaining limits

Settings-to-TikTok switching completed, and a screenshot confirmed the
feed afterward. FOSS also resumed from Android dozing. A separate check
put Android fully Asleep while Marathon remained visible, then launched
TikTok: Android became Awake and a fresh screenshot showed the feed.
No further launch timeout appeared in these checks. These checks do not
establish the cause of the original earlier failed reopen.

The uclamp kernel remains selected, the backlight readback was on, and the
home Wi-Fi profile retained band `a` at the final check. Journal and kernel
logs were inspected; the Android crash buffer was empty. The original
reopen cause, the single loaded browser presentation gap and TikTok's
remaining app jank are unresolved.

Raw aggregate results and gfxinfo: [comparison data](2026-10-29-android-comparison).
The exact measurement script, static page, private presentation traces and
18 MiB Perfetto capture are retained on the build USB at
`artifacts/2026-10-29-android-comparison/`. Personal feed screenshots and
the full Android trace were not added to the public repository.
