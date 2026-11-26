# MP01 e-paper refresh control: the interim ABI and the upstream API

## What the hardware does

The Pango CPLD receives ordinary DSI video and updates the e-paper wherever
consecutive frames differ. It diffs the frames itself, so the host never
sends a partial-update command: what the host scans out is what the CPLD
updates. Its I2C port exposes two controls.

- **Waveform** (reg 0x8c, 0-3). This sets how each change is driven.
  The table below was measured by eye on the phone by the LuneOS port
  (einkd) and matches stock `MinimalRefreshService`.
- **Clear** (reg 0x8e = 0x05). This is a full flashing refresh that
  removes ghosting. Stock always writes waveform 2 straight after it and
  puts the user's waveform back 100 ms later. Nobody knows why, so the
  driver copies the sequence exactly.

| Value | Driver name | Look | Stock name |
|---|---|---|---|
| 0 | `quality` | full greyscale, slowest, cleanest | Slow |
| 1 | `clean` | greyscale, less ghosting than 0; **switching into it flashes twice** | (none) |
| 2 | `text` | nearly two-level: crisp text, images lose their greys | (none) |
| 3 | `fast` | fastest, most ghosting | Ultra |

Switching among 0, 2 and 3 is silent. Hybrid/auto (0 at rest, 3 while
scrolling) is policy and belongs in the compositor, not the kernel.

## Interim ABI (in this series)

These are sysfs attributes on the CPLD's I2C device, for example
`/sys/bus/i2c/devices/7-004b/`:

- `refresh_mode` (rw): reads back as `[quality] clean text fast`, with
  the current mode in brackets, and takes one of those names. While the
  module is powered down, the choice is stored and written at the next
  prepare. It survives blank, unblank and suspend.
- `full_refresh` (wo): `1` runs the clear sequence. While the display is
  off it returns `-EAGAIN`, since there is nothing to clear.

These are documented in `Documentation/ABI/testing/sysfs-driver-panel-minimal-z10-eink`.
They are not rate-limited. Stock drops a second mode change within 200 ms,
and that rule stays in userspace.

The vendor's `eink_cpld_registers` attribute was a write-a-number
multiplexer, and value 9 on it reflashed the CPLD. It is not reproduced in
any form.

## Where this should go upstream

sysfs on a panel device is not where DRM puts display state. The upstream
shape is KMS state, so that the compositor commits the waveform with the
frame it applies to:

1. **A connector property, "refresh waveform"** (enum: an
   `epd waveform` list exposed by the panel). It is set in the same
   atomic commit as the planes, so a scroll that switches to `fast` and
   the first scrolled frame land together. Two pieces are missing upstream
   for this. First, a `drm_panel` hook that lets a panel describe connector
   properties: the connector is made by `drm_bridge_connector` and the panel
   bridge, not by the panel. Second, an `atomic_check`/`atomic_enable` path
   that hands the panel the new connector state. A generic version of both
   would also serve host-side EPD controllers, such as the Rockchip EBC
   RFC series, which need the same per-commit waveform choice. The property values should
   be named by behaviour (`quality`, `clean`, `text`, `fast`), not by the
   CPLD's index, so that other EPD controllers can map their own LUTs onto
   them.
2. **A "full refresh" request** is an event, not state. It fits best as a
   connector property with a one-shot meaning, like `"CRTC" ACTIVE`
   toggles: a `FULL_REFRESH` boolean that the driver clears after acting on
   it. An alternative is a damage-clip convention: one damage clip that
   covers the whole plane, with a flag. The property is simpler and needs
   no new uAPI type.
3. **Damage.** `FB_DAMAGE_CLIPS` is already the upstream way to say which
   region changed. This CPLD diffs frames itself, so it does not need the
   clips. A host-side EPD controller would use them to pick per-region
   waveforms. The compositor should send damage anyway (see the Marathon
   policy note), so it is ready for controllers that can use it.
4. **Display class.** Userspace needs to know that a connector is an
   e-paper panel without a device-ID check. A read-only connector property
   (`"panel type"`: `lcd`, `oled`, `epd`), or a `drm_display_info` flag
   exported as a property, gives compositors the capability bit. Until
   that exists, the presence of the `refresh_mode` attribute on the
   panel's device is the interim signal.

Until 1-4 exist, the sysfs pair is the interim, and it lives only in the
MP01 overlay series.

## Not done in the kernel, on purpose

- No automatic clear after N partial updates. That is a ghosting policy,
  and the compositor knows when the content changed completely (an app
  switch or an unlock).
- No mode switch on scroll detection. The kernel cannot see scrolling;
  the compositor can.
- No VCOM, temperature or waveform-version attributes. The registers are
  readable through regmap debugfs
  (`/sys/kernel/debug/regmap/7-004b/registers`) while the display is on.
