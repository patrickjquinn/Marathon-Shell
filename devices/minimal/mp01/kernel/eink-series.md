# MP01 e-paper series

These patches drive the Minimal Phone MP01's e-paper display. They are
`mp01-0009` to `mp01-0014` in `packaging/packages/linux-minimal-mp01`,
applied after that package's shared MT6789 series and before the board
DTS (`mp01-0015`), with `CONFIG_DRM_PANEL_MINIMAL_Z10_EINK=m` in
`config-minimal-mp01.fragment`. The series also carried a `minimal`
vendor prefix; `mp01-0001` already adds it, so that copy was dropped.

| Patch | What | Class | Where it goes |
|---|---|---|---|
| mp01-0009 `dt-bindings: display: mediatek: dsi: Describe the data lane order` | `data-lanes` on the DSI output endpoint | SoC-common | the shared MT6789 series, then linux-mediatek |
| mp01-0010 `phy: Add the data lane order to the MIPI D-PHY configuration` | `data_lanes[]` in `phy_configure_opts_mipi_dphy` | generic | the shared MT6789 series, then linux-phy |
| mp01-0011 `phy: mediatek: mipi-dsi: Route the data lanes in the configured order` | MIPITX_PHY_SEL0-3 pad routing from `phy_configure()` | SoC-common, DT-guarded | the shared MT6789 series, then linux-phy |
| mp01-0012 `drm/mediatek: dsi: Take the data lane order from the endpoint` | mtk_dsi reads `data-lanes` and configures the PHY | SoC-common, DT-guarded | the shared MT6789 series, then linux-mediatek |
| mp01-0013 `dt-bindings: display: panel: Add the Minimal Z10 e-paper display` | `minimal,z10-eink` | device-class-optional | dri-devel |
| mp01-0014 `drm/panel: Add the Minimal Z10 e-paper display driver` | `panel-minimal-z10-eink` | device-class-optional | dri-devel |
| mp01-0016 `drm/mediatek: dsi: Meet the D-PHY clock lane minimums` | clock-lane trail and zero times at low data rates | SoC-common | the shared MT6789 series, then linux-mediatek |
| mp01-0024 `dt-bindings: display: mediatek: dsi: Add mediatek,vendor-link-timing` | the DT property | SoC-common | the shared MT6789 series, then dri-devel |
| mp01-0025 `drm/mediatek: dsi: Program the vendor link timing on request` | vendor word counts and data lane timings behind the property | SoC-common, DT-guarded | the shared MT6789 series, then linux-mediatek |
| mp01-0026 `arm64: dts: mediatek: mp01: Use the vendor DSI link timing` | sets the property | board | with the board DTS |

mp01-0009 to 0012 are SoC-common. They do nothing unless a board's DSI
endpoint has `data-lanes`, so the Q25 is unaffected. They are in the MP01
package rather than `linux-zinwa-q25` because the shared MT6789 series
that `research/mt6789/common-vs-board.md` proposes does not exist yet,
and adding them there would change the Q25 kernel package for no Q25
benefit. When the shared series is split out, move them into it in this
order. mp01-0013 and 0014 belong only to an MP01 kernel.

Notes for the board DTS and the design:

- `../eink-binding-note.md`: the nodes to write, which GPIOs are which, and the
  CPLD register map the driver keeps.
- `../eink-refresh-api.md`: the waveform and clear controls, the interim sysfs
  ABI, and the upstream DRM API it should become.
- `docs/design/EPAPER_DISPLAY_CLASS.md`: what the shell should do on an
  e-paper display, keyed off a display-class capability.

## Firmware safety

The vendor's `panel-z10-eink-i2c.c` carries the CPLD bitstream
(`panel-z10-eink-cpld-fw.h`). It erases and reprograms the CPLD's flash at
probe whenever the firmware version reads below 0x36 (and is not 0x25),
and whenever 9 is written to its `eink_cpld_registers` attribute.
Nothing from that path is in 0007. The driver reaches the CPLD only
through a regmap whose read table is 0x80, 0x84, 0x88-0x8d and 0x8f, and
whose write table is 0x8c and 0x8e. The code writes only 0-3 to 0x8c and
0x05 to 0x8e. The Pango configuration opcodes (0x10-0x12, 0x20-0x21,
0x30-0x31, 0x40, 0x50-0x53, 0x60, 0x70-0x71, 0xa1-0xa5, 0xff) fall outside
both tables, and nothing in the driver builds a raw I2C message except
the two regmap callbacks. Never send any of them by hand either:
ISC_ENABLE (0x53) alone freezes the CPLD's outputs (Pango UG030004).

## Compile test

The base was the extracted tree with all 138 linux-zinwa-q25 patches and
`config-zinwa-q25.aarch64`, plus `CONFIG_DRM_PANEL_MINIMAL_Z10_EINK=m`,
built with clang/LLVM=1. With W=1, `drivers/gpu/drm/mediatek/`,
`drivers/phy/mediatek/` and `drivers/gpu/drm/panel/` build with no
warnings, as they do on the unpatched base. No full `Image modules`
link was run, because it would hold the shared build lock for hours. All
of the panel module's undefined symbols are exported by the tree.
`checkpatch --strict` is
clean apart from 0006's usual "does MAINTAINERS need updating" (0007 adds
the entry). Both bindings pass `dt-doc-validate`. Their examples, and a
test DT with the MP01 nodes, pass `dt-validate`, and a bad lane number or
a stray `pm-enable-gpios` is rejected.

## Untested

None of this has run on an MP01. The things to check on hardware:

- The lane routing. The field layout is the vendor's, but the direction
  (logical to physical) only matters for permutations that are not their
  own inverse, and the MP01's 2/3 swap is its own inverse.
- Whether the CPLD accepts its reads as a write and then a separate read,
  as the vendor does them.
- The power-on order and delays (copied from the vendor), and whether
  powering the CPLD down on blank really keeps the picture.
- The bootloader handoff: no reset at the first prepare when the supplies
  are boot-on.
- What `refresh_mode` and `full_refresh` look like on the panel.
- The rotation value. Who owns GPIO12 is still open.
