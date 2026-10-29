# Uclamp kernel: initial performance and TikTok reopen failure

Follow-up: [device access recovered; browser/TikTok comparison](2026-10-29-android-comparison.md).

Measured on 2026-10-29 after the normal power-on verification, kernel
6.12.85-1-rpi, Shell r516 and Deckard r26. No experimental Android clamp
floor was applied. Android retained CPU weight 200 and BFQ weight 200 in
front, with an outer cgroup uclamp minimum of zero. Native app foreground
clamps are available on this kernel; that does not automatically boost
Android threads.

## Measurements

Five upward swipes per trial, 24 touch steps, 1500 ms between swipes. Three
warm trials followed by one trial under four CPU load workers. TikTok's
feed was visually confirmed before these trials. These are Android gfxinfo
statistics, separate from host presentation statistics.

| Trial | Before: stock kernel | After: uclamp kernel |
|---|---:|---:|
| Warm, pooled across three trials | 73 / 823 frames, 8.87% janky | 69 / 761 frames, 9.07% janky |
| Four CPU workers | 30 / 272 frames, 11.03% janky | 21 / 172 frames, 12.21% janky |
| Loaded app CPU frame p99 | 61 ms | 97 ms |

This does not demonstrate an improvement in TikTok from enabling uclamp
alone. Live feed content, caches and differing frame counts limit causal
comparisons. The load trial reached 99.51% CPU busy; its governor override
was restored to schedutil and its workers exited afterward.

The subsequent gate 4 host trace recorded a maximum presentation gap of
33.34 ms during Settings launch peeks, versus 66.66 ms in the saved stock
run. GUI stalls remained in all ten launch peeks (maximum 43.49 ms versus
55.31 ms). **This is not an end-to-end pass:** restoring TikTok afterward
failed. The gate reports successful trace collection without checking that
the restored app has a usable surface. Do not treat its PROCEED label as
successful app restoration or as proof of a kernel performance benefit.

Raw measurements: [performance](2026-10-29-uclamp/performance).
Baseline: [r516 summary](2026-10-29-zbus6/android-navigation/r516-summary.json).

## Reopen failure and rendering investigation

At 17:48:02 UTC Marathon reported no TikTok surface after 20 seconds.
Android still reported TikTok's SplashActivity as the top resumed activity;
its crash buffer was empty. A later check found Android's power manager
Asleep. Explicit Android WAKEUP plus a launcher intent changed it to Awake,
but the captured Marathon screen still showed the launch spinner. Recovery
has therefore not been verified.

The custom TikTok path was located in Deckard history:

- d4e33fc carries task TID names to child layers and converts unsupported
  YV12 video surfaces to linear BGRA on the EGL thread.
- c2dff05 retains EGL images/textures and avoids converting a held video
  frame again on the next composition. Its original measurement was
  1.8 ms per conversion for a 576x1024 video.
- The current local Android hardware/deckard source contains both changes.
  DeckardService also contains wakeUpDevice in frontOrLaunch. Neither
  source inspection proves that these exact libraries are running.
- FillDisplay applies a per-app orientation compatibility override. Android
  reported areBoundsLetterboxed=false during this investigation.

FOSS Browser was absent from the current installed package list. Its
existing APK is available locally at
/mnt/deckard-build/tmp/fdroid-apks/de.baumann.browser_159.apk (3.4 MiB).
No FOSS comparison has been performed or claimed.

## Access interruption and remaining verification

Kernel logs captured brcmf_cfg80211_external_auth failures at 17:48 and
repeatedly afterward. SSH transfers stalled and subsequent SSH connection
attempts timed out; device pings failed while the LAN gateway responded
in approximately 4 ms. These establish lost device connectivity, not its
cause or a causal link to the launch failure.

Once access returns:

1. Capture Android power/activity/window state, the host window registry,
   current kernel log and journal before restarting anything.
2. Verify installed SurfaceFlinger and composer binaries against the local
   image artifacts, including the YUV cache patch.
3. Reproduce TikTok home/resume and Settings/TikTok switching with a usable
   surface and screenshot required for success; compare FOSS Browser.
4. Compare scrolling on fixed local browser content and TikTok, with host
   presentation intervals, app gfxinfo, CPU/fault/I/O deltas and logs.
5. Fix the demonstrated failure, deploy it, and repeat those checks. Keep
   the uclamp kernel selected as the user requested.
