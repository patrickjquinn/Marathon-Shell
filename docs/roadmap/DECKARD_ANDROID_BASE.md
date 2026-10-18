# Deckard: which Android base

Research note for the Deckard plan (sections 4, 13, 14 and 16). Checked 18 October 2026 against GitHub (via `gh api`), LineageOS Gerrit, AOSP gitiles, the Waydroid OTA server, Valve's GitLab and vendor docs. Dates are commit, merge or publish dates. Anything not found is marked "not found".

## Conclusion

Skip Android 13 and build on LineageOS 23.2 (Android 16 QPR2), using Waydroid's own `dev/lineage-23.2` branches. Drop the M3 rebase milestone. Use stock Waydroid lineage-20 images only for the M0 measurements, because they are the only official arm64 images that exist today.

- Android 13 no longer gets AOSP security fixes. The last bulletin that lists Android 13 is December 2025. LineageOS 20's security string has been frozen at 2026-02-01, and its official builds were retired on 2024-12-30.
- Waydroid upstream skipped 14 and 15 and is now working on 16. Since July 2026 its `dev/lineage-23.2` branches have carried most of what Deckard M1 asks for: a Wayland window per Android task, hidden system bars in per-app windows, gesture navigation driven by the host window, and keyboard placement per card. The catch is that no official images are built from this branch yet.
- The microG spoofing patch, signingInfo included, is in upstream lineage-21.0, 22.x, 23.1, 23.2 and 24.0. On every branch it only works on userdebug and eng builds.
- Finger-tracking predictive back on 15 and 16 does not need a `BackNavigationController` patch. SystemUI's WMShell computes the progress from real touch or trackpad MotionEvents. Synthesising an edge swipe as touch input is enough, but SystemUI's process has to stay.
- Mesa's Android build supports v3d and v3dv. raspberry-vanilla ships AOSP 15, 16 and 17 for the Pi 5 on exactly that stack.

## 1. Android 14/15/16 bases for Waydroid-style containers

### Waydroid official

| Item | Finding | Source |
|---|---|---|
| Official images | lineage-20.0 only. The newest is `lineage-20.0-20260927` (system and vendor, arm64). The OTA JSON has no other version. | [OTA VANILLA.json](https://ota.waydro.id/system/lineage/waydroid_arm64/VANILLA.json), [MAINLINE vendor](https://ota.waydro.id/vendor/waydroid_arm64/MAINLINE.json) (fetched 2026-10-18) |
| README | "The image is currently based on Android 13." | [waydroid README](https://github.com/waydroid/waydroid) |
| Repo branches | vendor, hardware and device repos have `lineage-17.1`, `lineage-18.1`, `lineage-20` and **`dev/lineage-23.2`**. There is **no lineage-21 or lineage-22 branch**. | [vendor](https://github.com/waydroid/android_vendor_waydroid/branches), [hardware](https://github.com/waydroid/android_hardware_waydroid/branches), [device](https://github.com/waydroid/android_device_waydroid_waydroid/branches) |
| `dev/lineage-23.2` start | Created 2026-07-06 from WayDroid-ATV work ("Add patches and manifests for LineageOS 23.2", SupeChicken666). Moved to stock LineageOS plus `base-patches-36` on 2026-07-12. | [vendor compare](https://github.com/waydroid/android_vendor_waydroid/compare/lineage-20...dev/lineage-23.2) |
| Multi-window on 23.2 | 2026-08-28 to 2026-09-04 (TheKit): one Wayland connection per streamed task, display@1.3 `postTaskBuffer` and `updateTaskList`, a task lifecycle tracked from WMS, cards that follow host visibility and focus, "hide the system bars in per-app host windows", "follow the host window mode into gesture navigation", "put the keyboard on the card it types into". The last commit is 2026-09-26. | [hardware compare](https://github.com/waydroid/android_hardware_waydroid/compare/lineage-20...dev/lineage-23.2), [vendor dev/lineage-23.2 log](https://github.com/waydroid/android_vendor_waydroid/commits/dev/lineage-23.2) |
| arm64 on 23.2 | The device tree keeps `waydroid_arm64` and `waydroid_arm64_only` products, with Mesa gallium `freedreno v3d vc4 etnaviv nouveau tegra panfrost lima` and Vulkan `broadcom freedreno panfrost`. Not found: any official arm64 build from this branch. | [waydroid_arm64/BoardConfig.mk](https://github.com/waydroid/android_device_waydroid_waydroid/blob/dev/lineage-23.2/waydroid_arm64/BoardConfig.mk) |
| Host tool | Ready for newer APIs: "Use aidl5 for service manager on API 35+" and "aidl6 … on API 36+" (2026-04-26). The latest release is 1.6.3 (2026-05-28). | [waydroid commits](https://github.com/waydroid/waydroid/commits/main), [releases](https://github.com/waydroid/waydroid/releases) |
| Tracking issue | "#2229 Update image OS to Android 16 / Lineage 23", opened 2026-02-17, still open. | [issue 2229](https://github.com/waydroid/waydroid/issues/2229) |
| Open A16 bugs | #2407 (2026-09-04): zygote aborts with an empty BOOTCLASSPATH, reproduced on a custom 23.2 build. #2433 (2026-09-25): Zygisk unusable on A16 images. | [2407](https://github.com/waydroid/waydroid/issues/2407), [2433](https://github.com/waydroid/waydroid/issues/2433) |

### Community builds (WayDroid-ATV / supechicken)

| Release | Base | arm64 | Multi-window | Source |
|---|---|---|---|---|
| 20260118, 20260125 | LineageOS 21.0 (A14) | no (x86_64 asset only) | no | [releases](https://github.com/supechicken/waydroid-builds/releases) |
| 20260224 | LineageOS 22.2 (A15) | no | no | same |
| 20260302 / 20260313 | LineageOS 23.2 (A16 QPR2) | **yes, one build** (`lineage-23.2-20260313-…-waydroid_arm64`, on SourceForge) | no | [release 20260302](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20260302), [SourceForge](https://sourceforge.net/projects/waydroid-atv/files/images) |
| 20260717 | LineageOS 23.2 | "ARM64 images are NOT available in this release" | no | [release 20260717](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20260717) |
| 20261017 | LineageOS 24.0 (A17 QPR0), Mesa 26.2.5, SPL 2026-10 | no | no | [release 20261017](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017) |

The README's feature table marks "Seamless mode (multi-window)" as supported only by official builds and the A13 build, not A14–A17 ([README](https://github.com/WayDroid-ATV/waydroid-builds)).

### Other container Android

| Project | Android base | Source |
|---|---|---|
| Valve Lepton v3.0.x | Two images built in CI: `image/` is **LineageOS 18.1 (Android 11)** and `image-14/` is **AOSP `android-14.0.0_r75`** (not Lineage), with a Valve fork of `android_hardware_waydroid` on branch `android-14` (last commit 2026-09-09). Lepton v3.0.0 was released 2026-09-11. Not found: which image Steam ships by default. | [image/update_repositories.sh](https://gitlab.steamos.cloud/frame-public/lepton/-/blob/main/image/.buildscripts/update_repositories.sh), [image-14/update_repositories.sh](https://gitlab.steamos.cloud/frame-public/lepton/-/blob/main/image-14/.buildscripts/update_repositories.sh), [.gitlab-ci.yml](https://gitlab.steamos.cloud/frame-public/lepton/-/blob/main/.gitlab-ci.yml) |
| Jolla AppSupport | **Android 13**: "AppSupport is updated to Android version 13 now on all supported devices" (Sailfish 5.0.0.76, posted 2026-03-11). Not found: any Android 14+ AppSupport. | [release notes 5.0.0.76](https://forum.sailfishos.org/t/release-notes-tampella-5-0-0-76/28285) |
| Anbox Cloud 1.30.2 | Containers: **Android 14 and 15** (amd64 and arm64). Android 16 only as a **virtualised** Cuttlefish image (`resolute:android16-cf`). Image builds dated 2026-09-15. | [component versions](https://canonical.com/anbox-cloud/docs/reference/component-versions/) |

Every open-source Linux container stack with multi-window support today is on Android 13 (Waydroid official, Jolla). Waydroid upstream's A16 multi-window work exists only as source.

## 2. Android 13 security status

| Item | Finding | Source |
|---|---|---|
| AOSP bulletins | The December 2025 bulletin still lists Android 13 among the updated AOSP versions. The January and February 2026 bulletins have no platform entries. **From March 2026 (published 2026-03-02) the bulletins list 14, 15 and 16 (later 17) and not 13.** | [2025-12-01](https://source.android.com/docs/security/bulletin/2025-12-01), [2026-03-01](https://source.android.com/docs/security/bulletin/2026/2026-03-01), [2026-10-01](https://source.android.com/docs/security/bulletin/2026/2026-10-01) |
| Press | Heise: Google stopped Android 13 security patches at the start of March 2026. | [heise](https://www.heise.de/en/news/Android-13-Google-has-discontinued-support-for-operating-system-11262704.html) |
| LineageOS 20 security string | The last bump was "Bump Security String to 2026-02-01" (Gerrit 472474, merged 2026-02-02). For comparison, lineage-21.0, 22.2 and 23.2 were each bumped to 2026-10-01 between 2026-10-06 and 2026-10-09. | [472474](https://review.lineageos.org/c/LineageOS/android_build/+/472474), [503852 (23.2)](https://review.lineageos.org/c/LineageOS/android_vendor_lineage/+/503852) |
| LineageOS 20 code | Selective cherry-picks still land, for example the PduParser security fixes merged 2026-10-06 (Gerrit 505911). | [505911](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/505911) |
| LineageOS 20 official builds | Retired in hudson on 2024-12-30 ("Retire 20.0"). 21.0 was retired 2025-10-04. Current official build targets are 22.2 (115), 23.2 (50) and 24.0 (176). | [hudson 18922cc](https://github.com/LineageOS/hudson/commit/18922cc1f1182731b959337bc6de834c05cfaee5), [c0e674a](https://github.com/LineageOS/hudson/commit/c0e674a31d), [lineage-build-targets](https://github.com/LineageOS/hudson/blob/main/lineage-build-targets) |
| Android 14 runway | Not found: an official end date. If Android 14 follows Android 13 (released Aug 2022, out of the bulletins in Mar 2026), it would drop out around early-to-mid 2027. This is my inference, not a published date. | — |

## 3. microG signature spoofing upstream

Each of these changes adds the spoofing to the framework, gated on `#ifdef ANDROID_DEBUGGABLE`, so it is active only on **userdebug and eng** builds and limited to `com.google.android.gms` and `com.android.vending` signed with the microG key:

| Branch | Base spoofing | signingInfo spoofing | Source |
|---|---|---|---|
| lineage-20.0 | 383574 (2024-02-25) | 411384 (2024-12-16) | [411384](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/411384) |
| lineage-21.0 | 383573 (2024-02-25) | 411374 (2024-12-16) | [411374](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/411374) |
| lineage-22.2 | 422137 (2025-03-27) | 422279 (2025-03-27) | [422279](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/422279) |
| lineage-23.1 | 460457 (2025-12-27), with signingInfo folded in (the separate 460487 was abandoned) | in 460457 | [460457](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/460457) |
| lineage-23.2 | 466707 (2026-01-14), with signingInfo included (`packageInfo.signingInfo = new SigningInfo(…)`) | in 466707 | [466707](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/466707) |
| lineage-24.0 | 491314 (2026-09-09), with signingInfo included | in 491314 | [491314](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/491314) |

lineage-23.2 also has "ServiceWatcher: Allow microG location provider to be installed in /data" (497886, 2026-08-21) ([497886](https://review.lineageos.org/c/LineageOS/android_frameworks_base/+/497886)). The plan's userdebug-only constraint (section 13) holds unchanged on 23.2, and the "post-2024-12-16 lineage-20.0" requirement is no longer needed.

## 4. Predictive back from an external input source

| Item | Finding | Source |
|---|---|---|
| Where progress is produced (15 and 16) | WMShell's `BackAnimationController.onBackMotion(touchX, touchY, keyAction, swipeEdge)` feeds `onMotionEvent` → `BackTouchTracker`. It calls `ActivityTaskManager.startBackNavigation` (system_server `BackNavigationController`) only to get `BackNavigationInfo`, then drives the progress itself. | [BackAnimationController.java @android-16.0.0_r1](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/libs/WindowManager/Shell/src/com/android/wm/shell/back/BackAnimationController.java) |
| Who calls it | SystemUI's `EdgeBackGestureHandler` calls `mBackAnimation.onBackMotion(...)` from MotionEvents: edge touch swipes and, since Android 15, **trackpad three-finger swipes** (`isTrackpadThreeFingerSwipe`). The trackpad path does not exist in android-14.0.0_r1. | [EdgeBackGestureHandler @16.0.0_r1](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/packages/SystemUI/src/com/android/systemui/navigationbar/gestural/EdgeBackGestureHandler.java), [@15.0.0_r1](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/packages/SystemUI/src/com/android/systemui/navigationbar/gestural/EdgeBackGestureHandler.java) |
| Cross-process API | `IBackAnimation.aidl` (16) exposes only `setBackToLauncherCallback`, `clearBackToLauncherCallback` and `customizeStatusBarAppearance`. There is no motion or progress entry point for another process. | [IBackAnimation.aidl @16.0.0_r1](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/libs/WindowManager/Shell/src/com/android/wm/shell/back/IBackAnimation.aidl) |
| `registerBackGestureDelegate` (16) | This shell hook performs a complete back (DOWN, `setTriggerBack(true)`, UP at 0,0). It carries no progress. | same BackAnimationController file |
| Synthesised touch is proven in the hwcomposer | Waydroid's hwcomposer already emits synthetic `ABS_MT_*` touch streams, for example the pinch emulation in [e6d5142](https://github.com/waydroid/android_hardware_waydroid/commit/e6d5142b133c931679930b04a210d5e17ad420a3) on `dev/lineage-23.2`. | — |
| Android 16 apps | For apps targeting API 36 on 16+, the predictive back animations are on by default, "`onBackPressed` is not called and `KEYCODE_BACK` is not dispatched anymore". | [behavior changes 16](https://developer.android.com/about/versions/16/behavior-changes-16) (page updated 2026-10-16) |

Verdict: no framework patch is needed. Marathon's back gesture (pull the bar left) can be replayed to Android as an edge swipe, or as a three-finger swipe on a virtual touchpad, through the hwcomposer's input pipe, and SystemUI then produces real BackEvent progress. Two corrections to the plan follow. Section 4 says delivery runs through `BackNavigationController`, so a framework patch is required; that is wrong. And SystemUI's process cannot be stripped (section 5, "Stripped from the image"), because WMShell lives in it, even with its chrome hidden. Patching is only needed to drive progress from a non-input channel such as a protocol event, and that patch would go in SystemUI/WMShell, not system_server. Not verified on a device: whether `EdgeBackGestureHandler` stays registered when the nav bar is hidden in Waydroid's per-app window mode. Waydroid's "follow the host window mode into gesture navigation" commit suggests they rely on it.

## 5. Mesa v3d/v3dv on Android (Pi 5 / CM5)

| Item | Finding | Source |
|---|---|---|
| Mesa Android build | `android/Android.mk` maps `MESA_VK_LIB_SUFFIX_broadcom := broadcom` (v3dv) and accepts gallium `v3d` and `vc4` through `BOARD_MESA3D_GALLIUM_DRIVERS`. | [mesa android/Android.mk (main)](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/android/Android.mk), [docs/android.rst](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/docs/android.rst) |
| Proven on Pi 5 | raspberry-vanilla's `android_device_brcm_rpi5` ships `com.android.hardware.egl.mesa`, `minigbm_gbm_mesa` and `com.android.hardware.vulkan.broadcom` on android-15.0, 16.0 and 17.0. Its Mesa fork tracks 26.2.5 (2026-10-14). | [rpi5 device.mk (16.0)](https://github.com/raspberry-vanilla/android_device_brcm_rpi5/blob/android-16.0/device.mk), [android_external_mesa3d-rpi](https://github.com/raspberry-vanilla/android_external_mesa3d-rpi) |
| Waydroid image | The arm64 product builds gallium `v3d vc4` and Vulkan `broadcom` (lineage-20 and dev/lineage-23.2). | [lineage-20 BoardConfig](https://github.com/waydroid/android_device_waydroid_waydroid/blob/lineage-20/waydroid_arm64/BoardConfig.mk) |
| Waydroid host gap | `getVulkanDriver` maps `vc4 → broadcom` but has **no `v3d` entry**. On a Pi 4 or Pi 5, where the render node is v3d, Waydroid picks no Vulkan driver. That is an inference from the code; I did not test it. | [tools/helpers/gpu.py](https://github.com/waydroid/waydroid/blob/main/tools/helpers/gpu.py) |
| Waydroid on Pi 5 reports | #2047 (2025-09-09, open): fails on Pi OS Trixie. The reported workaround (2025-11-05) is a 4K-page kernel (`kernel=kernel8.img`) plus `psi=1`. #2230 (2026-02-18): runs, but multi-touch is single-point. A Pi forum thread (2025-09 to 12) reports Roblox at 60 fps and a 3DMark Sling Shot score of 2317 via a Pi-Apps Waydroid install, which is anecdotal evidence that GL works. Not found: any confirmed Vulkan/v3dv-on-Waydroid report. | [2047](https://github.com/waydroid/waydroid/issues/2047), [2230](https://github.com/waydroid/waydroid/issues/2230), [Pi forum t=392172](https://forums.raspberrypi.com/viewtopic.php?t=392172) |
| Page size | Raspberry Pi's `bcm2712_defconfig` sets `CONFIG_ARM64_16K_PAGES=y`. "Beginning with Android 15, AOSP supports devices … page size of 16 KB", so Android 13 cannot run on a 16K kernel. Alpine's `linux-rpi`, which Marathon's Pi 5 package depends on, builds aarch64 from `bcm2711_defconfig` (4K). Marathon's SDM845 and Librem 5 kernels are 4K. | [bcm2712_defconfig](https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm64/configs/bcm2712_defconfig), [Alpine linux-rpi APKBUILD](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/linux-rpi/APKBUILD), [page sizes](https://developer.android.com/guide/practices/page-sizes) |

## 6. Recommendation

| | Android 13 (LOS 20) | Android 14 (LOS 21 / AOSP 14) | Android 15 (LOS 22.2) | **Android 16 (LOS 23.2)** |
|---|---|---|---|---|
| AOSP security | ended (last bulletin Dec 2025) | live, probably ends ~2027 (inferred) | live | live |
| LineageOS official builds | retired 2024-12 | retired 2025-10 | built | built |
| Waydroid upstream branch | `lineage-20` (maintenance) | none | none | `dev/lineage-23.2` (active, multi-window) |
| Official Waydroid images | yes, arm64 | no | no | no |
| microG spoofing upstream | yes (userdebug) | yes | yes | yes |
| Progress-tracking back | no (no BackEvent progress API) | dev option only | yes, touch and trackpad | yes, default for API 36 apps |
| 16K-page kernels | no | no | yes | yes |
| Reference stacks | Jolla | Lepton, Anbox Cloud | Anbox Cloud | raspberry-vanilla (Pi 5) |

Recommendation: **go straight to LineageOS 23.2 / Android 16** and build it from Waydroid's `dev/lineage-23.2` manifests (`manifests-36`) for `waydroid_arm64_only`, userdebug.

- Effort. Waydroid's 23.2 branch already contains the per-task windows and host-driven gesture navigation that the plan budgets for M1 and M3. Forking it now avoids writing the hwcomposer work twice, so the M3 "rebase" milestone goes away. Android 14 and 15 have no Waydroid branch at all, so choosing either of them means more porting, not less.
- Risk. The branch is a dev branch with no official images, no arm64 build since March 2026 (and that one predates the multi-window work), and open boot bugs (#2407). M0 has to prove an arm64 23.2 build boots on the OnePlus 6. Keep the official lineage-20 image as the M0 measurement baseline and as a fallback until that build boots.
- Security. Starting on 13 means shipping a platform with no AOSP patches since early 2026 and a LineageOS security string frozen at 2026-02-01. Android 14 would buy roughly one year of patches; 16 buys the most.
- Later. Android 17 (LineageOS 24.0, official since September 2026, community Waydroid x86_64 build 2026-10-17) is the next step. Waydroid keeps its framework changes as exported `base-patches-36`, so moving from 16 to 17 should be a patch rebase rather than a fork rebase.

Plan edits this implies (not made here):
- Section 4, back row: remove the `BackNavigationController` patch claim.
- Section 5: keep SystemUI's process (WMShell lives in it).
- Section 13: lineage-23.2 userdebug.
- Section 14: `-Dplatform-sdk-version=36`, and add `v3d` / `broadcom` for the Pi 5.
- Section 16: fold M3 into M1 and M2.

## Other findings

- Valve's own CI references a project namespace `deckard/deckardos` (`registry.gitlab.steamos.cloud/deckard/deckardos/holo/android-arm64-package-builder-main`, in Lepton's [.gitlab-ci.yml](https://gitlab.steamos.cloud/frame-public/lepton/-/blob/main/.gitlab-ci.yml)). This matters for the naming question in section 17.
- Waydroid's own Mesa is still pinned to the `lineage-18.1` branch of `WayDroid-ATV/android_external_mesa3d` even in `manifests-36` ([02-waydroid.xml](https://github.com/waydroid/android_vendor_waydroid/blob/dev/lineage-23.2/manifest_scripts/manifests-36/02-waydroid.xml)). Waydroid's fork has per-Mesa-version branches up to `lineage-18.1-mesa-25.3` ([branches](https://github.com/waydroid/android_external_mesa3d/branches)). The plan's host-packaged Mesa (section 14) still stands.
