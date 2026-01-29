# Debian / Raspberry Pi OS Crash Options

Plausible causes for Marathon apps (and potentially native Wayland apps)
crashing on Debian-based systems (specifically Raspberry Pi OS) while working on Fedora. focusing on
on Wayland protocol expectations and Debian-specific platform differences, for now (May apply to PMOS).

## Wayland protocol baseline (potentially why these failures show up??)

Wayland clients rely on:
- `wl_shm` for shared-memory buffers and `wl_buffer` submission. If EGL-based buffers fail, many
  clients must fall back to shm to keep working. (have seen this previously in testing...)
- `xdg_wm_base` (xdg-shell) for `xdg_surface` / `xdg_toplevel` roles, configure events, and the
  ping/pong mechanism for responsiveness. Misbehavior here can cause clients to abort or hang.

These specifically call this out:
- Wayland Protocol Specification (wl_shm, wl_surface, wl_buffer)  
  https://wayland.freedesktop.org/docs/html/apa.html
- XDG shell overview / xdg_wm_base roles and configure/ping  
  https://wayland.app/protocols/xdg-shell

## Most likely causes (in order)

### 1) Wayland-EGL initialization failure (Pi OS)
**Symptom:** `qt.qpa.wayland: EGL not available`, EGL display/context creation fails.  
**Why:** Pi OS stacks often lack `EGL_WL_bind_wayland_display` or proper EGL extensions for
Wayland-EGL, causing Qt Wayland clients to abort.  
**Evidence:**  
https://forum.qt.io/topic/142178/qt-qpa-plugin-could-not-load-the-qt-platform-plugin-wayland-egl-in-even-though-it-was-found  
https://forum.qt.io/topic/76621/qtwayland-error-on-raspberry-pi  
https://stackoverflow.com/questions/75852022/qt-reports-qt-qpa-wayland-egl-not-available-what-did-i-missed

**Impact on Marathon:** The compositor defaults to `wayland-egl` unless forced to SHM. If EGL fails,
apps can crash immediately.

### 2) Missing Wayland EGL extension (EGL_WL_bind_wayland_display)
**Symptom:** `Failed to initialize EGL display. There is no EGL_WL_bind_wayland_display extension.`  
**Why:** Broadcom/VC4 driver stacks can lack this extension on some Pi OS configs.  
**Evidence:**  
https://forum.qt.io/topic/76621/qtwayland-error-on-raspberry-pi

### 3) Qt version mismatch (Fedora 6.8/6.9 vs Debian 6.4.2)
**Why:** Fedora ships newer Qt (6.8/6.9) while Debian Bookworm/PI OS ships 6.4.2. Qt 6.4 has known
Wayland + RHI differences, and missing fixes can trigger crashes that don’t reproduce on Fedora.  
**Evidence (versions):**  
https://packages.fedoraproject.org/pkgs/qt6-qtbase/qt6-qtbase/fedora-42.html  
https://packages.debian.org/bookworm/qt6-base-dev

### 4) Debian multi-arch QML import path mismatch
**Symptom:** QML modules not found → app runner exits early.  
**Why:** Debian ARM uses `/usr/lib/aarch64-linux-gnu/qt6/qml` (arm64) or
`/usr/lib/arm-linux-gnueabihf/qt6/qml` (armhf). If runtime import paths omit these, QML module
resolution fails.  
**Evidence:**  
https://lists.debian.org/debian-qt-kde/2024/12/msg00199.html

### 5) dbus-run-session isolation (Wayland session conflicts)
**Symptom:** App connects to the wrong session bus or fails to access required services.  
**Why:** `dbus-run-session` can conflict with dbus-broker/systemd user sessions in Wayland setups.  
**Evidence:**  
https://bugs.kde.org/show_bug.cgi?id=404335  
https://bbs.archlinux.org/viewtopic.php?id=308583

### 6) Landlock / sandbox side effects (less likely, but possible)
**Symptom:** App fails accessing files or sockets outside allowed rules.  
**Why:** Landlock can block access to resources if paths or permissions are misconfigured.  
**Evidence (Landlock scoping behavior):**  
https://man.archlinux.org/man/landlock.7.en

## Additional contributing factors

- **XDG_RUNTIME_DIR** not set or not writable can prevent Wayland sockets or SHM buffers. This can
  cause immediate client failure in Wayland environments.  
  https://wayland.freedesktop.org/docs/html/apa.html

- **Wayland shm fallback** may be required on Pi OS for stability. If EGL fails, a fallback to
  `wl_shm` is the only reliable path for many clients.  
  https://wayland.freedesktop.org/docs/html/apa.html

## What to test first (fastest signal)

1) Force SHM buffers for clients on Pi OS:
   - `MARATHON_FORCE_WAYLAND_SHM=1`
2) Disable sandbox to remove Landlock + dbus-run-session:
   - `MARATHON_ENABLE_SANDBOX=0`
3) Enable QML import trace to confirm module path failures:
   - `QML_IMPORT_TRACE=1`

These map directly to the failure options above and will hopefully let us quickly isolate whether the cause is
Wayland-EGL, QML import paths, or sandbox isolation. At this point im scatching my head a lil...

