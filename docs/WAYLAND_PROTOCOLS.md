# Wayland Protocol Policy (Marathon Shell)

Marathon Shell is both the **Wayland compositor** and the **system shell**. External/native apps connect as Wayland clients.

Deepak’s guideline: **only implement what we need**, keep perf-sensitive glue in C++, and avoid unnecessary protocol surface area.

## Supported protocols (current)

### Always enabled (required for real apps)
- **`wl_shm`**: Required for many clients (GTK, etc.) that use shared-memory buffers.
- **`xdg-shell`**: Modern standard for application windows (most clients).
- **`wp_viewporter`**: Needed by Firefox/GTK clients for destination sizing and correct rendering under scaling.
- **`zwp_text_input_manager_v2`** (Qt: `QWaylandTextInputManager`): Needed for on-screen keyboard / text input integration with Wayland apps.
- **`zwp_idle_inhibit_manager_v1`**: Used by media apps to prevent screen blanking during playback.

All of the “Always enabled” protocols above are **enabled by default**, but can be disabled for debugging/minimal builds via env vars:
- `MARATHON_WL_ENABLE_VIEWPORTER=0`
- `MARATHON_WL_ENABLE_TEXT_INPUT_V2=0`
- `MARATHON_WL_ENABLE_IDLE_INHIBIT=0`

### Optional (legacy compatibility)
- **`wl_shell`**: Deprecated legacy protocol. Some older/embedded clients may still use it, but modern apps should use `xdg-shell`.
  - **Default**: **disabled**
  - **Enable**: set env var `MARATHON_WL_ENABLE_WL_SHELL=1`

## Socket name (important for auditing under GNOME)
Marathon’s compositor listens on a **separate Wayland socket** from the host desktop compositor (e.g. GNOME). By default:
- **Socket**: `marathon-wayland-0`
- **Override**: `MARATHON_WL_SOCKET_NAME=marathon-wayland-test-0` (useful for dev/testing and avoiding stale sockets)

When you run `wayland-info`, make sure you’re pointing at Marathon’s socket, not the host compositor:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=marathon-wayland-0
wayland-info -i xdg_wm_base
```

## How to audit advertised globals (recommended)
To verify we’re only exposing what we intend, query the globals directly:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=marathon-wayland-0

for iface in wl_shell xdg_wm_base wp_viewporter zwp_text_input_manager_v2 zwp_idle_inhibit_manager_v1; do
  echo "### $iface"
  wayland-info -i "$iface" || true
  echo
done
```

## Implementation notes
- Protocol globals are created in `shell/src/wayland/waylandcompositor.cpp` constructor.
- If a protocol is optional, it must be **gated** behind an env/config flag and **documented here**.

## Future work (audit targets)
- Consider adding a small on-disk config (per `platforms/generic/`) instead of env vars once config consolidation is complete.
- Re-audit when adding new client classes (e.g., games requiring relative pointer, pointer constraints, etc.).


