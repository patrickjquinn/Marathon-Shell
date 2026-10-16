# Native app scale

How GTK, Qt/KDE and Flatpak apps that are not Marathon apps get drawn at
the right physical size.

## The problem

The shell runs Qt with `QT_ENABLE_HIGHDPI_SCALING=0` and sizes its own UI
from the panel DPI (`Constants.scaleFactor = DPI / 160 × interface size`).
Marathon apps (`marathon-app-runner`, Keel hosts) receive `MARATHON_DPI` /
the Silica pixel ratio and do the same. A native client knows none of this:
the compositor advertised `wl_output.scale = 1` and no fractional scale, so
GTK and Qt drew at desktop size, about a third too small on a 254–290 dpi
phone panel.

## The protocols

- **wp_fractional_scale_v1** (wayland-protocols staging). The compositor
  sends `preferred_scale` per surface as a numerator over 120 (1.5 = 180).
  The client keeps `wl_surface.buffer_scale` at 1, renders a buffer of
  `logical × scale` and sets a `wp_viewport` destination of the logical
  size. Requires `wp_viewporter`.
- **wl_output.scale** (core, integer). Clients without fractional support
  pick the scale of the outputs their surface is on and set
  `wl_surface.set_buffer_scale(n)` with an `n×` buffer.
- **wl_surface.preferred_buffer_scale** (wl_compositor v6). Qt 6.11's
  compositor implements wl_compositor v5 only, so this is not available;
  integer clients use wl_output.scale.

Clients:

| Client | Uses | Verified |
|---|---|---|
| GTK 4 / libadwaita (4.12+; on by default for GL from 4.14) | fractional + viewport | GTK 4.22.4 on the host: `preferred_scale(180)` → 720×720 buffer, `set_destination(480, 480)` |
| Qt 6.5+ | fractional + viewport, only under the default `PassThrough` rounding policy; otherwise preferred_buffer_scale / wl_output.scale | Qt 6.11.2 `qml`: window DPR 1.5, **even with `QT_ENABLE_HIGHDPI_SCALING=0`** |
| GTK 3 | wl_output.scale only | GTK 3.24.52: `wl_output.scale(2)` → `set_buffer_scale(2)`, 960×960 buffer for a 480×480 window |
| Firefox, Chromium/Electron | fractional (recent versions) | not tested |

`QT_ENABLE_HIGHDPI_SCALING=0` only disables Qt's own factor; a Wayland
window's DPR is still the platform window's scale
(`QWindowPrivate::updateDevicePixelRatio`: `platformWindow->devicePixelRatio()
* QHighDpiScaling::factor`). So Marathon's own Qt clients *would* scale if
told to, which is why they are exempted (below).

## How QtWaylandCompositor shows a scaled surface

`QWaylandQuickItem` (6.11):

- implicit size = `surface->destinationSize() × output scale / window DPR`
  (`updateSize`). `destinationSize` is the viewport destination, else
  buffer size / buffer scale — the logical size either way.
- the texture is drawn over the item's whole rect, the source rect taken
  from `sourceGeometry × bufferScale`.
- touch points are sent **unmapped**, in item coordinates
  (`QWaylandTouch::sendFullTouchEvent` uses `tp.position()`); mouse events go
  through `mapToSurface` (item size / destinationSize).
- popups and subsurfaces are child items placed and sized with the same
  output-scale factor (`XdgPopupIntegration::handleGeometryChanged`,
  `handleSubsurfacePosition`).

The output scale can only be an integer and applies to every item, so it
cannot carry a fractional, per-client scale. Instead the shell's
`WaylandShellSurfaceItem` stays at Qt's factor 1 and is transformed:

- the item takes its implicit size (the surface's logical size) and
  `scale: clientScale` with `transformOrigin: TopLeft`. On screen it is
  `logical × scale` = the buffer's pixels, so a fractional client's buffer is
  shown 1:1 and a GTK 3 2× buffer is scaled down.
- item coordinates are surface coordinates, so touch, mouse, popups and
  subsurfaces all line up with no extra mapping.
- configures carry `round(app area / clientScale)`.

For Marathon clients `clientScale` is 1 and the item fills its parent as
before.

## The scale

```
nativeScale = round4( (NATIVE_SCALE or DPI / 160) × interface size ),  ≥ 1
```

`DPI` is the shell's own (`ScreenMetrics::dpi`, i.e. `MARATHON_FORCE_DPI`
when set), the same number the shell's scale factor and the Keel/Silica
pixel ratio come from, so a native app's logical pixel is the shell's dp.
It follows the interface-size setting live. Quarter steps keep buffers at
familiar fractional sizes; GTK and Qt both clamp below 1.

`NATIVE_SCALE` / `MARATHON_NATIVE_SCALE` in the device profile replaces
`DPI / 160` (still multiplied by the interface size). `NATIVE_SCALE=1`
turns native scaling off for a device.

| Device | DPI (source) | DPI/160 | nativeScale | Logical width |
|---|---|---|---|---|
| Librem 5 | 287 (`FORCE_DPI`, greetd) | 1.79 | 1.75 | 411 of 720 |
| PinePhone | 270 (`FORCE_DPI`, greetd) | 1.69 | 1.75 | 411 of 720 |
| QEMU virtio | 296 (session default) | 1.85 | 1.75 | 411 of 720 |
| HackberryPi CM5 | 254 (`FORCE_DPI`, profile) | 1.59 | 1.5 | 480 of 720 |
| OnePlus 6 | ~402 (panel, no override) | 2.51 | 2.5 | 432 of 1080 |
| Zinwa Q25 | ~295 (62 mm panel, no override) | 1.84 | 1.75 | 411 of 720 |
| Pi 5 on a desktop monitor | ~96 | 0.6 | 1 | unchanged |

(Phosh uses 2 on the Librem 5 / PinePhone, i.e. 360 logical px; Marathon's
1.75 matches Marathon's own UI instead.)

GTK 3 and other integer clients get `ceil(nativeScale)` as their
`wl_output.scale` (2 at 1.5 and 1.75, 3 at 2.5) and the item scales the
buffer down to `nativeScale`. This is what Mutter and KWin do for
integer-only clients: rendering at the next integer and downscaling stays
sharp, rendering at the floor and upscaling would blur.

## Marathon's own clients

`NativeClientScale` reads `/proc/<pid>/environ` of each client as it
connects (pid from `SO_PEERCRED`). A client carrying
`MARATHON_SHELL_PID=<the shell's pid>` — the shell sets it for every
`marathon-app-runner` (on-demand, pool spare, unsandboxed) and Keel host,
and hosted Sailfish apps inherit it — is first-party:

- the `wp_fractional_scale_manager_v1` global is hidden from it
  (`wl_display_set_global_filter`), so a Qt runner does not even create a
  viewport;
- its `wl_output.scale` stays at Qt's 1;
- its configures and its item are unchanged.

The result for Marathon apps is the same protocol traffic as before the
change.

## Limits

- A native app spawned *by* a Marathon app inherits `MARATHON_SHELL_PID`
  and is treated as first-party (drawn at 1).
- Qt's popup placement ignores xdg_positioner constraints for every client,
  so a menu near the right edge can run off screen.
- A logical size that isn't a whole pixel at the scale (720 / 1.75) leaves
  the buffer a fraction of a pixel off the item's edge; GTK rounds its
  buffer, the item shows it at `logical × scale`.

## Sources

- wayland-protocols `staging/fractional-scale/fractional-scale-v1.xml`
- Qt 6.11.2 source: qtbase `src/plugins/platforms/wayland/qwaylandwindow.cpp`
  (`updateScale`), qtbase `src/gui/kernel/qwindow.cpp`
  (`updateDevicePixelRatio`), qtwayland
  `src/compositor/compositor_api/qwaylandquickitem.cpp`, `qwaylandoutput.cpp`,
  `extensions/qwaylandxdgshellintegration.cpp`, `qwaylandcompositor.cpp`
  (`wl_compositor::init(display, 5)`)
- [Qt 6.5: fractional-scale-v1 used by the Wayland platform plugin](https://doc.qt.io/qt-6.5/qtwaylandcompositor-attribution-fractional-scale-v1.html)
- [GTK 4.11.1: fractional scaling via wp_fractional_scale + wp_viewporter](https://blog.gtk.org/2023/04/05/gtk-4-11-1/),
  [GTK #6590 (4.14 GL fractional on by default, `GDK_DEBUG=gl-no-fractional`)](https://gitlab.gnome.org/GNOME/gtk/-/issues/6590)
- [wp_fractional_scale_v1 reference](https://wayland.app/protocols/fractional-scale-v1)
- Host measurements: `WAYLAND_DEBUG=1` traces of GTK 4.22.4/libadwaita 1.9.3,
  GTK 3.24.52 and Qt 6.11.2 clients against a QtWaylandCompositor with
  `NativeClientScale`.
