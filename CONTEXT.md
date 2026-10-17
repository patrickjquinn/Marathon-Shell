# Marathon Shell — Operational Context

Quick reference for building, flashing, driving and debugging Marathon.
`README.md` is the introduction; `docs/*.md` are the deep dives. If this
file disagrees with the tree, the tree wins — fix this file.

---

## 1. What this is

Marathon Shell is a Qt 6 / QML mobile shell and Wayland compositor in **one
process** (`marathon-shell-bin`), running on postmarketOS (Alpine) built
through duranium/mkosi. The shell process hosts the compositor, the scene
graph, all shell QML, the app launcher and window model, the app lifecycle
manager (cgroup v2 freezer), and the system service singletons (audio,
brightness, modem, Wi-Fi, location, ...). Apps run in their own processes
(`marathon-app-runner`, sandboxed with bwrap) and connect as Wayland clients.

The in-process compositor is treated as an advantage, not a debt.

The primary branch is **`main`**.

---

## 2. Hardware targets

Each device is described by `devices/<vendor>/<codename>/device.toml` (SoC
facts in `socs/<soc>.toml`, checked by `tools/devices/devices.py check`). Its
overlay in `packaging/packages/device-*-marathon` ships the
`/etc/marathon/device-profile.conf` generated from it (see
`docs/DEVICE_OVERLAYS.md`).

| Device              | Build target (`build-image.sh <target>`) | SoC / GPU                         | Display          | Status |
|---------------------|------------------------------------------|-----------------------------------|------------------|--------|
| Purism Librem 5     | `purism-librem5`                         | i.MX8MQ / Vivante GC7000L (etnaviv, GLES2) | 720x1440 | Primary phone |
| PINE64 PinePhone    | `pine64-pinephone`                       | Allwinner A64 / Mali-400 (lima, GLES2) | 720x1440    | Boots to OOBE; active |
| HackberryPi CM5     | `raspberry-pi5` + CM5 overlay (`build-hackberry-cm5-image.sh`) | BCM2712 / VideoCore VII (v3d) | HyperPixel 4 Square 720x720, BBQ physical keyboard | Active |
| Raspberry Pi 5 / CM5 (no enclosure) | `raspberry-pi5`          | BCM2712 / v3d                     | HDMI             | Base port for the CM5 overlay |
| QEMU aarch64        | `qemu-aarch64`                           | virtio-gpu-gl (virgl)             | 720x1440 default | Developer simulator |
| OnePlus 6           | `oneplus-enchilada`                      | SDM845 / Adreno 630               | 1080x2280        | Dormant (overlay untouched since 2026-09) |

### Hardware quirks (load-bearing)

- **etnaviv MSAA** — `layer.samples: 4` drops the Librem 5 to ~2 fps.
  Layer samples come from `GPU_MSAA` in the device profile (0 on the L5 and
  PinePhone, 4 on the Pi), overridable with `MARATHON_LAYER_SAMPLES`. Never
  hard-code `layer.samples`.
- **L5 audio default sink** — WirePlumber picks HDMI unless
  `50-marathon-l5-default-sink.conf` (in `device-purism-librem5-marathon`)
  raises the speaker sink's priority.
- **L5 disk layout** — `build-image.py` rebuilds the disk after mkosi: ext4
  boot partition at sector 4096 (512 MiB, label `pmOS_boot`) and
  `phone-boot.img` written at byte offset 33 KiB so the i.MX BootROM finds
  U-Boot. Raw `mkosi build` skips this and the image will not boot.
- **PinePhone disk layout** — pure MBR; `u-boot-sunxi-with-spl-528.bin`
  at 8 KiB; board DTBs copied to `allwinner/` on the ext4 boot partition.
- **Pi 5 / CM5 boot** — no UEFI. `build-image.py` converts the GPT to a pure
  MBR (FAT32 boot, type 0x0c, bootable; ext4 root `pmOS_root`), and
  `mkosi.finalize` stages `kernel_2712.img` + a plain-cpio `initramfs_2712`.
  `linux-rpi` is pinned to 6.12.85 (6.18.35 NULL-derefs in the initrd).
  `cgroup_enable=memory` must stay on the cmdline or the freezer and PSI are
  dead.
- **Power key** — handled by the shell's `PowerKeyListener`; device
  `logind.conf` files set `HandlePowerKey=ignore` so logind does not also act.
- **`QT_IM_MODULE`** — the shell runs with `none`; apps use `wayland`.
  `qtvirtualkeyboard` in the shell's environment kills the eglfs shell.

---

## 3. Process & session structure

- `greetd` runs `marathon-shell-session` as `user`. The session script sets
  the environment and execs the shell inside a `systemd-run --user --scope`
  under `marathon.slice` when that slice exists.
- The compositor socket is `$XDG_RUNTIME_DIR/marathon-wayland-0`
  (`MARATHON_WL_SOCKET_NAME` overrides).
- Wayland extensions beyond Qt: a vendored `zwp_linux_dmabuf_v1` v4 at
  `shell/src/wayland/linuxdmabufv1.{h,cpp}`; see `docs/WAYLAND_PROTOCOLS.md`.
- App lifecycle: warm runner pool, cgroup v2 freezer for backgrounded apps,
  oom_score_adj ladder. See `docs/NATIVE_APP_LIFECYCLE.md`.
- Mail: QMF 4.0.4 + `MailService` + the `marathonoauth`/`marathonclassic`
  credential plugins + the `marathon-mail-oauth` Rust helper.
- Rust services live in `crates/` (`marathon-weatherd`,
  `marathon-store-handler`, `marathon-core-native`).

---

## 4. Build pipeline

### Entry point

```bash
scripts/build-librem5-image.sh          # purism-librem5
scripts/build-hackberry-cm5-image.sh    # raspberry-pi5 + HackberryPi overlay
scripts/build-qemu-image.sh [--boot]    # qemu-aarch64
scripts/build-oneplus6-image.sh         # oneplus-enchilada
scripts/build-pinephone-image.sh        # pine64-pinephone
scripts/build-image.sh raspberry-pi5    # Pi 5 without the enclosure
```

All wrappers call `scripts/build-image.sh <target>`, which:

1. checks host tools (`scripts/qemu/lib/check-host.sh`);
2. runs `packaging/pipeline-patches/bootstrap.sh` to clone upstream duranium
   at the pinned commit and `git am` the patch series, plus a pinned mkosi;
3. builds Marathon's apks into `mkosi.packages/` (cached by
   `pkgver-pkgrel`; `FORCE_REBUILD=1` drops the cache);
4. runs duranium's `scripts/build-image.py device-<target> ui-marathon`,
   which runs mkosi and then the per-device disk surgery.

**Never** run raw `mkosi build`, and never call `build-image.py` by hand for
a device image — the wrappers stage the apks and overlays it needs.

### What lives where

- `~/.cache/marathon-build/duranium/` — the patched duranium tree
  (override the root with `MARATHON_BUILD_DIR`). It is **generated**: change
  it with a numbered patch in `packaging/pipeline-patches/`, never by editing
  it. Images land in `mkosi.output/<target>_marathon_edge/`.
- `packaging/pipeline-patches/` — 33 patches (0001–0034; there is no 0011)
  against duranium `394290c6`. Index in `packaging/pipeline-patches/README.md`.
- `packaging/packages/` — the Alpine aports (shell, base config, device
  overlays, kernel and U-Boot forks, QMF, Plymouth theme, Keel, Pacific,
  Pilot, ...). Bump `pkgrel` for every change you want in an image.
- `scripts/qemu/lib/build-*-apk.sh` — the per-aport builders the
  orchestrator calls.

---

## 5. Flashing & recovery

- **Librem 5** — `scripts/flash/flash-librem5.sh sd /dev/sdX <image.raw>` or
  `scripts/flash/flash-librem5.sh emmc <image.raw>` (uuu SDP → fastboot). The
  uuu script needs both the SDPU and SDPS stages; if uuu hangs near 97 %, one
  is missing. `phone-boot.img` is extracted next to the image by
  `build-image.sh`. The recovery rig (uuu + Jumpdrive + a pmOS phosh image)
  lives at `~/librem5-recovery/`, reproducible with
  `packaging/scripts/setup-librem5-recovery.sh`.
- **Pi 5 / HackberryPi CM5** — `scripts/flash/flash-hackberry-cm5.sh /dev/sdX`
  picks the newest `raspberry-pi5_marathon_edge_*.raw` and `dd`s it. The root
  partition grows to fill the card on first boot.
- **PinePhone** — `scripts/flash/flash-pinephone.sh /dev/sdX` writes the
  newest `pine64-pinephone_marathon_edge_*.raw` to a microSD, or to the eMMC
  JumpDrive exposes; it refuses an image without the MBR + 8 KiB SPL layout.
- **OnePlus 6** — `scripts/flash/flash-oneplus6.sh` (fastboot). Unverified on
  recent images.
- **QEMU** — `scripts/build-qemu-image.sh --boot`, or `--boot-only` to boot
  the last bake.

See `scripts/flash/README.md` for each script's details.

---

## 6. Driving the device

### SSH

```bash
sshpass -p marathon ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null root@marathon.local
```

`marathon.local` comes from avahi. Over USB networking the device is
`172.16.42.1` (the default in `scripts/hot-deploy.sh`).

### Credentials (dev images)

| Context                     | Value      |
|-----------------------------|------------|
| `root` / `user` SSH password | `marathon` |
| OOBE / lock-screen PIN      | `027602`   |

### The `marathon` CLI

`scripts/marathon` is the device driver: build, deploy, snap, unlock,
launch, logs, doctor. Reference: `docs/DEV_CLI.md`.

### Restarting the shell

```bash
ssh root@marathon.local 'systemctl restart greetd'
```

Never `pkill marathon-shell`: it leaves the Wayland socket half-deleted and
later app launches fail.

### Screenshots

```bash
scripts/device-snap.sh <label>     # → $MARATHON_SNAP_DIR/<label>.png
MARATHON_HOST=<ip> scripts/device-snap.sh <label>
```

Sends `SIGUSR1` to the shell, waits for `/tmp/marathon-shot.png` to be
complete, copies it back and re-encodes it. Don't read `fb0`; the shell
renders through DRM/KMS.

### Logs

- Shell: `journalctl -t marathon-shell` (the session pipes the shell through
  `systemd-cat --identifier=marathon-shell`). Release builds compile out
  `qDebug`/`qInfo`, so only warnings and above appear. `MARATHON_DEBUG=1` in
  the session enables full logging rules, but only a non-Release build has
  the debug/info output to show.
- The shell also appends to `~/.marathon/crash.log` (for `user`:
  `/home/user/.marathon/crash.log`).
- Other Marathon services: `journalctl -u <unit>` or `journalctl --user -u
  <unit>`.

---

## 7. Hot-deploy loop

A full image is 10–20 minutes. For iteration on a flashed device:

```bash
scripts/hot-deploy.sh            # push apps/* to /usr/share/marathon-apps, bust QML cache, restart greetd
scripts/hot-deploy.sh --bin      # also push build/marathon-shell-bin
```

Shell QML is compiled into the binary, so shell QML changes need `--bin`
(or a new apk). App QML pushed to disk can still be shadowed by the compiled
module; when in doubt, ship the apk.

---

## 8. Design system & visual validation

- `docs/UI_DESIGN_SYSTEM.md` is the design-system reference; check it before
  adding tokens, motion or chrome.
- The AI "sparkles" glyph is banned. OOBE shows the Marathon mark.
- A QML redesign is validated by a screenshot compared with the design
  (`scripts/device-snap.sh`, or `scripts/visual-validate.sh` on the host),
  not by lint and build.
- Host-side QML previews need `MARATHON_FORCE_DPI=160`; otherwise the host
  DPI overflows the 540x1140 design canvas.

---

## 9. Coding rules & commits

- Follow `docs/CODING_RULES.md` sections A–G and cite rule IDs in reviews and
  commit bodies.
- No generated-by or co-author trailers on commits.
- Small, atomic commits.
- Anchor every `tar` extract with `-C <dest>`.

---

## 10. Common foot-guns

| Symptom                                    | Cause / fix |
|--------------------------------------------|-------------|
| App launches fail after a restart          | The shell was `pkill`ed. Restart greetd instead. (§6) |
| Image flashes but won't boot               | Raw `mkosi build` skipped the disk surgery. Use the wrappers. (§4) |
| Build ignores your edit to the duranium tree | The tree is generated. Write a pipeline patch. (§4) |
| Shell QML change "didn't land"             | Shell QML is in the binary; use `hot-deploy.sh --bin`. (§7) |
| uuu hangs near 97 %                        | Missing SDPU/SDPS stage. (§5) |
| Librem 5 has no audio                      | Default sink is HDMI; device overlay rule missing. (§2) |
| Host QML preview oversized                 | Missing `MARATHON_FORCE_DPI=160`. (§8) |
| Shell drops to ~2 fps after a QML change   | Hard-coded `layer.samples`. (§2) |
| Shell dies when the keyboard opens         | `QT_IM_MODULE=qtvirtualkeyboard` reached the shell. (§2) |
| No debug lines in the journal              | Release build; only warnings are compiled in. (§6) |

---

## 11. Path reference

### Source tree

| Path | What |
|------|------|
| `shell/` | Shell C++ (`shell/src/`) and QML (`shell/qml/`). `shell/main.cpp` is the entry. |
| `apps/` | Bundled QML apps. |
| `marathon-silica/` | `Marathon.Silica`: Keel's Silica plus accessibility, keyboard operation and missing components. |
| `marathon-core/`, `marathon-services/` | Shared libraries and services. |
| `crates/` | Rust workspace (`marathon-weatherd`, `marathon-store-handler`, `marathon-core-native`). |
| `tools/` | `marathon-app-runner`, `marathon-webview-runner`, `marathon-sandbox`, `marathon-mail-oauth`, ... |
| `scripts/` | Build wrappers, `marathon` CLI, `device-snap.sh`, `hot-deploy.sh`, `flash/`, `qemu/`. |
| `packaging/` | aports, pipeline patches, configs. See `packaging/README.md`. |
| `docs/redesign/` | JSX design references. |

### Build cache

| Path | What |
|------|------|
| `~/.cache/marathon-build/duranium/` | Patched duranium tree (generated). |
| `~/.cache/marathon-build/duranium/mkosi.packages/` | Locally built apks. |
| `~/.cache/marathon-build/duranium/mkosi.output/<target>_marathon_edge/` | Built images. |
| `~/.cache/marathon-build/mkosi-src/` | Pinned mkosi checkout. |

### On the device

| Path | What |
|------|------|
| `/usr/bin/marathon-shell-bin` | Shell binary. |
| `/usr/bin/marathon-shell-session` | Session script greetd runs. |
| `/etc/marathon/device-profile.conf` | Device traits read by `DeviceProfile`, generated from `devices/`. |
| `/usr/share/marathon-apps/<app>/` | App files. |
| `/home/user/.cache/marathon-qml/` | QML disk cache. |
| `/home/user/.marathon/crash.log` | Shell log file. |
| `/tmp/marathon-shot.png` | Latest `SIGUSR1` screenshot. |

### Environment variables

| Variable | Purpose |
|----------|---------|
| `MARATHON_FORCE_DPI` | Fix the DPI (160 for host previews; device profiles set their own). |
| `MARATHON_LAYER_SAMPLES` | Override the device profile's MSAA sample count. |
| `MARATHON_DEBUG=1` | Full Qt logging rules in the session. |
| `MARATHON_BUILD_DIR` | Build cache root (default `~/.cache/marathon-build`). |
| `FORCE_REBUILD=1` | Rebuild every apk. |
| `MARATHON_HOST`, `MARATHON_SNAP_DIR` | Target and output for `device-snap.sh`. |
| `MARATHON_WL_SOCKET_NAME` | Compositor socket name. |

---

## 12. Where to look next

- `docs/ARCHITECTURE.md` — shell process model
- `docs/BUILDING.md` — cold-clone build walkthrough
- `docs/IMAGE_BUILD_ARCHITECTURE.md` — how the image pipeline is shaped
- `docs/DEVICE_SUPPORT.md`, `docs/DEVICE_OVERLAYS.md` — devices and porting
- `docs/NATIVE_APP_LIFECYCLE.md`, `docs/NATIVE_APP_THEMING.md`,
  `docs/NATIVE_APP_SCALE.md` — native and Flatpak apps
- `docs/WAYLAND_PROTOCOLS.md`, `docs/UI_DESIGN_SYSTEM.md`,
  `docs/CODING_RULES.md`
