# packaging/

Everything needed to turn this repo into a bootable Marathon image.
Merged in from `MarathonOS/Marathon-Image` on 2026-08-31; see
[`docs/MONOREPO_MIGRATION.md`](../docs/MONOREPO_MIGRATION.md) for the
rationale and the full history-preservation notes.

| Path | What |
|---|---|
| `packages/` | Alpine aports — `marathon-shell`, `marathon-base-config`, `postmarketos-ui-marathon`, `qmf`, `callaudiod`, the four `device-*-marathon` overlays, two kernels, `librem5-vivante-blobs` |
| `pipeline-patches/` | Patch series applied to upstream postmarketOS duranium, plus `bootstrap.sh` to stage a patched tree |
| `configs/` | System config drop-ins (sysctl, udev, limits, systemd) |
| `devices/` | Per-device kernel-config fragments, read by `packages/linux-marathon/APKBUILD` |
| `scripts/` | `build-cm5-pmbootstrap.sh` (the canonical HackberryPi CM5 path — duranium's UKI/erofs/verity chain does not boot Pi 5 firmware), its `push-cm5.sh` iteration loop, and `setup-librem5-recovery.sh` |
| `tools/` | `simg2img.py`, an Android sparse→raw converter for unpacking factory images |

## Building

Nothing here is invoked directly. The orchestrator is
[`scripts/build-image.sh`](../scripts/build-image.sh) at the repo root:

```sh
./scripts/build-qemu-image.sh          # or build-oneplus6 / build-librem5
```

It resolves this directory automatically. `MARATHON_IMAGE_DIR` still
overrides it if you need to point a build at an external packaging tree.

Per-aport rebuilds go through the builders in `scripts/qemu/lib/`, e.g.
`./scripts/qemu/lib/build-marathon-shell-apk.sh`.

See [`docs/BUILDING.md`](../docs/BUILDING.md) for a cold-clone walkthrough
and [`docs/IMAGE_BUILD_ARCHITECTURE.md`](../docs/IMAGE_BUILD_ARCHITECTURE.md)
for why the pipeline is shaped the way it is.

## Licensing

`LICENSE` here is MIT, inherited from Marathon-Image; the repo root is
Apache 2.0. Both are © Patrick Quinn. Unifying them is an open decision —
see `docs/MONOREPO_MIGRATION.md`.
