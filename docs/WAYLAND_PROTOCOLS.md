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

### Optional (legacy compatibility)
- **`wl_shell`**: Deprecated legacy protocol. Some older/embedded clients may still use it, but modern apps should use `xdg-shell`.
  - **Default**: **disabled**
  - **Enable**: set env var `MARATHON_WL_ENABLE_WL_SHELL=1`

## Implementation notes
- Protocol globals are created in `shell/src/waylandcompositor.cpp` constructor.
- If a protocol is optional, it must be **gated** behind an env/config flag and **documented here**.

## Future work (audit targets)
- Consider adding a small on-disk config (per `platforms/generic/`) instead of env vars once config consolidation is complete.
- Re-audit when adding new client classes (e.g., games requiring relative pointer, pointer constraints, etc.).


