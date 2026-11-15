#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Pacific day-1 device check: run on the phone, as the normal user (defaultuser),
# from a terminal or over SSH. Copy it over with the engine RPMs:
#
#   scp shoal/pacific/engine/device-check.sh defaultuser@<phone>:
#   ssh defaultuser@<phone> sh device-check.sh
#
# Collects what decides go/no-go for Pacific's engine on this phone (README.md
# "Day 1"): page size, EGL and GL extensions (as a Wayland client of Lipstick,
# like the app), GPU device nodes, whether a Sailjailed process keeps the GPU,
# libhybris and media packages, Codec2 and gst-droid decoders, whether the
# engine's libraries resolve, and a headless page load. Everything goes to
# ~/pacific-device-report-<time>.txt; a verdict is printed at the end.
#
# Read-only apart from the report; no root needed (some lines say "needs
# root" and are skipped). PACIFIC_ENGINE_PREFIX (default /opt/pacific) and
# PACIFIC_DESKTOP (default shipwright-pacific.desktop) can be overridden.
set -u
prefix=${PACIFIC_ENGINE_PREFIX:-/opt/pacific}
desktop=${PACIFIC_DESKTOP:-shipwright-pacific.desktop}
probe=/usr/libexec/pacific/pacific-egl-probe
envsh=/usr/libexec/pacific/pacific-env.sh
report=${PACIFIC_REPORT:-$HOME/pacific-device-report-$(date +%Y%m%d-%H%M%S).txt}
verdict=GO
notes=""

log() { printf '%s\n' "$*" >>"$report"; }
section() { printf '\n== %s\n' "$*" >>"$report"; printf '%s\n' "-- $*" >&2; }
run() { printf '$ %s\n' "$*" >>"$report"; "$@" >>"$report" 2>&1; }
fail() { verdict=NO-GO; notes="$notes
  NO-GO: $*"; log "NO-GO: $*"; }
warn() { [ "$verdict" = GO ] && verdict="GO (with warnings)"; notes="$notes
  warning: $*"; log "WARNING: $*"; }

: >"$report" || { echo "device-check: cannot write $report" >&2; exit 2; }
log "Pacific device check, $(date -Iseconds)"

section "System"
run uname -a
run cat /etc/os-release
run sh -c 'grep -E "^(MemTotal|MemAvailable|SwapTotal)" /proc/meminfo'
run sh -c 'cat /proc/cpuinfo | grep -E "^(processor|CPU part|Hardware)" | sort | uniq -c'
run getprop ro.product.model
run id

section "Page size"
pagesize=$(getconf PAGESIZE 2>/dev/null || echo unknown)
log "PAGESIZE=$pagesize"
# Atlantic's build targets 4 KiB pages (no USE_64KB_PAGE_BLOCK). It also ran
# pages with the JIT on a 16 KiB Asahi host; 64 KiB is out.
case $pagesize in
    4096) ;;
    16384) warn "page size 16384: works on the development host, untested on a phone" ;;
    *) fail "page size is $pagesize, the engine is built for 4096" ;;
esac

section "GPU device nodes"
run sh -c 'ls -l /dev/dri /dev/mali* /dev/dma_heap /dev/ion /dev/kgsl* 2>&1'
run sh -c 'grep -i -E "mali|kgsl|drm" /proc/devices'
[ -e /dev/mali0 ] && log "Mali kernel driver present: PACIFIC_GPU_MODE=mali by default"
[ -e /dev/dri ] || log "no /dev/dri (expected on libhybris; the engine renders through hybris EGL)"

section "EGL / GLES (Wayland client of Lipstick)"
if [ -x "$probe" ]; then
    out=$("$probe" 2>&1)
    printf '%s\n' "$out" >>"$report"
    egl=$(printf '%s\n' "$out" | sed -n 's/^egl_extensions: //p')
    gl=$(printf '%s\n' "$out" | sed -n 's/^gl_extensions: //p')
    for ext in EGL_WL_bind_wayland_display EGL_KHR_image_base EGL_KHR_image_pixmap; do
        case " $egl " in *" $ext "*) log "have $ext" ;; *) [ "$ext" = EGL_KHR_image_pixmap ] || fail "missing $ext" ;; esac
    done
    for ext in EGL_ANDROID_image_native_buffer EGL_KHR_fence_sync EGL_KHR_wait_sync EGL_ANDROID_native_fence_sync EGL_EXT_image_dma_buf_import EGL_KHR_surfaceless_context EGL_HYBRIS_native_buffer EGL_HYBRIS_native_buffer2 EGL_EXT_buffer_age; do
        case " $egl " in *" $ext "*) log "have $ext" ;; *) log "lacks $ext" ;; esac
    done
    case " $egl " in *" EGL_ANDROID_native_fence_sync "*) ;; *) warn "no EGL_ANDROID_native_fence_sync: frames reach Qt without a fence (Mali mode keeps glFinish on)" ;; esac
    for ext in GL_OES_EGL_image GL_OES_EGL_image_external GL_EXT_texture_format_BGRA8888; do
        case " $gl " in
            *" $ext "*) log "have $ext" ;;
            *) if [ "$ext" = GL_OES_EGL_image ]; then fail "missing $ext"; else log "lacks $ext"; fi ;;
        esac
    done
    printf '%s\n' "$out" | grep -q '^egl_version: 1\.5' || log "EGL below 1.5: libegl-stubs.so stays preloaded (PACIFIC_EGL_STUBS=1)"
else
    fail "$probe is not installed (shipwright-pacific-engine)"
fi

section "GPU under Sailjail"
if command -v sailjail >/dev/null 2>&1 && [ -f "/usr/share/applications/$desktop" ] && [ -x "$probe" ]; then
    jailed=$(sailjail -p "$desktop" "$probe" 2>&1)
    printf '%s\n' "$jailed" >>"$report"
    if printf '%s\n' "$jailed" | grep -q '^gl_renderer:'; then
        log "the probe renders inside Sailjail with $desktop's permissions"
        printf '%s\n' "$jailed" | grep -q 'gl_renderer: .*llvmpipe' && fail "Sailjailed GL fell back to software (llvmpipe)"
    else
        fail "no GL context inside Sailjail with $desktop's permissions"
    fi
    run sailjail -p "$desktop" /usr/bin/id
else
    warn "Sailjail check skipped (needs sailjail, /usr/share/applications/$desktop and the probe)"
fi

section "libhybris, droid and media packages"
run sh -c 'rpm -qa | grep -i -E "hybris|droid|gst-droid|droidmedia|codec2|gstreamer1.0|pulseaudio|maliit|qt6-qtbase|qt6-qtwayland|shipwright-keel|shipwright-pacific|libsoup3|libicu|libseccomp" | sort'
run sh -c 'cat /etc/ld.so.preload 2>/dev/null || echo "(no /etc/ld.so.preload)"'

section "Codec2 and gst-droid decoders"
for f in /vendor/etc/media_codecs_c2.xml /vendor/etc/media_codecs.xml /odm/etc/media_codecs_c2.xml /etc/gst-droid/gstdroidcodec.conf; do
    if [ -r "$f" ]; then
        log "$f:"
        grep -o 'name="[^"]*"' "$f" | sort -u >>"$report"
    else
        log "$f: not readable"
    fi
done
if command -v gst-inspect-1.0 >/dev/null 2>&1; then
    run sh -c 'gst-inspect-1.0 2>/dev/null | grep -i -E "droid|vp9|vp8|avdec_h264|avdec_aac|opus|pulse"'
    gst-inspect-1.0 droidvdec >/dev/null 2>&1 || warn "no droidvdec: video decodes in software"
else
    warn "gst-inspect-1.0 missing (gstreamer1.0-tools): decoders not listed"
fi

section "Engine libraries"
if [ -d "$prefix/lib" ]; then
    missing=$(LD_LIBRARY_PATH="$prefix/lib:$prefix/lib/compat" ldd "$prefix/lib/libWPEWebKit-2.0.so.1" \
        "$prefix/libexec/wpe-webkit-2.0/WPEWebProcess" "$prefix/libexec/wpe-webkit-2.0/WPENetworkProcess" 2>&1 | grep "not found" | sort -u)
    if [ -n "$missing" ]; then
        log "$missing"
        fail "engine libraries do not resolve (see above)"
    else
        log "every engine library resolves"
    fi
    q=/usr/lib64/qt6/qml/Shipwright/Pacific/WebView/libpacificwebview.so
    [ -f "$q" ] && run sh -c "LD_LIBRARY_PATH=$prefix/lib:$prefix/lib/compat ldd $q | grep -E 'not found|WPEWebKit|Qt6Quick'"
else
    fail "$prefix is missing (install shipwright-pacific-engine)"
fi

section "Spell checking"
if [ -x "$prefix/bin/enchant-lsmod-2" ]; then
    dicts=$(ENCHANT_CONFIG_DIR=$(mktemp -d) "$prefix/bin/enchant-lsmod-2" -list-dicts 2>&1)
    printf '%s\n' "$dicts" >>"$report"
    printf '%s\n' "$dicts" | grep -q "en_GB (hunspell)" || fail "enchant lists no en_GB hunspell dictionary"
    printf '%s\n' "$dicts" | grep -q "^fi (voikko)" || fail "enchant lists no Finnish (Voikko) dictionary"
    word=$(echo "kisssa" | ENCHANT_CONFIG_DIR=$(mktemp -d) VOIKKO_DICTIONARY_PATH=$prefix/share/voikko \
        "$prefix/bin/enchant-2" -d fi_FI -a 2>&1 | grep '^&')
    log "Finnish check of 'kisssa': $word"
    case $word in *kissa*) ;; *) fail "Voikko does not suggest 'kissa' for 'kisssa'" ;; esac
    run sh -c "ls $prefix/share/hunspell"
else
    fail "$prefix/bin/enchant-lsmod-2 missing (spell checking)"
fi

section "Headless page load"
mb=/usr/bin/pacific-minibrowser
if [ -x "$mb" ] && [ -x "$envsh" ]; then
    page='data:text/html,<title>pacific-check</title><h1>ok</h1><a href="https://example.org/">link</a><input type=email>'
    out=$(QT_FORCE_STDERR_LOGGING=1 timeout 60 "$envsh" "$mb" --headless --snapshot --timeout 45 "$page" 2>&1)
    printf '%s\n' "$out" >>"$report"
    if printf '%s\n' "$out" | grep -q '"title":"pacific-check"'; then
        log "headless load and agent snapshot work"
    else
        fail "headless page load failed (WebProcess, GPU or library problem; see above)"
    fi
    out=$(QT_FORCE_STDERR_LOGGING=1 timeout 60 "$envsh" "$mb" --screenshot "$HOME/pacific-check.png" --timeout 45 "$page" 2>&1)
    printf '%s\n' "$out" >>"$report"
    if [ -s "$HOME/pacific-check.png" ]; then
        log "windowed render saved to $HOME/pacific-check.png: look at it (a heading 'ok', not black)"
    else
        fail "windowed render did not produce a screenshot"
    fi
else
    warn "pacific-minibrowser not installed (shipwright-pacific-webview-examples): no load test"
fi

section "Verdict"
log "$verdict$notes"
printf '\nPacific device check: %s%s\nReport: %s\n' "$verdict" "$notes" "$report"
case $verdict in NO-GO) exit 1 ;; *) exit 0 ;; esac
