# Marathon Shell — Operational Context

Operational quick-reference for driving, building, flashing, debugging and visually
validating Marathon Shell. Companion to `README.md` (intro) and `docs/*.md` (deep
dives). If something here drifts from the live tree, the tree wins — but tell
someone, because this doc is supposed to be authoritative.

---

## 1. What this is

Marathon Shell is a Qt6/QML mobile shell + Wayland compositor in **one process**,
running on top of Alpine + duranium. It is the foreground of a "real phone OS"
target: lockscreen → home → app grid → per-app windows → quick settings → status
bar → keyboard → notifications, all rendered by `marathon-shell-bin`.

In-process compositor is treated as a UX advantage, not a debt.

Primary branch for in-flight UX work: **`ux-overhaul`**. Never merge straight to
`main`; that gate is human-controlled.

---

## 2. Hardware targets

| Device          | SoC            | GPU                    | Display       | Status                  |
|-----------------|----------------|------------------------|---------------|-------------------------|
| Librem 5        | i.MX8MQ        | Vivante GC7000Lite GLES2 | 720x1440      | Primary mobile target   |
| HackberryPi CM5 | BCM2712 (Pi 5) | VideoCore VII (v3d) GLES3 | HyperPixel 720x720 | Fallback dev hardware |
| QEMU (aarch64)  | virt           | virgl (CPU fallback)   | 540x1140 sim  | Dev simulator           |

### Hardware quirks (load-bearing)

- **L5 etnaviv MSAA trap** — `layer.samples: 4` collapses to ~2 fps on GC7000Lite.
  Every `layer.samples` in the shell must be gated on the `MARATHON_LAYER_SAMPLES`
  env (default 4, overridden to 0 on L5).
- **L5 GLES2 ceiling** — no GLES3 until Mesa 26.2. WebEngine HW accel needs
  `bwrap` allowing only `renderD128`, `MESA_LOADER=etnaviv`, and
  `WLR_RENDER_DRM_DEVICE` set.
  WPE WebKit + WPEBackend-fdo is the strategic bridge.
- **L5 input devices** — `event0=gpio-keys`, `event1=bd718xx-pwrkey`,
  `event2=pwm-vibrator`, `event3=snvs-powerkey`. KEY_POWER lives on bit 52 of
  the EV_KEY mask, which is why the bare `KEY=...` line lists `10000000000000 0`.
- **L5 audio default sink** — wireplumber picks HDMI by default; without the
  Marathon priority rule (`50-marathon-l5-default-sink.conf` baked into the
  `device-purism-librem5-marathon` aport) the device has zero audio. The rule
  bumps `HiFi__Speaker__sink` priority to 2000.
- **L5 partition surgery** — ext4 boot partition at sector 4096, label
  `pmOS_boot`. The phone-boot.img blob is `dd`'d to byte offset 33 KiB
  (33792 bytes) on the disk so the i.MX BootROM finds the IVT (Image Vector
  Table, tag byte `0xd1`) where it expects it. This is what `build-image.py`
  does that raw `mkosi build` doesn't.
- **Pi 5 boot path** — pure MBR + FAT16 + 0x0e bootable + ext4 root labelled
  `pmOS_root` + no-splash cmdline + pre-populated `/etc`. Drop any one and the
  CM5 silently doesn't boot. Full recipe in
- **Display blanking** — `/sys/class/graphics/fb0/blank` going to 4 (POWERDOWN)
  is the kernel idle path, not our suspend path. Power-key handling lives in
  the shell's `PowerKeyListener`; `systemd-logind` is set to
  `HandlePowerKey=ignore` so it does NOT also fire.
- **QT_IM_MODULE** — shell process uses `none` (eglfs is single-window, the
  `qtvirtualkeyboard` IM plugin spawns a Raster QWindow and fails the eglfs
  XOR check). App clients use `wayland`. Propagated correctly via the systemd
  scope env passthrough.

---

## 3. Process & compositor structure

- `greetd` starts `marathon-shell` via a `systemd-run` scope, not a unit. Scope
  inherits `marathon.slice` resource controls and is recreated on every login.
- The shell process hosts: the Wayland compositor, scene graph, all QML, the
  app launcher, the per-app windowing model, AppLifecycleManager (cgroup v2
  freezer), every QML singleton/service (audio, brightness, modem, wifi, etc.),
  WebEngine (when running), and the SIGUSR1 screenshot handler.
- Wayland protocols beyond what Qt 6 ships: a vendored
  `zwp_linux_dmabuf_v1 v4` with `main_device` feedback lives at
  `shell/src/wayland/linuxdmabufv1.{h,cpp}` (~445 LOC). Eliminated the
  QRhi/dmabuf null-texture failures end-to-end.
- **Stdio** — shell stdout/stderr routes to the greetd pipe, NOT journald, which
  is why `journalctl -u marathon-shell` is empty when you want it most. To see
  `qDebug`/`qWarning` output, run the shell binary manually under SSH with
  `QT_LOGGING_RULES='*=true'` and pipe to a file.
- **Mail backend** — QMF 4.0.4 + `MailService` QML singleton +
  `marathonoauth`/`marathonclassic` credential plugins + the
  `marathon-mail-oauth` Rust helper — all baked into the duranium image.

---

## 4. Build pipeline

### Canonical build entry (the only entry)

```bash
cd ~/duranium-build/duranium
./scripts/build-image.py device-purism-librem5-marathon ui-marathon --release=edge
# or for Pi 5:
./scripts/build-image.py device-hackberrypi-cm5-marathon ui-marathon --release=edge
```

**Never** run raw `mkosi build`. It skips L5 partition surgery (ext4 boot at
sector 4096, phone-boot.img dd'd to byte 33 KiB / 0xd1 IVT header) and the
Pi MBR rewrite. The device will not boot.

### What lives where

- `~/duranium-build/duranium/` — upstream duranium clone, pinned at commit
  `394290c6`. Marathon's divergence is a 16-patch series applied by
  `bootstrap.sh`.
- `packaging/packages/` — Alpine APKBUILDs for every Marathon component
  (shell, ui controls, device tunings, app images, mail helper, etc.). Bump
  `pkgrel` per release; the orchestrator picks up the new APK at image bake.
- `packaging/pipeline-patches/` — the patch series against duranium
  upstream. If you need to edit duranium's mkosi config, edit a patch here.

### Stable image references

The current known-good L5 image is bookkept in
`project_r180_stable_image.md` with the absolute path under
`~/duranium-build/duranium/mkosi.output/.../*.raw` and the flash command.

---

## 5. Recovery & flashing

### Librem 5 (uuu)

Recovery rig lives at `~/librem5-recovery/`: `uuu` + Jumpdrive 0.8 + pmOS phosh
reset image. Reproducible from a clean host with
`scripts/setup-librem5-recovery.sh`. Notes:

- The GCC 15 `<cstdint>` patch and `libstdc++-static` are load-bearing for the
  current uuu build.
- `scripts/flash/flash-librem5.sh` must include both **SDPU** and **SDPS** stages
  from the canonical pmaports script — if uuu hangs at ~97% you are almost
  certainly missing one of them.

Hold VOLUME-UP while plugging USB-C to enter serial-download. uuu autodetects.

### Pi 5 (HackberryPi CM5) — SD card

`./scripts/build-image.py device-hackberrypi-cm5-marathon ...` produces a `.raw`.
Flash with `dd` (or balenaEtcher) to the SD card. First boot regenerates SSH
host keys; `marathon.local` resolves via avahi.

### Recovery to pmOS

If Marathon won't boot at all, the canonical recovery path is the pmOS phosh
reset image staged in `~/librem5-recovery/`. Flash that, confirm phosh boots,
then re-flash a Marathon image.

---

## 6. Driving the device

### SSH

```bash
sshpass -p marathon ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  root@marathon.local
```

- Hostname `marathon.local` (mDNS via avahi) — works over USB-OTG and Wi-Fi.
- Fallback IP for USB CDC NCM cold boot: `192.168.0.10`.
- Pi 5: same `root@marathon.local`.

### Credentials

| Account / context        | Value          |
|--------------------------|----------------|
| L5 / Pi 5 `root` SSH pw  | `marathon`     |
| L5 / Pi 5 `user` SSH pw  | `marathon`     |
| OOBE / lockscreen PIN    | `027602`       |
| Fedora host sudo         | see `~/.marathon-secrets/askpass.sh` |

Host sudo is surfaced via `~/.marathon-secrets/askpass.sh`. On every session,
restore to `/tmp/askpass.sh` (chmod 700) — `/tmp` is tmpfs on Fedora.

### Restart procedure

```bash
sshpass -p marathon ssh root@marathon.local 'systemctl restart greetd'
```

**Never** `pkill marathon-shell` or `pkill -f marathon-shell-bin`. It leaves the
Wayland socket half-deleted, and every subsequent app launch fails with
`error: socket /run/user/0/wayland-1 already exists`.

### Screenshotting

```bash
scripts/device-snap.sh <label>
# → $MARATHON_SNAP_DIR/<label>.png
#   (default: $TMPDIR/marathon-snaps)
# Override with: MARATHON_SNAP_DIR=/some/dir scripts/device-snap.sh foo
# Override host: MARATHON_HOST=192.168.0.10  scripts/device-snap.sh foo
```

The script does the right thing: SSH, `kill -USR1 $(pgrep marathon-shell-bin)`,
poll `/tmp/marathon-shot.png` on the device until it's size-stable AND ends
with the PNG IEND CRC marker (`ae426082`), scp to host, re-encode via
ImageMagick to a clean sRGB/RGBA baseline file the Read tool accepts.

- Never read `fb0` — the shell uses eglfs/DRM, fbdev is a black hole.
- Never inline base64 PNGs — pull as a file, then `Read` it.
### Logs

- Shell stdio: NOT in journald. Either restart the shell manually under SSH
  with `QT_LOGGING_RULES='*=true' MARATHON_FORCE_DPI=160 ./marathon-shell-bin
  2>&1 | tee /tmp/shell.log`, or scrape the greetd pipe if you can find the FD.
- Other Marathon services: `journalctl -u <unit>` works normally.

---

## 7. Hot-deploy iteration loop

A full image bake is ~10-20 min. For QML / shell C++ iteration on an
already-flashed device, push the deltas and restart greetd:

```bash
# 1. Shell binary (only when C++ changed)
sshpass -p marathon scp build/shell/marathon-shell-bin \
  root@marathon.local:/usr/bin/

# 2. Shell libs (when shell libs changed)
sshpass -p marathon scp build/lib*.so* root@marathon.local:/usr/lib/

# 3. MarathonUI Controls QML — easiest thing to forget
sshpass -p marathon scp marathon-ui/Controls/*.qml \
  root@marathon.local:/usr/lib/qt6/qml/MarathonUI/Controls/
# Also push Core/ Theme/ Effects/ when changed.

# 4. Bust the QML disk cache
sshpass -p marathon ssh root@marathon.local \
  'rm -rf /home/user/.cache/marathon-qml /root/.cache/marathon-qml'

# 5. Restart
sshpass -p marathon ssh root@marathon.local 'systemctl restart greetd'

# 6. Verify
scripts/device-snap.sh <label>
```

Editing `marathon-ui/Controls/MQSTile.qml` on disk DOES NOT propagate without
step 3 — the shell binary baked a `qmldir` at build time, but at runtime QML
is loaded from `/usr/lib/qt6/qml/MarathonUI/...`.

The per-app variant (the qrc-shadow trick where disk pushes to
`/usr/share/marathon-apps/<app>/` are ignored until you also strip
`prefer :/qrc/...` from the per-app qmldir) is documented at

---

## 8. Design system & visual validation

### Tokens (Marathon DS)

- `MSpacing` — xs=5, sm=10, md=16, lg=20, xl=32
- `MRadius`  — sm=2, md=4, lg=6, xl=8, pill=999
- `MTypography` — sizeEyebrow=11, sizeCaption=12, sizeFootnote=13, sizeBody=17, sizeTitle3=22
- `MColors` — marathonTealBright `#1de9b6`, marathonTealDark, tealBorder,
  elev1 `#0a` (alpha), elev2 `#12`, elev3 `#1c`, textPrimary, whiteOverlay08/16
- Primitives — `MCard` (double-edge stroke + drop shadow), `MGlass`
  (backdrop blur), `MShadow`, `MGlow`, `MText` (Sora 200 parity), `MTopHairline`

The full spec lives in `docs/UI_DESIGN_SYSTEM.md`. The
`docs/redesign/ds-qml-guide.jsx` reference (Marathon QML Guide) is the source
of truth for any net-new component.

### Banned glyph

The AI-sparkle / "sparkles" Lucide icon is banned everywhere in Marathon.
OOBE first screen must show the Marathon product mark.

### Visual validation

For any QML redesign: launching + lint + build is NOT validation. You must
`scripts/device-snap.sh` and diff against the source design.

For host-side previews of QML, **always** export `MARATHON_FORCE_DPI=160`
before running. Without it, host DPI inflates `scaleFactor` and design-px
tokens overflow the locked 540×1140 canvas — the code is correct, the test is
wrong.

---

## 9. Coding rules & commit hygiene

- Follow `docs/CODING_RULES.md` sections A–G (anti-slop, Qt/QML anti-patterns,
  atomic commits). Cite rule IDs in review and commit bodies.
- **No generated-by / co-author trailers on commits.** Ever. Commit
  messages are human attribution.
- Atomic commits. One conceptual change per commit. Squash WIP locally.
- For `tar` extracts during build / overlay assembly, always anchor with
  `tar -C <dest>` — never rely on cwd. Prevents apk extracts from overwriting
  source.

---

## 10. Common foot-guns / gotchas

| Symptom                                          | Root cause / fix                                                                 |
|--------------------------------------------------|----------------------------------------------------------------------------------|
| Apps fail to launch after a restart              | You ran `pkill marathon-shell`. Reboot, never pkill. (§6)                       |
| Image flashes but won't boot                     | You ran raw `mkosi build` instead of `build-image.py`. (§4)                     |
| QML change "didn't land" on device               | Forgot step 3 or 4 in the hot-deploy loop. (§7)                                 |
| uuu hangs at ~97% flash                          | Missing SDPU+SDPS stages in flash-librem5.sh. (§5)                              |
| Marathon has zero audio                          | Default sink is HDMI; wireplumber rule missing or aport not rebuilt. (§2)       |
| Visual test on host looks wrong (oversized)      | Forgot `MARATHON_FORCE_DPI=160`. (§8)                                           |
| Shell drops to 2fps after a QML tweak            | New `layer.samples` not gated on `MARATHON_LAYER_SAMPLES`. (§2)                 |
| Soft keyboard crashes shell                      | `QT_IM_MODULE=qtvirtualkeyboard` propagated to shell. Shell must use `none`. (§2) |
| `journalctl -u marathon-shell` is empty          | Shell stdio routes to greetd pipe, not journald. Run manually under SSH. (§6)   |
| `marathon.local` doesn't resolve                 | Cold-boot mDNS not up yet. Fall back to `192.168.0.10`. (§6)                    |
| PNG from screenshot rejected by Read tool        | Use `scripts/device-snap.sh` — it re-encodes through magick. (§6)               |
| Browser/Maps/WebEngine renders black             | etnaviv GLES2 vs Chromium GLES3 + dmabuf-v3 ceiling. See WPE / dmabuf-v4 work.  |
| OOBE first screen shows sparkles                 | Banned glyph snuck in. Replace with Marathon product mark. (§8)                 |

---

## 11. Path reference

### Repos / source trees

| Path                                              | What it is                                                        |
|---------------------------------------------------|-------------------------------------------------------------------|
| `~/Developer/Marathon-Shell/`                     | This repo. Shell C++ + QML, MarathonUI Controls, scripts.         |
| `~/Developer/Marathon-Shell/shell/`               | Shell C++ source. Wayland glue at `shell/src/wayland/`.           |
| `~/Developer/Marathon-Shell/marathon-ui/`         | MarathonUI QML modules: `Core/`, `Theme/`, `Effects/`, `Controls/`. |
| `~/Developer/Marathon-Shell/tools/marathon-webview-runner/` | WPE WebKit runner (Phase 2 validated). `main.cpp` is the dmabuf bridge entry. |
| `~/Developer/Marathon-Shell/scripts/`             | Host-side scripts. `device-snap.sh`, `flash/`, `qemu/automation/`. |
| `~/Developer/Marathon-Shell/docs/redesign/`       | JSX source-of-truth for next-gen surfaces (incl. `ds-qml-guide.jsx`). |
| `~/Developer/Marathon-Shell/packaging/packages/` | 15 APKBUILDs (shell, ui controls, device tunings, app images, mail helper, etc.). |
| `~/Developer/Marathon-Shell/packaging/pipeline-patches/`| 16-patch series applied by bootstrap.sh against duranium `394290c6`. |
| `~/Developer/Marathon-Shell/packaging/devices/`  | Per-device config (L5, CM5, OnePlus 6, QEMU).                     |
| `~/Developer/Marathon-Shell/packaging/scripts/`  | `setup-librem5-recovery.sh`, `build-cm5-pmbootstrap.sh`, `push-cm5.sh`, `sync-and-build-marathon.sh`, plus older `build-rootless-*.sh` variants (use `build-image.py` instead). |
| `~/duranium-build/`                               | Build root. Not a repo itself — holds vendored duranium + mkosi.  |
| `~/duranium-build/duranium/`                      | Upstream duranium clone, pinned at `394290c6` + Marathon patches. |
| `~/duranium-build/duranium/scripts/build-image.py` | **Canonical build entry.** Always invoke via this.                |
| `~/duranium-build/duranium/mkosi.images/`         | mkosi image definitions (per-image dirs).                         |
| `~/duranium-build/duranium/mkosi.repart/`         | Partition layouts (incl. `mkosi.repart.librem5/`).                |
| `~/duranium-build/duranium/mkosi.profiles/`       | Profile overlays (ui-marathon, device-purism-librem5-marathon, …).|
| `~/duranium-build/duranium/mkosi.output/purism-librem5-marathon_marathon_edge/` | Where L5 `.raw` images land.       |
| `~/duranium-build/duranium/mkosi.output/raspberry-pi5-marathon_marathon_edge/` | Where Pi 5 `.raw` images land. (See `r180_stable_image` memory for the bookmark file path.) |
| `~/duranium-build/duranium/pmaports/`             | duranium-pinned pmaports tree (Alpine `device/`, `main/`, `modem/`, `cross/`). |
| `~/duranium-build/mkosi-src/`                     | Vendored mkosi source — sometimes the build pulls from here rather than the system mkosi. |
| `~/.local/var/pmbootstrap/`                       | pmbootstrap config + state.                                       |
| `~/.local/var/pmbootstrap-work/`                  | pmbootstrap chroot caches (`cache_apk_aarch64`, `cache_ccache_aarch64`, distfiles, ccache, rust, go, sccache). |
| `~/.local/var/pmbootstrap-venv/`                  | Python venv for pmbootstrap.                                      |
| `~/.local/var/pmbootstrap-git/`                   | Git clones pmbootstrap manages (kernel etc.).                     |
| `~/.cache/mkosi/`                                 | mkosi's own cache.                                                |

### Recovery / flashing

| Path                                              | What it is                                                        |
|---------------------------------------------------|-------------------------------------------------------------------|
| `~/librem5-recovery/`                             | uuu rig for the Librem 5. Reproducible from `setup-librem5-recovery.sh`. |
| `~/librem5-recovery/mfgtools/`                    | Built uuu binary lives here.                                      |
| `~/librem5-recovery/mfgtools-build/`              | uuu build tree (GCC 15 cstdint patch + libstdc++-static applied).  |
| `~/librem5-recovery/boot-purism-librem5.sh`       | Jumpdrive boot stage 1 (host → uuu → device into mass-storage).   |
| `~/librem5-recovery/u-boot-librem5.bin`           | Jumpdrive u-boot.                                                 |
| `~/librem5-recovery/kernel-librem5.gz`            | Jumpdrive kernel.                                                 |
| `~/librem5-recovery/initramfs-purism-librem5.gz`  | Jumpdrive initramfs.                                              |
| `~/librem5-recovery/dtbs/`                        | DTBs for Jumpdrive.                                               |
| `~/librem5-recovery/purism-librem5.lst` + `purism-librem5.tar.xz` | uuu manifest + payload bundle.                     |
| `~/librem5-recovery/20260620-0010-postmarketOS-edge-phosh-29-purism-librem5.img.xz` | pmOS phosh reset image (full-OS fallback). |
| `~/Developer/Marathon-Shell/scripts/flash/flash-librem5.sh`     | Marathon's L5 flash wrapper. Must include SDPU + SDPS stages.    |
| `~/Developer/Marathon-Shell/scripts/flash/flash-hackberry-cm5.sh` | Pi 5 / HackberryPi CM5 SD-card flash.                          |
| `~/Developer/Marathon-Shell/scripts/flash/flash-hackberry-pi.sh` | Earlier HackberryPi variants.                                   |
| `~/Developer/Marathon-Shell/scripts/flash/flash-oneplus6.sh`    | OnePlus 6 (legacy target).                                       |

### Secrets

| Path                                              | What it is                                                        |
|---------------------------------------------------|-------------------------------------------------------------------|
| `~/.marathon-secrets/askpass.sh`                  | Persistent sudo askpass (prints the host sudo password). Source of truth — read it from there, never inline it here. |
| `/tmp/askpass.sh`                                 | Session copy (chmod 700). Restore on every session (tmpfs).       |
| `~/.marathon-secrets/marathon-snapshot@local-1.rsa` + `.pub` | Snapshot repo signing key + pubkey.                  |
| `~/.marathon-secrets/SKYZMTGV.nmconnection.raw`   | Test Wi-Fi NetworkManager keyfile.                                |

### On-device paths

| Path on device                                    | What it is                                                        |
|---------------------------------------------------|-------------------------------------------------------------------|
| `/usr/bin/marathon-shell-bin`                     | Shell binary.                                                     |
| `/usr/lib/qt6/qml/MarathonUI/Controls/`           | MarathonUI Controls QML (push deltas here for hot-deploy).        |
| `/usr/lib/qt6/qml/MarathonUI/{Core,Theme,Effects}/` | Other MarathonUI modules.                                       |
| `/usr/share/marathon-apps/<app>/`                 | App QML on disk (qrc-shadowed unless qmldir patched — see hot-deploy QRC trick memory). |
| `/home/user/.cache/marathon-qml/`                 | User-side QML compile cache (bust on hot-deploy).                 |
| `/root/.cache/marathon-qml/`                      | Root-side QML compile cache (bust on hot-deploy).                 |
| `/etc/wireplumber/wireplumber.conf.d/50-marathon-l5-default-sink.conf` | Default-sink priority rule (Speaker > HDMI). Source: `packaging/packages/device-purism-librem5-marathon/`. |
| `/etc/udev/rules.d/90-marathon-modem-wakeup.rules` | Modem USB power/wakeup rule (see L5 wakeup memory).             |
| `/tmp/marathon-shot.png`                          | Where the SIGUSR1 handler writes the latest screenshot.           |
| `/run/user/0/wayland-1`                           | Wayland socket. Killing the shell with `pkill` half-deletes this. |

### Useful env vars

| Variable                       | Purpose                                                          |
|--------------------------------|------------------------------------------------------------------|
| `MARATHON_FORCE_DPI=160`       | Lock `scaleFactor` for visual checks on host.                    |
| `MARATHON_LAYER_SAMPLES=0`     | Disable QML `layer.samples` MSAA on etnaviv (L5).                |
| `MARATHON_OOBE_START_PAGE=<n>` | Jump OOBE to a specific page for screenshot audits.              |
| `MARATHON_SNAP_DIR=<dir>`      | Where `device-snap.sh` writes PNGs.                              |
| `MARATHON_HOST=<host-or-ip>`   | Override the SSH target for `device-snap.sh` (default `marathon.local`). |
| `QT_LOGGING_RULES='*=true'`    | Verbose Qt logging when running the shell manually under SSH.    |
| `QT_IM_MODULE=none`            | For the shell process (eglfs single-window).                     |
| `QT_IM_MODULE=wayland`         | For app clients (so the soft keyboard works).                    |
| `MESA_LOADER=etnaviv`          | For WebEngine HW-accel via bwrap (L5).                           |
| `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128` | For WebEngine HW-accel via bwrap (L5).               |

### Other useful scripts

| Path                                              | What it does                                                       |
|---------------------------------------------------|--------------------------------------------------------------------|
| `~/Developer/Marathon-Shell/scripts/device-snap.sh` | SIGUSR1 screenshot → IEND-stable poll → magick re-encode → host.  |
| `~/Developer/Marathon-Shell/scripts/qemu/automation/` | QEMU drive harness for matrix scenarios.                         |
| `~/Developer/Marathon-Shell/scripts/qemu/verify-cm5-boot-artifacts.sh` | Sanity-check CM5 boot artifacts before flashing.       |
| `~/Developer/Marathon-Shell/packaging/scripts/setup-librem5-recovery.sh` | Reproduce `~/librem5-recovery/` from a clean host.        |
| `~/Developer/Marathon-Shell/packaging/scripts/build-cm5-pmbootstrap.sh` | Legacy CM5 build via pmbootstrap (superseded by build-image.py). |
| `~/Developer/Marathon-Shell/packaging/scripts/push-cm5.sh`   | Push APKs to a flashed CM5 for hot-iter.                          |

---

## 12. Where to look next

- `README.md` — project intro, repo layout
- `docs/ARCHITECTURE.md` — shell process model, scene graph layers
- `docs/IMAGE_BUILD_ARCHITECTURE.md` — duranium + in-tree `packaging/` relationship
- `docs/WAYLAND_PROTOCOLS.md` — supported protocols + vendored extensions
- `docs/UI_DESIGN_SYSTEM.md` — Marathon DS reference
- `docs/CODING_RULES.md` — what to do and not do
- `docs/redesign/` — JSX source-of-truth for the next-gen surfaces
