# Phase C-7 status

End-to-end QEMU validation of the split-process Marathon stack.

## What landed

Branch `ux-overhaul`. Commits relevant to C-7:

- `0a04892` — call `QWaylandCompositor::create()` before `attachWindow`
- `76e0737` — construct `QWaylandQuickOutput` with `(compositor, window)` directly
- `8b30bab` — `scripts/verify-split.sh` for in-guest verification
- C-7 image-side wiring: `marathon-shell-session` in `Marathon-Image` now spawns
  `/usr/bin/marathon-compositor` as a child, waits for the wl socket, and
  execs `marathon-shell-bin` with `MARATHON_WAYLAND_CLIENT_MODE=1` and
  `QT_QPA_PLATFORM=wayland`. Bumped APKBUILD to r43.

## What works

- `marathon-compositor` + `marathon-shell` + 4 wlr-protocol clients + session-lock
  client all build clean on Fedora 42 host.
- Offscreen smoke test on the host confirms every release of `marathon-compositor`
  advertises all five protocols on the wire (`xdg_wm_base`, `zwlr_layer_shell_v1`,
  `zwlr_foreign_toplevel_manager_v1`, `zwlr_screencopy_manager_v1`,
  `ext_session_lock_manager_v1`).
- duranium mkosi image build (r43 apk in `mkosi.packages/`) completes.
- QEMU boot reaches greetd → marathon-shell-session.

## What blocks finishing C-7

`marathon-compositor` segfaults in the QtQuick render thread during the first
scene-graph sync when running under `QT_QPA_PLATFORM=eglfs` +
`QT_QPA_EGLFS_INTEGRATION=eglfs_kms` against the virtio-gpu device the QEMU
image ships with. Behaviour reproduced across three iterations:

| Build  | Symptom                                                      |
|--------|--------------------------------------------------------------|
| r41    | `qt.scenegraph.time.renderer: total=7ms` then SEGV (signal 11) |
| r42    | Identical SEGV after the `create()`/`attachWindow` reorder    |
| r43    | Identical SEGV after the `QWaylandQuickOutput` ctor change    |

The crash is inside the render thread, with a stripped stack trace
(`coredumpctl info` shows `n/a (n/a + 0x0)` for every frame because the
Alpine apk packaging strips debug symbols from the compositor binary).
verify-split.sh consequently reports 4 pass / 7 fail — both
`marathon-compositor` and `marathon-shell-bin` are dead by the time the
script runs, so all protocol + respawn + RSS checks miss.

The in-shell legacy compositor (r39 image, host-compositor mode) ran fine on
the same eglfs+virtio-gpu+LLVMpipe stack with a 358 MB shell RSS, so the
toolchain is not at fault. The standalone binary's QML scene wiring is
where the bug lives.

## Suggested next steps (next session)

1. **Build a debug apk.** The current APKBUILD passes
   `-DCMAKE_BUILD_TYPE=MinSizeRel` and Alpine strips symbols. A
   `MinSizeRel`-with-`-g` build (and skipping `abuild`'s strip step for
   `marathon-compositor` only) would let `coredumpctl debug` resolve the
   trace and identify the crashing function.
2. **Try `QWaylandQuickCompositor`.** Phosh/kwin both use the Quick variant.
   Switching `MarathonCompositor`'s base class from `QWaylandCompositor` to
   `QWaylandQuickCompositor` would align with the upstream pattern.
3. **Strip Compositor.qml to a bare Window.** Remove the Repeater +
   WaylandQuickItem binding to isolate whether the crash is in scene-graph
   sync of QML elements or somewhere deeper.
4. **Check whether QtWayland 6.11 has a known compositor + virtio-gpu issue.**
   Web search for `QtWayland virtio-gpu LLVMpipe render thread segfault`.

In-tree C-1..C-6 is shippable as-is for non-eglfs targets; the eglfs+virtio-gpu
runtime path is the gating issue. None of the protocol or client code is
suspect.
