# SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine a91f8ec, cmake/atlantic-wpe-features.cmake)
# SPDX-License-Identifier: MPL-2.0
#
# Shared Atlantic WebKit feature policy used by both the native build script
# and the rpmbuild/spec path.

# GPU process: OFF. WPE defaults ENABLE_GPU_PROCESS ON (OptionsWPE.cmake), and it
# DEPENDS ON USE_GBM (OptionsWPE.cmake: WEBKIT_OPTION_DEPEND ENABLE_GPU_PROCESS
# USE_GBM). The build host has libgbm so it compiles in, but the libhybris/Adreno
# *device* has no GBM / DRM render node (/dev/dri/renderD128 absent) — the GPU
# process starts via the EGL fallback but cannot export composited frames, so
# pages render blank (chrome draws, content area white; verified on Xperia 10 II).
# Disable it so all rendering/compositing happens in the WebProcess (the proven
# hybris path; Skia GPU painting in the WebProcess is unaffected). Revisit on the
# future Mali/Mesa device where GBM should exist — ideally make this runtime-
# conditional on a DRM render node. See target-devices-roadmap.
set(ENABLE_GPU_PROCESS OFF CACHE BOOL "" FORCE)

set(ENABLE_VIDEO ON CACHE BOOL "" FORCE)
set(ENABLE_MEDIA_STREAM ON CACHE BOOL "" FORCE)
# MediaRecorder + WebCodecs: needed by WebRTC sites' capability detection
# (vdo.ninja/codecs dies on an unguarded MediaRecorder reference). Both sit on
# GStreamer encoders; encode paths on hybris are otherwise untested.
set(ENABLE_MEDIA_RECORDER ON CACHE BOOL "" FORCE)
set(ENABLE_WEB_CODECS ON CACHE BOOL "" FORCE)
set(ENABLE_WEB_AUDIO ON CACHE BOOL "" FORCE)
# WebRTC via GstWebRTC. Build deps: libgstreamer-plugins-bad1.0-dev + libnice-dev
# on the host (bootstrap-host.sh); device already ships the gst 1.26 runtime
# plugins (webrtcbin, nice, dtls, srtp). Runtime prefs PeerConnection/MediaDevices
# default off — the qt5 plugin enables them.
set(ENABLE_WEB_RTC ON CACHE BOOL "" FORCE)
set(USE_GSTREAMER_WEBRTC ON CACHE BOOL "" FORCE)
# Geolocation compiles against GDBus only, but at runtime WebKit's provider
# talks to org.freedesktop.GeoClue2 — SFOS only ships geoclue-0.x, so positions
# won't resolve until a GeoClue2 bridge exists. API surface is still worth having.
set(ENABLE_GEOLOCATION ON CACHE BOOL "" FORCE)
# Gamepad: ON. WPE defaults this ON (OptionsWPE.cmake) and we were forcing it
# off for no recorded reason. The port has complete plumbing on both paths —
# WebCore platform/gamepad/libwpe/* and WebKit UIProcess/Gamepad/{libwpe,wpe}/*
# are all in SourcesWPE.txt — and libwpe ships gamepad.h, so the legacy API path
# we use has a provider. libmanette is only consulted under ENABLE_WPE_PLATFORM,
# which we do not build, so it is not a dependency here.
#
# No pad is expected to be connected to a phone most of the time; the honest
# result is navigator.getGamepads() returning an empty list rather than the
# method being absent, which is what a page feature-detecting it should see.
# A Bluetooth controller is a real use case on this device.
set(ENABLE_GAMEPAD ON CACHE BOOL "" FORCE)
# WPEPlatform: OFF. We drive WebKit through the legacy libwpe API
# (WPEBackend-fdo + the Qt5 plugin). Up to 2.52 WPEPlatform defaulted to
# ENABLE_DEVELOPER_MODE, i.e. off; 2.54 defaults it ON, which builds
# libWPEPlatform (xkbcommon, libdrm, ...) and makes the public wpe-webkit-2.0
# headers include wpe-platform/, so the Qt5 plugin stopped compiling
# (WPEKeymapXKB.h -> xkbcommon/xkbcommon.h). Pin the 2.52 configuration.
set(ENABLE_WPE_PLATFORM OFF CACHE BOOL "" FORCE)
# DeviceOrientation / DeviceMotion. Defined PRIVATE OFF in WebKitFeatures.cmake
# and turned on by no port, so window.DeviceOrientationEvent does not exist and
# every sensor-aware page takes its no-sensor path. Everything behind the flag in
# WebCore is generic and present; what upstream never does on a non-Cocoa port is
# *provide* the DeviceOrientationController Page supplement, so the controller
# resolves to null forever. webkit-wpe-device-orientation.patch adds the clients
# and the supplement, plus the IPC that feeds samples from the UI process, where
# the sensors live (WPEDeviceOrientationBridge, QtSensors) — the WebProcess stays
# out of the sensor stack exactly as it does for geolocation.
#
# NOTE this flag alone is NOT a shippable feature: it makes the API appear while
# no event ever fires, so pages feature-detect success and silently get nothing.
# It only makes sense together with the patch and the bridge.
# See docs/investigations/device-orientation.md.
set(ENABLE_DEVICE_ORIENTATION ON CACHE BOOL "" FORCE)
# Spellcheck links host libenchant-2; enchant + hunspell backend + en_US dicts
# are bundled for the device by stage-compat-shims.sh (SFOS has no enchant).
set(ENABLE_SPELLCHECK ON CACHE BOOL "" FORCE)
set(ENABLE_SPEECH_SYNTHESIS OFF CACHE BOOL "" FORCE)
set(ENABLE_SAMPLING_PROFILER OFF CACHE BOOL "" FORCE)
set(ENABLE_INTROSPECTION OFF CACHE BOOL "" FORCE)
set(ENABLE_WEBDRIVER OFF CACHE BOOL "" FORCE)
set(ENABLE_XSLT OFF CACHE BOOL "" FORCE)
# Bubblewrap process sandbox (seccomp + namespaces) re-enabled for SFOS 5.1.
# Build deps: libseccomp + bwrap + xdg-dbus-proxy on the build host; their
# absolute runtime paths are baked in via -DBWRAP_EXECUTABLE /
# -DDBUS_PROXY_EXECUTABLE in scripts/build-webkit.sh.  Still defaults OFF *at
# runtime* in WPE-legacy: deploy/runtime-common.sh turns it on via
# WEBKIT_FORCE_SANDBOX when ATLANTIC_ENABLE_SANDBOX=1.  SFOS/Android-kernel
# sandbox workarounds: patches/webkit/webkit-bubblewrap-sfos-sandbox.patch.
set(ENABLE_BUBBLEWRAP_SANDBOX ON CACHE BOOL "" FORCE)

set(USE_ATK OFF CACHE BOOL "" FORCE)
set(USE_GSTREAMER ON CACHE BOOL "" FORCE)

# WebKit 2.52.4 in this tree registers webkitwebsrc, but does not expose a
# USE_GSTREAMER_WEBKIT_HTTP_SRC CMake toggle to force here.

# GStreamer GL integration: ON (video-playback plan Phase 3). The old "hybris
# EGL in the WebProcess is unstable" concern is stale — the WebProcess has been
# doing all compositing through hybris EGL for hundreds of builds. With GL off,
# every decoded frame is mapped from system memory and uploaded to a texture ON
# THE COMPOSITOR THREAD per composite (CoordinatedPlatformLayerBufferVideo
# fallback path) — device-measured as a major part of the 25-30ms composite
# cost during video playback. With GL on, webkitglvideosink (glupload !
# glcolorconvert) moves the upload+conversion to GStreamer's own GL thread
# (context shared with the compositor's), and the compositor just draws the
# resulting texture. Runtime safety: webKitGLVideoSinkProbePlatform() falls
# back to the old sink if the GL context can't be created, and
# WEBKIT_GST_DISABLE_GL_SINK=1 is a full kill switch —
# deploy/runtime-common.sh ships that default until device-verified.
set(USE_GSTREAMER_GL ON CACHE BOOL "" FORCE)

# Enable Media Source Extensions (MSE) — required for YouTube, Twitch, etc.
# MSE-based players do not use GStreamer HTTP source directly; they push buffers
# via JS. MSE is already implicitly enabled via ENABLE_VIDEO but make it explicit.
set(ENABLE_MEDIA_SOURCE ON CACHE BOOL "" FORCE)

# Enable adaptive bitrate streaming support
set(ENABLE_VIDEO_TRACK ON CACHE BOOL "" FORCE)

# Encrypted Media Extensions (EME v3) API. This compiles in the EME JS surface
# and the software ClearKey key system only — ENABLE_THUNDER stays OFF, so there
# is NO Widevine/PlayReady CDM (real DRM would need the Thunder/OpenCDM stack +
# a proprietary libwidevinecdm.so, which is L3-only and not redistributable).
# Purpose here is API presence: sites that feature-detect EME can negotiate/
# degrade instead of throwing. Runtime pref is enabled in qt5-plugin WPEQtView.
set(ENABLE_ENCRYPTED_MEDIA ON CACHE BOOL "" FORCE)

set(USE_LCMS OFF CACHE BOOL "" FORCE)
set(USE_LIBBACKTRACE OFF CACHE BOOL "" FORCE)
set(USE_LIBHYPHEN OFF CACHE BOOL "" FORCE)
set(USE_OPENJPEG OFF CACHE BOOL "" FORCE)
set(USE_WOFF2 ON CACHE BOOL "" FORCE)
# AVIF image decoding. libavif is built decode-only (dav1d) by build-engine.sh
# and installed into WPE_PREFIX, where WebKit's FindAVIF picks it up via the
# PKG_CONFIG_PATH set in build-webkit.sh. Runtime libs (libavif + libdav1d) are
# bundled into wpe-sfos-compat. NOTE: AVIF decode is software (dav1d) — no HW
# AVIF decode on this device — so it is lighter on bandwidth/memory but heavier
# on CPU per image than JPEG. Primarily a compatibility fix (render AVIF images
# that currently fail) rather than a scroll-perf win.
set(USE_AVIF ON CACHE BOOL "" FORCE)
set(USE_SYSTEM_SYSPROF_CAPTURE OFF CACHE BOOL "" FORCE)
