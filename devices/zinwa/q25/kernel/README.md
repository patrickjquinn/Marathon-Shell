`packaging/packages/linux-zinwa-q25` builds the Q25 kernel from ellyq's
`mtk_g99-mainline` at `978b8b67` with one `git format-patch` series and the
phone's configuration. The series is kept as clean, atomic patches for the
MT6789 tree and mainline; each patch's commit message carries its rationale.
docs/roadmap/Q25-UPSTREAM-PLAN.md lists what each patch replaces.

| Patches | What | Where it goes |
|---|---|---|
| `drm/mediatek: Add MT6789 display support` | MT6789 mmsys/DSI data on the MT8186 tables. | MT6789 tree, with linux-mediatek `880bc1cbf3a3` (W5). |
| `power: supply: bq256xx: ensure charging…` | Clears EN_HIZ, sets CHG_CONFIG at probe. | linux-pm (W9). |
| `pinctrl: mediatek: mt6789: guard the sleep PM ops` | Build fix. | Fold into ellyq's pinctrl patch. |
| `iio: adc: mt6359-auxadc: Include the ADC resolution…` | BATADC scale. | linux-iio, reconciled with mt6768-mainline `ca09cacace6d`. |
| `arm64: dts: … mt8781-zinwa-q25` (board, accepted boot, audio/sensors/CONNSYS, panel Doze, camera pool, MD1) | The board DT the phone boots, on upstream's `mt8781-zinwa-q25.dts`. | ellyq's DTS; vendor nodes to overlays (W19, section 4). |
| `mfd: mt6358: Fix AUD and MISC top interrupt status bits` | ACCDET irq storm. | Mainline (W10). |
| `dt-bindings: iio: imu: icm42600: …`, `iio: imu: inv_icm42607: …` | Backports of torvalds `e097c0108de9`, `22addefdabdf`, `2871c45d9469`…`87775fff21b1`. | Drop when the base passes v7.3. |
| `media: i2c: imx111: …`, `media: i2c: s5kjn1: …`, `iio: magnetometer: mmc5633: …` | Sensor fixes found on the Q25. | linux-media, linux-iio. |
| `pinctrl: mediatek: mt6789: Drop the unused EH driving table` | W=1 fix. | Fold into ellyq's pinctrl patch. |
| `dt-bindings: gnss: add MediaTek MT6789 CONNSYS GNSS`, `arm64: dts: … describe the GNSS receiver` | The GNSS node and its LNA pin states for `mtk-connsys-gnss`. | With the driver, to the MT6789 tree. |
| `arm64: dts: … Build with overlay symbols` | `-@` for the runtime camera overlay. | Drops with the camera overlay (W7). |
| `Input: synaptics-rmi4 - add support for reset gpios` (Roman Vivchar's RFC), `… hold reset while the sensor is off` | The touchscreen's reset line. | linux-input, with the RFC. |
| `clk: mediatek: mt6789: Parent the I2C wrapper gates to i2c_pseudo_ck` | The I2C clocks were orphans at 0 Hz. | MT6789 tree (W2). |
| `dt-bindings: power: …`, `pmdomain: mediatek: Add MT6789 power domains` | The SoC power domains, from linux-mediatek `a2a96be99f1b` with fixes. | MT6789 tree (W3). |
| `dt-bindings: watchdog: mediatek,mtk-wdt: Add MT6789`, `watchdog: mtk_wdt: …`, `arm64: dts: mediatek: mt6789: Make the TOPRGU a reset controller` | The CONN MCU reset. | linux-watchdog, MT6789 tree (W3). |
| `arm64: dts: … mt8781-zinwa-q25` (CONN MCU reset, GPU supplies, bootloader display, VBIF28, UFS VCC, modem rails, panel bias) | Owners for everything the bootloader leaves on, so the board boots without `*_ignore_unused`. | ellyq's DTS (W4). |
| `soc: mediatek: mtk-mutex: Defer until the mutex device has probed` | From linux-mediatek `3e6c84ec8051`. | linux-mediatek (W5). |
| `drm/mediatek: mtk_dsi: Stop the engine…`, `drm/mediatek: dsi: Register DSI host after…`, `drm/mediatek: mtk_dsi: Run the link at the peripheral's HS rate` | Taking over the DSI the bootloader left running, at the panel's 652 Mbit/s. | linux-mediatek (W5). |
| `dt-bindings: vendor-prefixes: Add Zinwa`, `dt-bindings: regulator: ti,tps65132: Add OCS OCP2131`, `dt-bindings: display: panel: …`, `drm/panel: Add Zinwa Q20 HD720 panel driver` | The panel and its bias supply. | dri-devel, linux-regulator, devicetree (W5). |
| `clk: mediatek: mt6789: Park the GPU mux during MFGPLL rate changes` | GPU DVFS. | MT6789 tree (W6). |

`0002-q25-private-mt6358-current-car-snapshot.patch` here is not part of the
series: it is the source of the diagnostic `q25-mt6358-live` module (H28) and
goes with the mt6358 gauge driver (W9).

The release is `7.0.0-q25`; `CONFIG_MODULE_UNLOAD` is on and every configured
module is built and shipped by the kernel package. The same build compiles
the Q25's out-of-tree modules (`packaging/packages/linux-zinwa-q25/modules`)
against the tree and ships them as `q25-kernel-modules`.
