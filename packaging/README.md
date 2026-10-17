# packaging/

Everything needed to turn this repo into a bootable Marathon image.
Merged in from `MarathonOS/Marathon-Image` on 2026-08-31; see
[`docs/MONOREPO_MIGRATION.md`](../docs/MONOREPO_MIGRATION.md) for the
history.

| Path | What |
|---|---|
| `packages/` | Alpine aports (below) |
| `pipeline-patches/` | 33-patch series against upstream postmarketOS duranium, plus `bootstrap.sh` to stage a patched tree. Index: [`pipeline-patches/README.md`](pipeline-patches/README.md) |
| `duranium-overlay-extras/` | Non-patch files the duranium tree needs (the snapshot repo public key, a repack helper) |
| `devices/` | Kernel-config fragments read by `packages/linux-marathon/APKBUILD` (OnePlus 6 / SDM845, generic) |
| `configs/` | Older system config drop-ins (sysctl, udev, limits, systemd). Not referenced by the image build; the live copies are in `marathon-base-config` and `marathon-shell` |
| `scripts/` | `setup-librem5-recovery.sh` (Librem 5 uuu recovery rig), and the older pmbootstrap CM5 path (`build-cm5-pmbootstrap.sh`, `push-cm5.sh`), superseded by `scripts/build-hackberry-cm5-image.sh` |
| `tools/` | `simg2img.py`, an Android sparse-to-raw converter |

## Aports

| Group | Packages |
|---|---|
| Shell and system | `marathon-shell`, `postmarketos-ui-marathon`, `marathon-base-config`, `marathon-plymouth-theme`, `marathon-boot-logo` |
| UI framework | `keel-silica` (Sailfish Silica components for Qt 6), `keel-mcp` (MCP server for apps' Keel Actions) |
| Apps and services | `pacific` (browser), `wpewebkit`, `shoal-pilot` and `shoal-pilotd` (Pilot assistant), `marathon-mail-oauth`, `qmf` |
| Device overlays | `device-purism-librem5-marathon`, `device-pine64-pinephone-marathon`, `device-raspberry-pi5-marathon`, `device-hackberrypi-cm5-marathon` (layers on the Pi 5 overlay), `device-oneplus-enchilada-marathon` (dormant) |
| Kernels and boot | `linux-purism-librem5-marathon`, `linux-postmarketos-allwinner-marathon`, `u-boot-pinephone-marathon`, `linux-marathon` (SDM845) |
| Device support | `librem5-vivante-blobs`, `callaudiod`, `pinephone-callaudiod-marathon` |

`pacific`, `shoal-pilot*` and `keel-mcp` build from a local Shipwright
checkout (`PACIFIC_SRC`, `PILOT_SRC`, `KEEL_MCP_SRC`; default
`~/Developer/Shipwright`).

## Building

Nothing here is invoked directly. The orchestrator is
[`scripts/build-image.sh`](../scripts/build-image.sh), usually through a
wrapper:

```sh
./scripts/build-qemu-image.sh           # qemu-aarch64
./scripts/build-librem5-image.sh        # purism-librem5
./scripts/build-hackberry-cm5-image.sh  # raspberry-pi5 + HackberryPi overlay
./scripts/build-oneplus6-image.sh       # oneplus-enchilada
./scripts/build-image.sh pine64-pinephone
```

It finds this directory itself; `MARATHON_IMAGE_SRC` points a build at an
external packaging tree. It builds the apks in dependency order (cached by
`pkgver-pkgrel`), then the target's `device-<target>-marathon` overlay and
any `*-marathon` kernel or U-Boot fork the overlay depends on, then bakes the
image. Bump `pkgrel` in an aport for the change to reach the next image.

Per-aport builders live in `scripts/qemu/lib/`, e.g.
`./scripts/qemu/lib/build-marathon-shell-apk.sh`.

See [`docs/BUILDING.md`](../docs/BUILDING.md) for a cold-clone walkthrough
and [`docs/IMAGE_BUILD_ARCHITECTURE.md`](../docs/IMAGE_BUILD_ARCHITECTURE.md)
for how the pipeline is shaped.
