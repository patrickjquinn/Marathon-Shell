# libhybris's Wayland EGL platform, with cancelled buffers fixed

`eglplatform_wayland.so` as libhybris builds it, from libhybris
[`a1b75cb`](https://github.com/libhybris/libhybris/commit/a1b75cb37fe50198a9a0353f416413464a13184e)
(the Jolla Phone's libhybris 0.0.5.58, Jolla's packaging `f78b6a0`), with one fix
(`cancelled-buffers.patch`).

## The crash

`WaylandNativeWindow::dequeueBuffer()` puts the buffer it hands out on `queue`,
and `finishSwap()` (in `eglSwapBuffers()`) takes the front of `queue`, asserting
that it is still busy. `cancelBuffer()`, which the GPU driver calls for a buffer
it dequeued and then did not draw, marks the buffer free but leaves it on
`queue`: the next swap took it and aborted the process:

    WPEWebProcess: wayland_window.cpp:185: void WaylandNativeWindow::finishSwap(): Assertion `wnb->busy == 1' failed.

Seen while flinging pages in Pacific on the Jolla Phone, about once in fourteen
runs. The fix takes a cancelled buffer off `queue`, and `finishSwap()` skips any
buffer on `queue` that is no longer busy.

## How Pacific uses it

The engine package installs it in `/opt/pacific/lib/hybris/` with links to the
system's other platforms, and `pacific-env` sets `HYBRIS_EGLPLATFORM_DIR` there
only when `/usr/lib64/libhybris/eglplatform_wayland.so` is the exact build it was
made from (size and FNV-1a 64 of the file): the class layouts must match the
device's libhybris. Other devices keep their own. `PACIFIC_HYBRIS_PLATFORM=0`
keeps the system's everywhere.

Built against that build, it has the same exported symbols, the same libraries
and the same object sizes as the system's (checked with `nm -DS`, `readelf -d`
and the `operator new` sizes).

## The build

`build.sh` compiles the three sources with:

- `libhybris/`: the files they need from libhybris at `a1b75cb`
  (LGPL-2.1-only Wayland platform, Apache-2.0 common code, the
  `wayland-android.xml` protocol under the HPND sell variant);
- `aosp/`: Android's native-window, gralloc and graphics headers
  (`android16-release`, Apache-2.0): the `ANativeWindow` ABI GPU drivers rely on;
- `android-config.h` and `sync/sync.h`, written here;
- stub libraries with libhybris's sonames (`stubs.txt`), as the build root has
  no libhybris; the device's own are loaded at run time.
