<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: LGPL-2.1-or-later
-->

# Pacific engine

Pacific's web engine is WPE WebKit 2.54.2 on the legacy libwpe + WPEBackend-fdo API. The view is `../webview`. For the alpha, `shipwright-pacific-engine` repackages [Atlantic](https://github.com/SpecSierra/atlantic-engine)'s Sailfish OS build 746.1 (atlantic-engine a91f8ec). The beta rebuilds the same recipe from source (see "Beta" below).

## Packages

`rpm/shipwright-pacific-engine.spec` builds the engine for one processor, chosen by `--define 'pacific_cpu ...'` (`tools/build/sdk/specs.conf` passes `PACIFIC_CPU` through):

- `pacific_cpu armv8.2` (the default): `shipwright-pacific-engine`, for the Jolla Phone and C2 and the Xperia 10 III and IV; `shipwright-pacific-engine-dictionaries` (noarch, used by both builds); and `shipwright-pacific-engine-devel`, which holds the headers and the pkg-config files in `/opt/pacific/lib/pkgconfig`.
- `pacific_cpu armv8.0`: `shipwright-pacific-engine-armv80`, the engine alone, for the Xperia 10 II (Snapdragon 665: ARMv8.0, no LSE atomics, RCpc, dot product or FP16), from the armv8.0 WebKit tarball (`PACIFIC_CPU=armv8.0 build/build.sh`).

Both engines hold the same files, so they conflict, and both provide `shipwright-pacific-engine-abi`, which Pacific and its web view require. Each refuses (`%pre`) to install on a processor without what it was compiled for, naming the missing feature. Zypper and PackageKit choose a provider of `-abi` without looking at the processor, so Reef installs the engine for the phone explicitly with Pacific: `tools/build/reef/cpu-builds.json` gives each engine's `requires_cpu` and names the two as `variants`, gen-catalogue puts both in the catalogue, and the client asks for the first build the phone runs in the same transaction as Pacific (`reef/client/backend`, `Catalogue::variant_picks` and `Plan::alongside`). With only the ARMv8.2 engine published, Pacific stays hidden on an ARMv8.0 phone.

The `rpm/prebuild.sh` hook runs `fetch-rpms.sh`, which takes Atlantic's RPMs from a local mirror (`PACIFIC_ENGINE_RPMS`) or Atlantic's repository. It accepts only files that match `SHA256SUMS`. The RPMs land in `target/pacific-engine/rpms`, which the native build keeps between runs.

```
tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec \
    shoal/pacific/webview/rpm/shipwright-pacific-webview.spec
# The armv8.0 engine, once its tarball is built, installed (build.sh install)
# and listed in SHA256SUMS:
PACIFIC_CPU=armv8.0 tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec
```

`fetch-rpms.sh` (and the spec) need only the tarball for the processor being built; `SHA256SUMS` has a note where the armv8.0 tarball's line goes.

Layout (everything private to `/opt/pacific`):

| Path | Contents |
|---|---|
| `/opt/pacific/lib` | libWPEWebKit-2.0, libwpe-1.0, libWPEBackend-fdo-1.0, libepoxy (with Atlantic's RTLD_DEFAULT fallback), woff2 |
| `/opt/pacific/lib/compat` | Libraries Sailfish OS 5.2 lacks: libgbm (Mesa), libjpeg.so.8, dav1d, libavif, brotli, enchant, hunspell, harfbuzz-icu, a gssapi stub, libatomic |
| `/opt/pacific/lib/shims` | Atlantic's LD_PRELOAD shims (MPL-2.0): libegl-stubs, libsyncskip, libsigill_skip |
| `/opt/pacific/libexec/wpe-webkit-2.0` | WPEWebProcess, WPENetworkProcess |
| `/opt/pacific/lib/wpe-webkit-2.0/injected-bundle` | libWPEInjectedBundle |
| `/opt/pacific/lib/enchant-2`, `/opt/pacific/share/enchant` | enchant 2.3.3 (LGPL-2.1-or-later) built from source in the spec, with its hunspell provider; `bin/enchant-lsmod-2` for diagnostics |
| `/opt/pacific/share/hunspell` | Spell-checking dictionaries (`shipwright-pacific-engine-dictionaries`) |
| `/opt/pacific/lib/libvoikko.so.1`, `lib/enchant-2/enchant_voikko.so` | libvoikko 4.3.2 (MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later), built in the spec, for Finnish |
| `/opt/pacific/share/voikko` | The Finnish Voikko morphology (VFST, format 5) and the voikko-fi 2.5 source it was built from (`-dictionaries`) |
| `/opt/pacific/lib/gstreamer-1.0` | The gst-droid camera device provider, for getUserMedia |
| `/opt/pacific/share` | pulse-client.conf, inspector.gresource, the engine's `build-config` (CMakeCache, feature flags) |
| `/usr/libexec/pacific/pacific-env`, `pacific-env.sh` | The runtime environment (below): the ELF program, and a shell shim over it |
| `/usr/libexec/pacific/pacific-egl-probe` | Prints EGL and GL facts as a Wayland client (built here from `probe/egl-probe.c`) |
| `/usr/libexec/pacific/device-check.sh` | The day-1 go/no-go check |
| `/etc/sailjail/permissions/PacificWebEngine.permission` | The engine's Sailjail permission |

**Differences from Atlantic's packages:**

- `License:` is filled in.
- Automatic requirements are on for system libraries; the bundled sonames are neither provided nor required.
- No `sfos-qcom-boost`, no systemd units, and no `%posttrans` enabling services.
- No Qt 5 plugin (`wpewebkit2-qt5`).
- No bubblewrap: WebKit's sandbox is off on libhybris.
- No compat libsoup: Sailfish OS 5.2 has libsoup 3.6, which the package requires.
- Spell checking is Pacific's own. Atlantic's Ubuntu-built enchant looks for providers in `/usr/lib/aarch64-linux-gnu/enchant-2` and installs its provider and dictionary there and in `/usr/share/hunspell`. Pacific instead:
  - builds enchant 2.3.3 (the version WebKit was linked against) for `/opt/pacific`, so its provider, data and dictionary directories are compiled into `/opt/pacific`;
  - uses the system's libhunspell 1.7.3;
  - ships its dictionaries in `/opt/pacific/share/hunspell`.
- Nothing collides with Atlantic's files, so both engines can be installed at once.

**No binary edit.** Our WebKit is built with `/opt/pacific` as its prefix, so its compiled-in helper and injected-bundle paths are already right (Atlantic's needed `/opt/wpe-sfos/` rewritten in place).

## Runtime environment (`pacific-env`)

`pacific-env` (`launcher/pacific-env.c`) sets the environment below and execs its arguments: `pacific-env <program> [args]`, or `pacific-env --print` for `export` lines. It is an ELF program because Sailjail starts only ELF binaries and leaves no shell in the sandbox; Pacific's own binary re-execs itself through it (`PACIFIC_ENV=1` marks the environment as applied). `pacific-env.sh` is a shim over `--print` for shell use.

`pacific-env.sh` is a cut-down port of Atlantic's `deploy/runtime-common.sh`. Use it either way:

- `. /usr/libexec/pacific/pacific-env.sh` in a launcher script;
- `pacific-env.sh <program> [args]` as a wrapper.

Any variable already set wins. The WebProcess and NetworkProcess inherit everything.

Before it execs the program, `pacific-env` also raises the open-files limit to the hard limit (Sailfish gives apps 1024 of 32768). Every gralloc buffer costs a WebProcess about three descriptors; at 1024 a long scroll with zero-copy tiles ran out, the next frame buffer could not be imported (libhybris: "failed to register buffer") and the page froze. `pacific-env.sh` (`--print`) cannot pass a limit on; a program started that way keeps its own.

| Variable | Value | Why |
|---|---|---|
| `LD_LIBRARY_PATH` | `/opt/pacific/lib:/opt/pacific/lib/compat` | The engine's private libraries. Required. |
| `LD_PRELOAD` | `shims/libegl-stubs.so` | libhybris EGL is 1.4. libepoxy looks up the EGL 1.5 sync and image functions and, when they are missing, installs `abort()` stubs, so the first `eglCreateSync` kills the WebProcess. The shim forwards them to the KHR extensions. It also stubs `eglCreatePlatformDisplay`, which only matters for a future WPEPlatform build. Set `PACIFIC_EGL_STUBS=0` if the device check shows EGL 1.5. |
| | `shims/libsyncskip.so` | Inert unless `ATLANTIC_SKIP_SWAP_FENCE=1`, which skips libhybris' CPU wait on the swap fence in the compositor threads. Atlantic turns it on for the Adreno 610 (YouTube composites in 37 ms instead of 74 ms); Pacific turns it on where /dev/kgsl-3d0 exists (Adreno: Xperia 10 II ~45→49 fps flinging) and leaves it 0 elsewhere until measured. |
| | `shims/libsigill_skip.so` | Only when Patchmanager's preload library is in `/etc/ld.so.preload`: its constructor executes a trap. |
| `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` | 1 | bubblewrap's user namespace drops the graphics/video/audio groups the Android HAL needs, and its mount namespace hides `/odm` and `/vendor` submounts, so pages are blank. Sailjail confines the whole app instead. |
| `WEBKIT_ENABLE_SECCOMP_FILTER` | 1 | Atlantic's patch: a seccomp filter without namespaces in every WebProcess and NetworkProcess (no mount, namespace, ptrace or keyring syscalls). |
| `WEBKIT_INJECTED_BUNDLE_PATH` | `/opt/pacific/lib/wpe-webkit-2.0/injected-bundle` | Belt and braces with the rewritten path. |
| `ENCHANT_CONFIG_DIR` | `~/.local/share/org.shipwright/pacific/enchant` | enchant's personal word list, writable under Sailjail. The web view links `hunspell/` inside it to the dictionary directory, so Pacific's dictionaries come before any system ones. |
| `PACIFIC_DICTIONARY_DIR` | `/opt/pacific/share/hunspell` | Where the view lists dictionaries and points enchant. |
| `VOIKKO_DICTIONARY_PATH` | `/opt/pacific/share/voikko` | The Finnish morphology. libvoikko also has this path compiled in. |
| `QSG_RHI_BACKEND` | opengl | The view binds EGLImages as GL textures. |
| `QSG_RENDER_LOOP` | threaded | As Atlantic. |
| `GST_PLUGIN_FEATURE_RANK` | `droidvdec:300,droidvenc:0,vp9dec:310,vp8dec:310,droidadec:0` | Hardware H.264/H.265. VP8/VP9 go to software because droidvdec also claims VP9 and its colour conversion breaks. Audio is decoded in software because droidadec fails on AAC. |
| `GST_PLUGIN_PATH` | `/opt/pacific/lib/gstreamer-1.0:...` | The camera device provider. |
| `WEBKIT_GST_ENABLE_HLS_SUPPORT` | 1 | HLS streams. |
| `WEBKIT_GST_DISABLE_GL_SINK` | 1 | The GStreamer GL sink stalls 1080p decode on hybris (Atlantic, measured). |
| `WEBKIT_GST_VIDEO_DECODING_LIMIT` | `1920x1080@60` | Sites pick streams the hardware decoder can take. |
| `WEBKIT_GST_QUEUE_HIGH_WATERMARK`, `..._RING_BUFFER_MAX_SIZE`, `..._URIDECODEBIN_BUFFER_SIZE`, `WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES` | 0.05, 16 MB, 8 MB, 64 MB | Faster stream start, deeper read-ahead. Atlantic patch flags. |
| `WEBKIT_GST_MEDIA_ROLE` | x-maemo | Sailfish's volume keys only step streams with this role. |
| `WEBKIT_VOLUME_LOCKED` | 1 | Pages cannot override the system volume. |
| `WEBKIT_GST_AUDIO_SYSTEM_CLOCK` | 1 | The pulse sink must not be the pipeline clock: it freezes when corked, and YouTube sound stopped after 0.25 s. |
| `PULSE_CLIENTCONFIG` | `/opt/pacific/share/pulse-client.conf` | PulseAudio over the plain socket. The shm transport jams after a stream starts. |
| `JSC_numberOf*Threads`, `JSC_numberOfGCMarkers`, `JSC_maxNumberOfWorklistThreads` | 2, 2, 2, 2, 4 | JIT and GC threads never starve the UI. |
| `WEBKIT_MEMORY_BASE_THRESHOLD_MB` | 4000 on 8 GB phones, 700 below | WebKit purges caches at fractions of this RSS (Atlantic's memory-pressure patch). `PACIFIC_MEMORY_TIER=low` forces 700. |
| `WEBKIT_PROCESS_PREWARM` | 1 on 8 GB | A spare WebProcess. Atlantic measured the first cross-site tap at 327 ms without it and 107 ms with it, for about 100 MB. |
| `WEBKIT_MEMORY_POLL_INTERVAL_MS`, `WEBKIT_TEXTURE_POOL_CAP_MB`, `WEBKIT_URL_CACHE_DISK_CAPACITY_MB` | 3000, 64, 100 | Atlantic patch flags. |
| `PACIFIC_GPU_MODE` | `mali` when `/dev/mali0` exists; otherwise `default`; `cpu` by hand | Mali mode is Atlantic's "gpu-mali", measured on the Jolla Phone (55 fps against 45 for CPU painting). It sets these: |
| | | `WEBKIT_RASTER_ON_COMPOSITOR_THREAD=1`, `WEBKIT_SKIA_GPU_PAINTING_THREADS=1`: GPU painting on the compositor thread. |
| | | `WEBKIT_TILE_GPU_READBACK_SYNC=1`: without it, whole tiles intermittently go black (cause still open). |
| | | `WEBKIT_LOWRES_TILE_SCALE=1.0`: low-res tiles cost more than they save under GPU paint. |
| | | `WEBKIT_COMPOSITOR_GL_FINISH=1`: the frame reaches Qt with no fence, so without it Qt drew half-finished frames. |
| | | `cpu` sets `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1`. |
| Scrolling and painting | `WEBKIT_LOWRES_*`, `WEBKIT_CHECKERBOARD_*`, `WEBKIT_COVER_AREA_MULTIPLIER`, `WEBKIT_TILE_UPLOAD_*`, `WEBKIT_FORCE_ASYNC_SCROLL`, `WEBKIT_INDEPENDENT_SCROLL`, `WEBKIT_NO_FAKE_MOUSE_MOVE`, `WEBKIT_TOUCH_ACK_TIMEOUT_MS`, `WEBKIT_PARSER_TIME_LIMIT_MS`, `WEBKIT_LOADING_TIMER_ALIGNMENT_MS`, `WEBKIT_SCROLLBAR_*`, `WEBKIT_LAYERS_TILE_SIZE`, `WEBKIT_SKIP_ROOT_CUSTOMPROP_REPAINT`, `WEBKIT_COMPOSITE_SKIP_LOCKED_LAYERS` | Atlantic's defaults after device measurement. Each is described where Atlantic exports it in `deploy/runtime-common.sh`. These are patch-stack flags with no upstream meaning. |

Left off, measured on the Jolla Phone (12 October 2026): `WEBKIT_DIRECTIONAL_TILE_COVERAGE` (eight flicks over the flags list: 67 composites a second and no tile waits either way, half again as many tile paints with it), `WEBKIT_DROP_TILES_WHEN_HIDDEN` (a background tab's graphics memory was the same with it), `WEBKIT_FLING_THROTTLE_MS` (Atlantic measured it neutral to worse once scrolling no longer waits for the main thread, as with `WEBKIT_INDEPENDENT_SCROLL`), `WEBKIT_TILE_BUFFER_SKIP_ZERO` (zero-copy tiles, patch 0006, do not take that path).

The view's own switches:

- `PACIFIC_FRAME_ACK`: `stock`, `sample` or `eager` frame acknowledgement.
- `PACIFIC_SCALE_MODE=zoom`.
- `PACIFIC_STRICT_HISTORY_NAV=0`.
- `PACIFIC_DISABLE_CLIPBOARD_BRIDGE=1`.
- `PACIFIC_DEBUG=1`.

## Sailjail

`sailjail/PacificWebEngine.permission` is installed to `/etc/sailjail/permissions/`. Apps add `PacificWebEngine` to their `[X-Sailjail] Permissions=`. The permission grants:

- `/opt/pacific` and `/usr/libexec/pacific`;
- the GPU and libhybris nodes: `/dev/mali0`, `/dev/dma_heap`, `/dev/dri`, `/dev/ion`, `/dev/kgsl-3d0`, the binder nodes, `/dev/__properties__`, `/odm`, `/vendor/firmware_mnt`, droid-hybris;
- `/run/display`.

Network, sound, camera, microphone, location, Downloads and Pictures come from the standard permissions. `../webview/README.md` lists what the browser's `.desktop` file needs. Whether a Sailjailed WebProcess keeps the GPU is a day-1 check.

## Spell-checking dictionaries

The hunspell twelve come from [wooorm/dictionaries](https://github.com/wooorm/dictionaries) at commit 8cfea406, which normalises the upstream (mostly LibreOffice) Hunspell dictionaries to UTF-8. `SOURCES` pins each file by SHA-256. All may be redistributed, and each dictionary's licence text is installed in `/usr/share/licenses/shipwright-pacific-engine-dictionaries/`.

| Dictionary | Licence (as declared upstream) |
|---|---|
| en_US, en_GB | MIT AND BSD (SCOWL) |
| de_DE | GPL-2.0 OR GPL-3.0 |
| fr_FR | MPL-2.0 |
| es_ES | GPL-3.0 OR LGPL-3.0 OR MPL-1.1 |
| it_IT | GPL-3.0 |
| sv_SE | LGPL-3.0 |
| nl_NL | BSD-3-Clause OR CC-BY-3.0 |
| pl_PL | GPL-3.0 OR LGPL-3.0 OR MPL-2.0 |
| pt_BR | LGPL-3.0 OR MPL-2.0 |
| pt_PT | GPL-2.0 OR LGPL-2.1 OR MPL-1.1 |
| ga_IE | GPL-2.0 |
| fi_FI (Voikko) | GPL-2.0-or-later |

The dictionaries are data files read at run time. The hunspell GPL ones are their own source.

Finnish has no usable hunspell dictionary, so it comes from Voikko:
- the spec builds libvoikko 4.3.2 (VFST backend only, dictionary path `/opt/pacific/share/voikko` compiled in) and enchant's voikko provider;
- the data is the Voikko project's prebuilt Finnish morphology, `dict.zip`, format 5. Its `index.txt` records it as voikko-fi 2.5, a development snapshot built 2024-06-18;
- that data is GPL-2.0-or-later and compiled with foma, which Sailfish OS lacks, so the voikko-fi 2.5 source tarball ships next to it in `/opt/pacific/share/voikko/source`, and its COPYING is the installed licence;
- all three tarballs are pinned in `SOURCES`.

Enchant offers the dictionary as `fi`, and `fi_FI` falls back to it.

## Licences and corresponding source

The binaries are:

- WebKit: LGPL-2.0-or-later, LGPL-2.1-or-later and BSD-2-Clause.
- libwpe and WPEBackend-fdo: BSD-2-Clause.
- libepoxy, Mesa libgbm, dav1d and brotli: MIT or BSD.
- libavif: BSD-2-Clause.
- libjpeg-turbo: IJG, BSD-3-Clause and Zlib.
- enchant: LGPL-2.1-or-later.
- enchant 2.3.3: LGPL-2.1-or-later, built from its release tarball (in `SOURCES`).
- Atlantic's shims and environment: MPL-2.0.

Redistributing them means publishing the corresponding source next to the RPMs:

- the [WPE WebKit 2.54.2 tarball](https://wpewebkit.org/releases/wpewebkit-2.54.2.tar.xz);
- Atlantic's patch stack and build recipe at atlantic-engine a91f8ec (`patches/`, `versions.env`, `build-all.sh`, `shims/`, `deploy/`), and our patches (`build/patches/`, with the three of Atlantic's rebased onto 2.54.2 in `build/patches/atlantic/`);
- libwpe at 445a0b5 and WPEBackend-fdo at 8449232;
- the compat libraries' upstream releases (listed in Atlantic's `versions.env`).

Mirror these with the RPMs before anything leaves the team. Atlantic's packages carry `License: unknown`; the licence information here comes from the upstream projects.

## Our own build

`shipwright-pacific-engine` takes libwpe, WPEBackend-fdo, libepoxy and the compat libraries from Atlantic's 746.1 packages, and WebKit itself (libWPEWebKit, the WebProcess and NetworkProcess, the injected bundle, headers, inspector resources) from our own build in `build/`, a tarball pinned in `SHA256SUMS`.

**What differs from Atlantic's WebKit**

| | Atlantic 746.1 | Ours |
|---|---|---|
| Compiler | Ubuntu clang 18, against the 5.1 SDK sysroot | Fedora clang 22 and lld, against a Sailfish 5.2.0.15 sysroot (`make-sysroot.sh`) |
| CPU | armv8-a, tuned for Cortex-A73 (Xperia 10 II), no LSE | armv8.2-a with LSE atomics, RCpc, dot product and FP16, tuned for Cortex-A78 (the Jolla Phone's A78/A55). **Does not run on armv8.0 phones**: `PACIFIC_CPU=armv8.0` builds armv8-a with CRC and crypto, tuned for Cortex-A73, for `shipwright-pacific-engine-armv80` |
| Optimisation | -O3, ThinLTO | -O3, ThinLTO, profile-guided (`pgo-train.sh`: 14 sites with flings, then Speedometer 3.1, on the phone) |
| Linking | static libstdc++, binary path edit | Sailfish's libstdc++, libjpeg 62 and harfbuzz-icu; packed relative relocations; prefix `/opt/pacific`, so no path edit |
| Patches | Atlantic's stack (scripts/patches.sh) | the same 50 patches at atlantic-engine a91f8ec (three rebased onto 2.54.2, below), then ours in `build/patches/` |

No identical-code folding (`--icf=safe`): a ThinLTO build with it stalled Speedometer at the same step every run.

**Measured on the Jolla Phone (5.2.0.18)**, back to back on the same day:

| | Atlantic 746.1 | Ours |
|---|---|---|
| Speedometer 3.1 | 3.95 ± 0.15 | 4.79 ± 0.20 |
| Wikipedia, idle after flinging (web frames a second) | ~100 | 9 |
| Flinging Wikipedia and The Verge (frames shown a second) | ~60-80 | ~60-80 |

The first runs of a new engine stutter until the GPU driver's shader cache is warm; measure after a couple of runs.

**Our patches**

- `0001-compositor-offscreen-animations-at-10hz`: the compositor ran every running animation at full rate even when off the surface. Wikipedia's mobile pages carry an infinite "pulsating dot" in the header, so a page scrolled past it composited ~95 frames a second while idle. Animation-only frames with no animated layer on the surface now wait 100 ms. Damage tracking would be the general answer; patch 0025 compiles it in, off until measured.
- `0002-safe-area-insets-api`: `wpe_sfos_set_safe_area_insets()`. WebCore has the CSS safe-area constants on every port, but only Cocoa sets them. Pacific keeps pages below the notch, and gives pages with `viewport-fit=cover` the whole screen with the notch as `env(safe-area-inset-top)`, as Safari does.
- `0003-taps-never-press-the-scrollbar`: WPE synthesizes a mouse press for a tap, and EventHandler hit-tested it against the overlay scrollbar's track. A tap there jumped the page and lost the click. With Atlantic's `WEBKIT_SCROLLBAR_SCALE=3` the track was 63 CSS px wide, so The Verge's terms-of-use close button could not be tapped. Taps now skip the scrollbar, and the scale is back to 1.
- `0004-flings-never-throttled`: on the scrolling thread `LayerTreeHost` forwards a fling step only when that thread flagged a layer change, and on some pages the flag stays unset, so steps were shown only by composites for other reasons. With Wikipedia's header scrolled away those were 0001's 10 Hz ticks, and flings ran at 10 frames a second. The scrolling thread now notes every step: no throttling within 250 ms of one, and a step arriving while throttled is composited at once. Flinging Wikipedia: 29 to 71 frames a second while the page moves.
- `0005-compositor-thread-realtime`: the compositor thread puts every frame on screen but ran as an ordinary thread, competing with the CPU painting threads; it now has the scrolling thread's class, UserInteractive. Up to 2.54.0 that was `SCHED_RR` (WTF demoted on SIGXCPU); since 2.54.1 it is `SCHED_OTHER` with a utilization clamp floor of 1024 (full CPU speed, the big cores) and the lowest nice level RealtimeKit grants, demoted while no page is shown. `PACIFIC_COMPOSITOR_REALTIME=0` turns it off. Measured on 2.54.0, gain within noise apart from the worst gaps; not yet measured with 2.54.1's scheduling.
- `0006-zero-copy-cpu-tiles`: a whole tile painted on the CPU goes into a gralloc buffer (libhybris `EGL_HYBRIS_native_buffer2`, mapped cached) taken from a pool, and the compositor shows it through that buffer's EGLImage instead of uploading it with `glTexSubImage2D`. Buffers and EGLImages are made once and reused 50 ms after the last frame that showed them; a buffer per tile cost the main thread a fifth of its time and importing each one into the driver a third of the compositor's, which made a first, unpooled version slower than the upload. Partial updates are copied into the tile's buffer on the CPU. Images are made with `eglCreateImageKHR`: Mali crashes on images of native buffers made with EGL 1.5's `eglCreateImage`. Flinging OSNews: 74-77 frames a second with 2-7 pauses over 25 ms in ten flings, against 65-68 and 14-15 with the upload. The pool holds at most a sixth of the open-files limit in buffers, 384 at most; tiles past it take the upload path (without that bound, buffers in use grew to about 320 in a long scroll, a thousand descriptors, and the page froze at Sailfish's limit of 1024). `PACIFIC_ZERO_COPY_TILES=0` turns it off.
- `0007-frame-paced-scroll`: Atlantic's independent scroll ticked the scrolling thread on a free-running timer that drifted against the frames, so some frames composited without a new scroll position and the next moved twice as far. `ThreadedCompositor::frameComplete()`, which the embedder paces to the display, now ticks the scrolling tree; the timer only covers a pause in the frames. Acknowledgements jitter by a few ms, so each tick advances the animation by whole refresh periods (one, or as many as passed after a missed frame), kept within a period of the real time and never backwards; snapping to a fixed grid put two jittered ticks on one point. Frames composited without moving, flinging: OSNews 0-3% against 8% on the timer, The Verge 1-2% against 8-59%. `PACIFIC_FRAME_PACED_SCROLL=0` keeps the timer alone; `ATLANTIC_FRAME_TRACE=1` logs each composited frame's scroll position.
- `0008-recorded-css-filters`: a layer with a CSS filter was painted into a buffer and filtered there, on the main thread, whenever a tile with it was recorded; flinging The Verge, half the WebProcess main thread's time was Skia blurring drop shadows. Drop-shadow, Gaussian blur and the matrix, saturate and hue-rotate colour matrices in sRGB (CSS filter functions; SVG filters, linearRGB by default, keep the old path) are now recorded as a Skia image filter on a transparency layer (`FilterRenderingMode::GraphicsContext`, as Apple's ports record a CGStyle), and run when the tile is played back on the painting threads. Rendering matched the old path to within blur rounding. The Verge: 2.6 s of main-thread CPU in 7.8 s of flinging instead of 4.3 s, and 77 frames a second while moving with no pause over 25 ms, against 74 with 7. `PACIFIC_RECORDED_FILTERS=0` turns it off.
- `0009-touch-scroll-resampling`: a drag's moves reached the scrolling thread at the touchscreen's rate (110-125 Hz) against the panel's 90 Hz and each scrolled as it came, so at a steady finger a frame moved one move's distance, two or none; 28% of the frames composited mid-drag did not move. Once a drag's first move has scrolled on the scrolling thread, its later moves are queued and each display refresh (patch 0007) applies the finger's movement up to 16 ms before the frame, interpolated within a move and timed by the touch reports' own times (the UI process merges wheel events that wait for an acknowledgement, so they arrive in bursts). Anything else flushes the queue first, report by report. Frames that did not move while dragging: OSNews 0.9%, The Verge 4.7%. Flings travel about 5% further, as fewer moves reach the velocity estimate merged. `PACIFIC_SCROLL_RESAMPLE=0` turns it off; `PACIFIC_SCROLL_RESAMPLE_LATENCY_MS` sets the delay behind the frame.
- `0010-touch-slop`: WPE's gesture controller made a touch a scroll after 40 device px (a scroll line step), 16 dp on the Jolla Phone and twice Android's 8 dp: the page did not move for the first 40 px of a drag and then jumped by all of them. `PACIFIC_TOUCH_SLOP_PX` sets it; Pacific's web view sets 8 dp from the screen's density. Touch-down to the first frame that moves: 42-44 ms instead of 59-62 ms.
- `0011-single-scroll-clock`: patch 0007 ticks scroll animations from each frame's acknowledgement, but the display link kept ticking them as well, 0.3-6 ms later, so a frame showed whichever tick ran last and steps between frames varied by 0.58-0.78 of their size on the Qt path. While frames come, the display link's ticks are ignored; it only covers a pause in the frames. Step spread: The Verge 0.21, OSNews 0.16; on the direct path Wikipedia 0.29, with 4% of frames jumping instead of 17%.
- `0012-obscured-content-insets`: `wpe_sfos_set_obscured_content_insets()` tells the engine which edges the embedder's own controls cover while the page draws under them (Pacific's floating toolbar). WebCore's obscured content insets (Safari on the Mac) let the page scroll its end clear of them; with fixed layout the layout viewport now leaves them out too, so `position: fixed` elements at the bottom (cookie banners, sites' bottom navigation) sit above the toolbar instead of under it. Each change lays the page out again, so Pacific changes them once scrolling stops.
- `0013-bfcache-no-store`: HTTPS pages with `Cache-Control: no-store` (most news sites) go into the back/forward cache too, as in Chrome since 2025: restored only within three minutes and only if the HttpOnly cookies for their URL are unchanged, so a page from before a log-out never comes back. Back on The Verge shows the previous page at once instead of after a 2.5 s reload. `PACIFIC_BFCACHE_NO_STORE=0` restores WebKit's refusal.
- `0014-find-match-cache`: an upstream bug in `CachedMatchFinder`: counting a search kept the previous search's match list under the new search's key, so find in page highlighted the matches of the text before the last keystroke (every "n" of the first keystroke while typing "Norway"). Counting now drops the kept list.
- `0015-one-finger-gestures`: WPE's touch gesture controller followed each event's first listed point and took every finger's events as one finger's, so a pinch scrolled the page and a lifted finger could start a fling. It now follows the point each event is about; a second finger ends any scroll without a fling (`Phase::Cancelled`), and nothing is gestured until every finger is up. The page still gets every touch.
- `0016-even-drag-steps`: on top of 0009's touch resampling: the finger lifting waits in the queue behind the moves (no lurch of three steps into the fling); while frames come only a frame's tick advances animations and resamples drags, at the frame's time on the display grid (the independent timer had made double and zero steps); and the resampling wait adapts to how late touch reports arrive, plus one report interval (16-40 ms; `PACIFIC_SCROLL_RESAMPLE_ADAPTIVE=0` keeps it fixed). Steady drags: step spread OSNews 0.63 to 0.31, The Verge 0.78 to 0.42; 200 ms flings 0.42 to 0.20.
- `0017-touch-scroll-prediction`: a drag is drawn where the finger will be when the frame is shown, from its recent velocity (200 ms flicks: the page trailed the finger by 33-42 ms as it lifted, now 2-12 ms). `PACIFIC_SCROLL_PREDICT=0` turns it off.
- `0018-ios-fling-physics`: a finger landing on a coasting page stops it within a frame and is not a click; a fling launches at the finger's speed over its last 50 ms; a finger that rests before lifting does not fling. `PACIFIC_FLING_TRACE=1` logs each fling.
- `0019-fling-carry-and-catch`: a flick on a coasting page adds the page's speed (`PACIFIC_FLING_CARRY_SHARE`, 1), only when the flick is at least half that speed (`PACIFIC_FLING_CARRY_MIN`, 0.5) and the page still moves at 350 px/s (`PACIFIC_FLING_CARRY_FLOOR`, Chromium's fling boost); a caught page released with a few pixels of motion flew to the end of the page, and 0018's iOS curve hit the ceiling on the second flick. The UI process models the stacked speed, so a late catch is a catch. Ceiling 18000 px/s.
- `0020-no-suspended-process-reuse`: a new navigation is never sent to the process holding a suspended page (upstream reuses it for speed): in that process the load never started, so going The Verge, OSNews, The Verge in one tab left the address bar on the new address over the old page, with Stop no help (three navigations in ten). Back and forward still restore their suspended page in its own process. `PACIFIC_REUSE_SUSPENDED_PROCESS=1` restores upstream's reuse.
- `0021-drag-steps-without-animation`: 2.54.1's touch scrolling (below) starts a scroll animation, a step of no length, for every drag step, so that the scrolling thread keeps watching the display link; ours ticks without it (patches 0004, 0007, 0009). The animation took the place of a fling a finger had caught, and the flick's end dropped the speed 0019 carries. `PACIFIC_DRAG_STEP_ANIMATION=1` restores it.
- `0022-legacy-vblank-timer`: 2.54.1 gives the legacy API's view display 1, which sends the UI process's display link to the DRM vblank monitor first (we build with libdrm). The timer, at Atlantic's `WEBKIT_DISPLAY_REFRESH_RATE`, stays its clock, as on 2.54.0; `PACIFIC_DRM_VBLANK=1` tries DRM first. The display ID itself stays: wheel activity now asks the display link for full-speed updates, and patch 0011 keeps those ticks out of the way while frames come.
- `0023-background-beyond-the-page`: on a short page, and past the end of any page, what the document did not cover was white, under the floating toolbar too (a dark site's frosted toolbar looked light grey, and a white band showed as it slid away). WebKit keeps the page's extended background colour (`backgroundShouldExtendBeyondPage`, on by default) but only the Cocoa ports paint it. Two layers with that colour now sit against the document's top and bottom edges in the scrolled contents, moving with it on the scrolling thread and painting nothing the document covers, and the frame's clip keeps the bottom and right obscured insets past the document's end.
- `0024-dynamic-toolbar-viewport-units`: viewport units as Safari's with its dynamic toolbar. vh and lvh are the whole view, svh the view less the toolbar (the insets last set that were not zero), dvh the view less the insets in force; before, all were the view less the insets in force (817 of 882 CSS px on the Jolla Phone), so `height: 100vh` sections stopped at the toolbar. The layout viewport and `position: fixed` stay as patch 0012 has them.
- `0025-damage-tracking-legacy`: WTF defined `ENABLE_DAMAGE_TRACKING` only with WPEPlatform. It is now defined for the legacy API too; nothing under it needs WPEPlatform. Off by default (WebKit's WPE defaults for damage propagation and damage-limited compositing apply only with WPEPlatform); Atlantic's `WEBKIT_DAMAGE_COMPOSITING=1` turns it on. The WPEBackend's EGL window is one target for buffers that keep whatever frame they last held, so the damage record follows `EGL_EXT_buffer_age` (the last four frames' damage), and an unknown age repaints in full. Not yet built or measured; `device-check.sh` reports whether the phone has `EGL_EXT_buffer_age`. Turning WPEPlatform on instead would add libWPEPlatform and its dependencies (epoxy, GIO, xkbcommon; libinput, udev and GBM for its DRM backend and wayland for its Wayland one, each of which can be switched off) and its code paths, for nothing Pacific uses, and its legacy-API target would have the same buffer-age problem.
- `0026-composite-waits-for-scroll-tick`: a frame is composited after its own scroll tick (frameComplete runs the scrolling thread's tick, then the compositor waits up to 3 ms for it), not with the position of the frame before. `PACIFIC_SCROLL_TICK_WAIT=0` composites at once.
- `0027-device-pixel-scroll-positions`: the scrolling thread rounds scroll positions to device pixels instead of whole CSS pixels (2.5 device pixels on the Jolla Phone), so slow drags and the end of a fling no longer step. `PACIFIC_DEVICE_PIXEL_SCROLL=0` rounds to CSS pixels.
- `0028-pointer-listeners-do-not-block-touch-scroll`: pointer and mouse listeners (analytics and ad scripts add them) no longer make a touch drag wait for the page's main thread; only touch listeners can cancel a scroll. `PACIFIC_POINTER_EVENTS_BLOCK_SCROLL=1` restores the wait. Not yet measured on a page that has them.
- `0029-resting-drag-holds-its-place`: a finger that stops holds the page where it is shown; 0017's prediction eased back toward the reports, moving the page 4-7 CSS px against the finger each time a drag stopped (10-15 times in a run of steady drags on OSNews, now none). `PACIFIC_SCROLL_PREDICT_EASE_BACK=1` restores it.
- `0030-scrolling-touchmoves-do-not-wait`: once a drag is past 12 CSS px and a touchmove went unhandled, the later touchmoves no longer wait for the page, as in Chrome and Safari. `PACIFIC_TOUCHMOVE_ALWAYS_WAITS=1` restores the wait. Not yet measured on a page with touch listeners that can cancel.
- `0031-drag-steps-skip-the-flush-lock`: each drag step asked the scrolling tree whether a scroll was in progress under the finger, a hit test under the lock the main thread holds through its whole layer flush, tile painting included; a 90 ms repaint on OSNews froze a steady drag for 90 ms. The question is asked only of an event that would go to the main thread. Steady drags on OSNews: worst frame on screen 83-110 ms before 0026-0031, 14-25 ms after.
- `0032-caught-fling-drags-at-once`: the drag that follows a catch (0018) is recognised in the UI process from touch-down, as Chromium treats touch listeners as passive during a fling (the page still gets the touches but cannot cancel the scroll), and begins at a quarter of the slop. The caught page stood still for 37-39 ms under a moving finger and then jumped 16 CSS px; it now follows within about 25 ms. `PACIFIC_CATCH_WAITS_FOR_PAGE=1`, `PACIFIC_CATCH_SLOP_PX`.
- `0033-drags-start-at-their-pace`: a drag starts from where the finger crossed the slop (Android's slop subtraction), not with the slop's distance in one frame, and with its first move that has a length: the scrolling tree latches a gesture only to a Began that scrolls, and an unlatched drag's lift flung at nothing (a quarter of quick re-flicks while this was built; none in 54 since). The moves after the first are resampled on a clock that starts at it and speeds up to real time, so the frames after the first step are not still. `PACIFIC_TOUCH_SLOP_SUBTRACT=0`, `PACIFIC_SCROLL_START_RAMP`.
- `0034-webp-scaled-decode-config-lifetime`: a memory-safety fix to Atlantic's `webkit-image-subsampling`. Its scaled WebP decode declared the `WebPDecoderConfig` inside a block, and libwebp's incremental decoder kept pointers into it, so `WebPIUpdate()` read a stack frame that had ended while decoding any page's large WebP image. The config now outlives the decoder.
- `0035-tiles-ahead-of-the-fling`: while a layer's visible rect moves faster than about half a screen a second, its cover reaches 200 ms of travel ahead (half a screen to four), a quarter of a screen behind and nothing to the sides, and a pass creates every tile the page will cross in about two rendering updates rather than one ring around the centre. One ring per update kept up with about 5300 CSS px/s. At rest WebKit's cover is unchanged. `PACIFIC_TILE_VELOCITY_COVER=0`.
- `0036-shape-with-the-script`: WebKit maps ICU scripts to HarfBuzz's itself (`HarfBuzzICUScript.h`, `hb_script_from_string()` on the ISO 15924 code) and no longer links libharfbuzz-icu, which Sailfish OS lacks. Atlantic's stand-in for it returned `HB_SCRIPT_UNKNOWN` for every script, so Arabic was drawn without joining and RTL locales had no default direction. The engine RPM no longer ships the stand-in.
- `0037-visible-tiles-first`: a layer's dirty tiles are painted on screen first (the visible rect plus 50 ms of travel), then ahead of the scroll, then the rest. Only the tiles on screen hold back their rendering update's composite; one painted off screen asks for a composite of its own when it is done. Flinging fast down OSNews with 0035, frames while coasting with more than 5% of the screen unpainted went from 6-7% to 1-2%, and rendering updates from 26-32 to 41-43 a second.
- `0038-frame-threads-preempt`: UserInteractive threads (scrolling, compositing, event dispatch) get a CPU sooner, and painting gives way. Upstream raises them through rtkit, which Sailfish OS lacks (and its user session's `RLIMIT_NICE` is 1), so they ran as ordinary threads, and on the Jolla Phone's Linux 6.12 (EEVDF) the scrolling thread often waited 3-5 ms behind a painting thread: 0026's composite went without the frame's scroll tick, and a fling showed a still frame, then a double step. Without a privilege, they now ask `sched_setattr()` for a 0.5 ms slice (to preempt a thread within its 2.8 ms slice), and painting threads run at nice 5 (a thread that ran a moment ago repays its debt to them faster, and becomes eligible to preempt). Flicking GitHub's awesome list (12 runs of 10 flings each way, the same build with both undone by hand): coasting frames standing still between moving ones went from 8 of 4691 to 1 of 4520; frames missed on screen were unchanged (11 and 12).
- `0039-scene-layers-lock-order`: a page froze for good and took no touches when a layer gained or lost a backdrop filter while it scrolled. The main thread attaches the backdrop layer under its own layer's lock and then takes the scene's `m_layersLock`; the scrolling thread's `flushPendingState()` took `m_layersLock` and then each layer's lock (holding the scrolling tree's lock, so the EventDispatcher waited too). The layers are now copied under `m_layersLock` and locked after it is released. Upstream main has the same code. Seen on a GitHub repository page.

**Atlantic's patches on 2.54.2** (`build/patches/atlantic/<name>` replaces Atlantic's patch of that name; an empty file would skip it): `webkit-portability-wtf-pal` (2.54.1 renamed `wtf/linux/RealTimeThreads.h` to `HighPriorityThreads.h`; the same includes go into the new name), `webkit-gst-media` (2.54.1 casts the blob ring-buffer size to `guint64`, the line its hunk replaces) and `webkit-wpe-dark-mode-runtime` (2.54.1 calls `windowScreenDidChange(1)` where its observer goes in, so it applied with fuzz). The other 47 and all of ours apply as they are, some at an offset; `build.sh` applies with no fuzz, so a moved context fails instead.

**Touch scrolling since 2.54.1.** Upstream's asynchronous touch scrolling for GTK and WPE (bug 318938, 319347@main, `ENABLE(COORDINATED_TOUCH_EVENTS)`) is in 2.54.1. Touch events go to the WebProcess's EventDispatcher thread, which answers at once when the touch point has no listener (from the layers' event regions), answers and then dispatches to the main thread for passive ones, and waits for the main thread only for listeners that can cancel. The UI process merges touch moves queued behind the one in flight and still reports every event back in order, so the gesture controller, Atlantic's `WEBKIT_TOUCH_ACK_TIMEOUT_MS` (one reply per event) and our patches see each touch report with its own time. Drags remain wheel events from the UI process's gesture controller, and everything our patches do happens after that: 0010's slop and 0015's finger tracking in the controller, 0018's catch at touch-down, 0009, 0016 and 0017's resampling and prediction on the scrolling thread, 0018 and 0019's flings. The replies come sooner where a page has no touch listener; 0016's adaptive delay follows. Its one part that did not fit, a scroll animation per drag step, is left out by 0021. Backported to 2.54.0 on 12 October 2026 it gained nothing on The Verge, which listens for touches (a drag 1.5 s into its load first scrolled 88-106 ms after the slop, as with the ack timeout alone), and the animation per step took OSNews's worst frame gap from 70 to 600 ms. 2.54.2 is to be measured on the phones the same way.

libhybris (`hybris/`, not a WebKit patch): the Wayland EGL platform rebuilt from the Jolla Phone's libhybris source with cancelled buffers fixed. `cancelBuffer()` left a buffer queued and the next `eglSwapBuffers()` aborted the WebProcess (`WaylandNativeWindow::finishSwap: wnb->busy == 1`). `pacific-env` uses it only in place of the exact system build it was made from; `PACIFIC_HYBRIS_PLATFORM=0` keeps the system's.

Painting (`PACIFIC_GPU_MODE`, pacific-env): on Mali, tiles are painted on the CPU by four threads in 512 px tiles and the GPU only composites. GPU painting ran on the compositor thread, where a new tile, a shader compile or a GPU allocation delayed the frame. Flinging OSNews on the Jolla Phone (frames a second while the page moves, worst gap): GPU painting 61 and 75 ms, CPU painting 70 and 31 ms; Wikipedia 73 against 80. It costs about half a core more while the page moves. `mali-gpu` paints on the GPU as before. Pausing the page's JavaScript during flings was measured too and changed nothing.

**Building it** (one heavy job at a time; the container takes up to 13 GB):

```
w=~/.cache/shipwright/webkit-build
shoal/pacific/engine/build/make-sysroot.sh $w          # Sailfish sysroot, woff2, bundled headers
shoal/pacific/engine/build/build.sh $w source          # WebKit 2.54.2 + Atlantic's patches + ours
shoal/pacific/engine/build/build.sh $w generate        # PGO-instrumented engine
#   on the phone: install it, run pgo-train.sh (see its header), copy the
#   .profraw files to $w/pgo/raw and merge the readable ones to $w/pgo/pacific.profdata
shoal/pacific/engine/build/build.sh $w use             # the release engine
shoal/pacific/engine/build/build.sh $w tarball         # stripped, for the spec; update SHA256SUMS
shoal/pacific/engine/build/build.sh $w install         # into the native build containers
```

For the Xperia 10 II, the same steps with `PACIFIC_CPU=armv8.0` in a workdir of its own (a profile of its own comes from `pgo-train.sh` on that phone; `lto` builds without one); its tarball is `pacific-webkit-2.54.2-aarch64-armv8.0.tar.xz`.

WebKit SIGKILLs its helper processes when the UI process exits, so they never write their profiles at exit. Training preloads a small library that calls the profile runtime's (hidden) write function every 5 s; profiles written while counters change can be torn, so merge only the files `llvm-profdata` reads cleanly.

**A profile from an older WebKit** (2.54.0's, until the phones train 2.54.2): `pacific-toolchain.cmake` already passes `-Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled`, so clang drops, with no more than a warning, the profile of each function whose code changed and uses the rest. One more thing: clang names a file's static functions in the profile by the source path, `../src/wpewebkit-2.54.0/Source/...` in 2.54.0's (in the Xperia 10 II's profile they are a tenth of the functions that ran and 7% of the counts). Run the `source` step and the builds with `PACIFIC_SRC_DIR=wpewebkit-2.54.0` so 2.54.2's tree has the same path; a profile trained on 2.54.2 goes with the default name again. The Jolla Phone's 2.54.0 profile was lost with its workdir (17 October); only the Xperia 10 II's (`webkit-build-armv80/pgo`) is left, so the armv8.2 engine needs a `generate` and a training run, or `lto` for now.

**Disk**: the armv8.2 workdir was 7.7 GB with the source, sysroot, ccache and one build tree (`build-use`). `generate` and `use` each keep a build tree of their own, so a full PGO round wants about 11-12 GB free (delete `build-generate` once the profile is merged); the patched source tree alone is about 0.55 GB.

### The next series: WPEPlatform

The legacy libwpe + WPEBackend-fdo API this engine is built on is deprecated from 2.54 ("light maintenance mode": still built by default and maintained while applications move, no removal date). On WebKit's main branch (2.55, October 2026) `ENABLE_WPE_PLATFORM` is gone, so libWPEPlatform is always built, TextureMapper is off by default and due to go, and `ENABLE_WPE_LEGACY_API` is still on. 2.56 (about March 2027, six months after 2.54) is the first series that may need the move. What it takes, in order:

1. **Buffers on libhybris.** WPEPlatform hands the embedder each frame as a DMA-BUF (`WPEBufferDMABuf`), an `AHardwareBuffer` in `OS(ANDROID)` builds only, or shared memory. The phones' GPUs are Android's, through libhybris: no DMA-BUF export from their EGL, so frames would come as shared memory (a CPU copy per frame, what the legacy path avoids). The way through is an `AHardwareBuffer` path for Linux on libhybris (gralloc buffers, imported with `EGL_ANDROID_image_native_buffer` as `webview/` does today with WPEBackend-fdo's EGLImages): a WebKit patch, small if upstream's `OS(ANDROID)` code takes a build switch instead of the OS. Ask upstream (Igalia) first; this is the blocker.
2. **A platform module of our own.** WPEPlatform's embedding is subclasses of `WPEDisplay`, `WPEToplevel` and `WPEView`, in the app or as a module WebKit loads at run time (`wpe-platform-gtk` is the example). `webview/`'s `viewbackend.cpp` (input, frames, the direct subsurface) becomes that module; the QML API stays.
3. **What the patches become.** Ours that touch `UIProcess/API/libwpe` (0010 slop, 0015 finger tracking, 0018 fling physics, 0019 catch) move to WPEPlatform's gesture code (`WPE_GESTURE_DRAG`; it has no pinch or swipe, which stay ours in `webview/`). The rest are WebCore and the compositor and carry over. Atlantic's patches that only serve the legacy view drop out.
4. **Damage tracking comes for free** (WPEPlatform defines it) once buffer age is honoured as 0025 does.

Until then each 2.54 point release is a rebase like 2.54.0 to 2.54.2 (patches/atlantic for Atlantic's that move, `-F0` so none lands in the wrong place).

## Day 1 on the phone

On the Jolla Phone (it runs Sailfish OS 5.2.0.18) with developer mode, from this workstation. The commands below build for `native.sh`'s default target, 5.2.0.15, into `RPMS/5.2.0.15/`; `native.sh --release 5.2.0.18` builds for the phone's own release into `RPMS/5.2.0.18/`.

1. **Build and copy.**

   ```
   tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec \
       shoal/pacific/webview/rpm/shipwright-pacific-webview.spec
   scp RPMS/5.2.0.15/shipwright-pacific-engine-2.54.2-*.aarch64.rpm \
       RPMS/5.2.0.15/shipwright-pacific-webview-0.1.0-*.aarch64.rpm \
       RPMS/5.2.0.15/shipwright-pacific-webview-examples-0.1.0-*.aarch64.rpm \
       shoal/pacific/engine/device-check.sh defaultuser@<phone>:
   ```

   Keel must be installed too: `shipwright-keel-silica`, `shipwright-keel-sailfishapp` and Chum's Qt 6.8, as for the other Shoal apps.
2. **Install** (`devel-su` on the phone):

   ```
   pkcon install-local shipwright-pacific-*.rpm
   ```

   If pkcon refuses, use `zypper in --allow-unsigned-rpm ./shipwright-pacific-*.rpm`.
3. **Run the check:** `sh device-check.sh`, as `defaultuser`, with the screen on. Read the verdict and `~/pacific-device-report-*.txt`, and look at `~/pacific-check.png`: it should be a white page with "ok", not black.
   - **NO-GO cases:** a missing `EGL_WL_bind_wayland_display`, `EGL_KHR_image_base` or `GL_OES_EGL_image`; engine libraries that do not resolve; a headless load that fails.
   - Record `EGL_ANDROID_native_fence_sync`, the EGL version (decides `PACIFIC_EGL_STUBS`), Codec2 and droidvdec, and the page size.
4. **Render and scroll by hand:**

   ```
   /usr/libexec/pacific/pacific-env.sh pacific-minibrowser --silica https://en.wikipedia.org/wiki/Pacific_Ocean
   ```

   - Scroll. Watch for black tiles and half-drawn frames.
   - Tap a search field: does Maliit open, and does text arrive?
   - Try `--script-input` for the comparison.
   - Open a `<select>`, then a date field.
   - Rotate the phone.
   - Try `PACIFIC_FRAME_ACK=sample` and `ATLANTIC_SKIP_SWAP_FENCE=1` for fps.
5. **Under Sailjail:** once the UI agent's `shipwright-pacific.desktop` is installed, the device check runs the EGL probe inside the jail with its permissions. Then start Pacific from the launcher and check `journalctl -f` for WebProcess crashes, missing device nodes, and seccomp denials.
6. **Video:** a YouTube 1080p video (H.264 through droidvdec) and a VP9 stream. Watch for audio cutting out after 0.25 s and for the decoder in use (`GST_DEBUG=2`).

Send the report, the screenshot and the notes back. They decide whether the alpha keeps Atlantic's binaries, or needs `PACIFIC_GPU_MODE=cpu` or other changes to the environment.
