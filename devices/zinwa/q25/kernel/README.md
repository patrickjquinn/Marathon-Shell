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

The release is `7.0.0-q25`; `CONFIG_MODULE_UNLOAD` is on and every configured
module is built and shipped by the kernel package. The same build compiles
the Q25's out-of-tree modules (`packaging/packages/linux-zinwa-q25/modules`)
against the tree and ships them as `q25-kernel-modules`.
