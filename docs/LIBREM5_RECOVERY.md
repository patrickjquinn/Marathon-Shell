# Librem 5 Recovery Runbook

**Purpose.** Verified procedure to unbrick a Purism Librem 5 after a
failed Marathon mkosi image. The Librem 5 boots only from internal eMMC
(microSD is not a boot device), so a botched flash means the only path
back is over USB Serial Download Protocol (SDP). This runbook is the
prerequisite for any Marathon-on-Librem-5 image work — if a flashed
image fails to boot, the steps below restore the phone to postmarketOS
phosh in ~10 minutes.

**Host assumed.** Fedora 42 (kernel 6.19), `podman`, `git`, no
`pmbootstrap`. SSH/sudo via `SUDO_ASKPASS=/tmp/askpass.sh`.

**Phone assumed.** Purism Librem 5, NXP i.MX 8M Quad. Board revision
unknown — runbook covers r2/r3/r4 from one set of artifacts via the
upstream U-Boot dispatch script.

## 1. Install `uuu` (NXP mfgtools)

`uuu` is **not** in Fedora 42 repos as of this writing (no
`rpms/uuu` in `src.fedoraproject.org`). Build from the Purism mfgtools
fork — the version pinned to the Librem 5 flash script. `uuu ≥ 1.4.193`
is required (1.2.91 fails with `Unknown Command: FB: reboot` per
[forums.puri.sm/t/uuu-error-during-reflashing/22500](https://forums.puri.sm/t/uuu-error-during-reflashing/22500)).

```bash
sudo dnf install -y git cmake gcc-c++ pkgconf-pkg-config \
    libusb1-devel libzip-devel bzip2-devel libzstd-devel \
    openssl-devel zlib-devel tinyxml2-devel

git clone https://source.puri.sm/Librem5/mfgtools
mkdir mfgtools-build && cd mfgtools-build
cmake ../mfgtools
make -j"$(nproc)"
sudo install -m 0755 uuu/uuu /usr/local/bin/uuu
```

The Purism fork is used because nxp-imx HEAD trips
[mfgtools#436](https://github.com/nxp-imx/mfgtools/issues/436)
(`mv: cannot stat '/src/libuuu/gen/gitversion.h.tmp'`). Source:
[developer.puri.sm/Librem5/Development_Environment/Boards/HowTo/Building_uuu.html](https://developer.puri.sm/Librem5/Development_Environment/Boards/HowTo/Building_uuu.html).

### Udev rules (so `uuu` runs without sudo)

`/etc/udev/rules.d/99-librem5-uuu.rules`:

```
SUBSYSTEM!="usb", GOTO="librem5_uuu_rules_end"
# i.MX 8M Quad SDP (Librem 5)
ATTR{idVendor}=="1fc9", ATTR{idProduct}=="012b", GROUP+="plugdev", TAG+="uaccess"
# Fastboot / USB gadget (uuu Fastboot phase after SPL)
ATTR{idVendor}=="0525", ATTR{idProduct}=="a4a5", GROUP+="plugdev", TAG+="uaccess"
ATTR{idVendor}=="0525", ATTR{idProduct}=="b4a4", GROUP+="plugdev", TAG+="uaccess"
LABEL="librem5_uuu_rules_end"
```

Apply:

```bash
sudo udevadm control --reload-rules
sudo groupadd -f plugdev
sudo usermod -aG plugdev "$USER"
newgrp plugdev   # or log out + back in
```

Sanity check without a device:

```bash
uuu -V            # must print "libuuu-1.4.193" or newer
uuu -udev         # cross-check the udev rules against the printed recommendation
```

## 2. Enter Serial Download Protocol (SDP) mode

Canonical Purism procedure (verbatim:
[docs.puri.sm/Hardware/Librem_5/Maintenance/Reflashing.html](https://docs.puri.sm/Hardware/Librem_5/Maintenance/Reflashing.html)):

1. Power the phone off.
2. **All three hardware kill switches OFF (down).** Cellular *does*
   matter — leaving WWAN on is the most common SDP failure mode after
   dead-battery / bad-cable.
3. Remove back cover, pop battery out.
4. Press and **hold Volume Up**.
5. While still holding Vol+, plug USB-A→USB-C from host to phone AND
   reinsert the battery. Keep Vol+ held ~5 s after the battery clicks.
6. Release Vol+.

**LED sequence (success):** red blinks at battery insertion, then
**red + green both solid** = SDP ready. Red-only blinking with no green
means the SoC did NOT enter SDP — pull battery for ≥10 s, retry.

**Host verification:**

```bash
lsusb | grep 1fc9
# Bus 003 Device 042: ID 1fc9:012b NXP Semiconductors i.MX 8M Dual/8M QuadLite/8M Quad Serial Downloader
```

If `lsusb` shows `1d6b:0104 Multifunction Composite Gadget` instead,
the phone booted normally — you missed the Vol+ window. Power-cycle
and retry.

## 3. Jumpdrive — expose eMMC as USB Mass Storage

Latest release: **Jumpdrive 0.8** (2021-05-31, still current).
Asset: `purism-librem5.tar.xz`. The release ships no `.sha256` /
`.sig` sidecar; pin the version, fetch over HTTPS to github.com, and
record the locally-computed hash in your repo (see
`librem5-recovery/purism-librem5.tar.xz.sha256.local`).

```bash
mkdir -p ~/librem5-recovery && cd ~/librem5-recovery
curl -fLOJ https://github.com/dreemurrs-embedded/Jumpdrive/releases/download/0.8/purism-librem5.tar.xz
sha256sum purism-librem5.tar.xz | tee purism-librem5.tar.xz.sha256.local
tar xJf purism-librem5.tar.xz
# extracts: u-boot/, initramfs, purism-librem5.lst, boot-purism-librem5.sh
```

With the phone in SDP mode (§2):

```bash
cd ~/librem5-recovery
./boot-purism-librem5.sh
# equivalent: uuu purism-librem5.lst
```

`uuu` prints SPL upload progress, then `Done`. The phone screen stays
dark (Jumpdrive has no UI). Within ~5 s the host kernel logs a new
USB-MSC device:

```bash
dmesg -w
# usb-storage 3-1:1.0: USB Mass Storage device detected
# sd 4:0:0:0: [sdX] 60506112 512-byte logical blocks: (31.0 GB)
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep Jumpdrive
# sdX  31G  Jumpdrive  usb     <-- the Librem 5 eMMC
```

The `MODEL` column literally reads `Jumpdrive`. **Pick `/dev/sdX`
carefully — this is your phone's eMMC, treat it like a HDD wipe.**

## 4. Known-good factory-reset image — pmOS phosh

**Recommended: postmarketOS phosh edge.** Single self-contained
`.img.xz`, host-distro-agnostic, supports r2/r3/r4 from one image via
the U-Boot `board_rev`-driven DTB picker.

(PureOS Crimson via Purism's `librem5-flash-image` script is the
alternative; it wraps `uuu` itself but expects an apt-based host. On
Fedora that means running it inside a podman Debian container —
unnecessary friction for a recovery rig.)

Current verified image (as of 2026-06-20):

```bash
IMG=20260620-0010-postmarketOS-edge-phosh-29-purism-librem5.img.xz
URL=https://images.postmarketos.org/bpo/edge/purism-librem5/phosh/20260620-0010/$IMG
SHA256=607e0df59b8b8d8e4d164d3fb2deb1079a8813f97effd401b70481df197a7079

curl -fLO "$URL"
echo "$SHA256  $IMG" | sha256sum -c -    # MUST print "OK"
```

For a newer image, navigate
[images.postmarketos.org/bpo/edge/purism-librem5/phosh/](https://images.postmarketos.org/bpo/edge/purism-librem5/phosh/)
and pick the latest timestamp directory; the `.sha256` sidecar is
shipped alongside the `.img.xz`.

### dd sequence

The pmOS `.img.xz` is a **complete eMMC image**: GPT partition table,
embedded U-Boot at the i.MX 8M-mandatory **33 KiB offset** (the ROM
expects SPL at byte 33 KiB on the eMMC user area regardless of
partition, per
[community.nxp.com](https://community.nxp.com/t5/i-MX-Processors/i-MX8M-Mini-ROM-loader-always-expects-SPL-in-the-same-offset-on/m-p/1224178)
and upstream pmaports `device-purism-librem5/deviceinfo`
`deviceinfo_sd_embed_firmware="u-boot/librem5/phone-boot.img:33"`), boot
partition starting at sector 4096. Direct full-disk write — no
pre-zero, no separate partition-table dance:

```bash
# Replace /dev/sdX with the device from `lsblk` above. NOT /dev/sda.
DEV=/dev/sdX
sudo umount ${DEV}?* 2>/dev/null || true

xzcat "$IMG" | sudo dd of="$DEV" bs=4M conv=fsync status=progress
sudo sync
sudo blockdev --flushbufs "$DEV"
```

`conv=fsync` + the explicit `sync`/`flushbufs` is non-negotiable —
Jumpdrive ack'ing a write does NOT mean the eMMC controller has flushed
it.

## 5. Verification before tearing down recovery

While the eMMC is still exposed:

```bash
sudo partprobe "$DEV"
sudo sfdisk -d "$DEV" | head      # GPT, pmOS_boot + pmOS_root listed
sudo fdisk -l "$DEV"
```

Then power-cycle:

1. Unplug USB-C.
2. Hold power 15–18 s (forces hard power-down).
3. Short-press power to boot.

Success indicators in order:

1. Purism boot logo (red P on black) within ~3 s → U-Boot is reading
   the boot partition.
2. Plymouth/"loading" within ~10 s → kernel + initramfs loaded, DTB
   matched.
3. Phosh lock screen within ~45 s → userspace is up.

If stuck at (1) without progressing within ~30 s, the DTB selection
failed — see §6 + §7.

## 6. Identify the board revision

**On a booted phone (any OS):**

```bash
cat /sys/firmware/devicetree/base/compatible | tr '\0' '\n'
# purism,librem5-r4    <-- the rev is here
# purism,librem5
# fsl,imx8mq
```

**Via U-Boot (serial on UART4, see
[docs.puri.sm/Hardware/Librem_5/advanced/serial.html](https://docs.puri.sm/Hardware/Librem_5/advanced/serial.html)):**

```
=> printenv board_rev
board_rev=4
```

**DTB picker (verbatim from upstream
`pmaports/device/main/device-purism-librem5/uboot-script.cmd`):**

```
# Default to "-r4" if board_rev isn't set, since there are apparently Evergreen
# boards that either 1) identify as r4, 2) identify as r5 (or something else?),
# or 3) don't identify as anything(?).
# See: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/issues/1643#note_1147248594
dtb_file=imx8mq-librem5-r4.dtb
if itest.s "x3" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r3.dtb
elif itest.s "x2" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
elif itest.s "x1" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
elif itest.s "x0" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
fi
```

`board_rev ∈ {0,1,2} → r2.dtb`, `3 → r3.dtb`, **anything else or
unset → r4.dtb**. The Marathon overlay MUST keep all three DTBs in
the boot partition (`deviceinfo_dtb="freescale/imx8mq-librem5-r2
freescale/imx8mq-librem5-r3 freescale/imx8mq-librem5-r4"` — already
correct upstream).

**Box/batch heuristic** if the phone won't even POST:

| Batch | Date | DTB rev |
|---|---|---|
| Birch | 2019 | r1/r2 |
| Chestnut | 2020 early | r2 |
| Dogwood | 2020 mid | r3 |
| Evergreen + Fir + Liberty | 2020 late onwards | r4 |

Anything shipped after late 2020 is overwhelmingly r4.

## 7. Common failure modes

**A. "Phone won't enter SDP mode"** — `lsusb` shows nothing or a normal
gadget device.

1. Battery dead? Plug a charger first (Vol+ must be held when battery
   clicks; a dead battery never clicks).
2. Kill switches off? **All three.** Verify visually (recessed = off).
3. USB-C cable data-capable? Charge-only cables silently fail.
4. Re-seat the battery for ≥10 s before retry — the i.MX 8M's PMIC
   needs to fully discharge to re-arm the BOOT-MODE pins.

**B. "uuu sees the phone but Jumpdrive fails to load"** — `uuu` prints
`Fail` or `Unknown Command`.

1. Check `uuu -V` — must be **≥ 1.4.193**.
2. `which -a uuu` — stale system binary shadowing the fresh build?
3. Did you actually extract Jumpdrive? `ls -la purism-librem5.lst`
   should exist next to `boot-purism-librem5.sh`.

**C. "Host doesn't see USB-MSC after Jumpdrive loads"** — `lsblk`
doesn't list a new ~31 GB device.

1. `dmesg -w` for a `usb-storage` line. `device descriptor read/64,
   error -71` = phone disconnected before USB-MSC came up — usually
   thermal/undervoltage; charge battery 30 min and retry.
2. udev syntax — `udevadm test /sys/bus/usb/...`.
3. Cable swap — SDP enumeration tolerates marginal cables; USB-MSC at
   full speed does not.

**D. "dd writes fine but phone boots to a black screen"** — Purism
logo briefly, then nothing.

1. **DTB mismatch.** Most common. Re-read §6. If the eMMC image's
   `boot.scr` doesn't carry the r2/r3/r4 dispatch logic above, an
   Evergreen phone with `board_rev=unset` will load the wrong DTB and
   the MIPI-DSI panel won't init. Re-flash with a postmarketOS image
   (which always ships all three DTBs + the dispatch script).
2. SPL at wrong offset. The i.MX 8M ROM reads SPL from **byte offset
   33 KiB on eMMC user area**. If your Marathon mkosi pipeline writes
   SPL anywhere else, the ROM falls through to SDP-retry and you'll
   see a momentary `1fc9:012b` re-enumeration on the host — that's
   the tell.
3. Panel init failing despite correct DTB. Connect serial (UART4, see
   §6) and `dmesg` for `mxsfb` / `nwl-dsi` errors. Marathon overlay
   inherits `deviceinfo_mesa_driver="mxsfb-drm"` from upstream —
   don't override.

## Quick reference card

```bash
# One-shot recovery, eMMC → stock pmOS phosh:
lsusb | grep 1fc9                                                    # confirm SDP
cd ~/librem5-recovery && ./boot-purism-librem5.sh                    # boot Jumpdrive
lsblk -d -o NAME,SIZE,MODEL | grep Jumpdrive                         # find /dev/sdX
xzcat 20260620-0010-postmarketOS-edge-phosh-29-purism-librem5.img.xz \
  | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress             # write
sudo sync && sudo blockdev --flushbufs /dev/sdX                      # flush
# unplug USB-C, hold power 15-18s, short-press power to boot
```

## Staged artifacts (this host)

`~/librem5-recovery/` is pre-staged on the build host:

- `purism-librem5.tar.xz` (Jumpdrive 0.8, `sha256sum` recorded locally)
- `20260620-0010-postmarketOS-edge-phosh-29-purism-librem5.img.xz`
  (verified `607e0df5...7079`)
- `mfgtools/` (Purism fork, source)
- `mfgtools-build/uuu/uuu` (binary, install to `/usr/local/bin/uuu`)

## Sources

- [docs.puri.sm/Hardware/Librem_5/Maintenance/Reflashing.html](https://docs.puri.sm/Hardware/Librem_5/Maintenance/Reflashing.html)
- [developer.puri.sm/Librem5/Development_Environment/Boards/HowTo/Building_uuu.html](https://developer.puri.sm/Librem5/Development_Environment/Boards/HowTo/Building_uuu.html)
- [source.puri.sm/Librem5/librem5-flash-image](https://source.puri.sm/Librem5/librem5-flash-image)
- [github.com/dreemurrs-embedded/Jumpdrive/releases/tag/0.8](https://github.com/dreemurrs-embedded/Jumpdrive/releases/tag/0.8)
- [github.com/nxp-imx/mfgtools](https://github.com/nxp-imx/mfgtools), [nxp-imx/mfgtools#436](https://github.com/nxp-imx/mfgtools/issues/436)
- [images.postmarketos.org/bpo/edge/purism-librem5/phosh/](https://images.postmarketos.org/bpo/edge/purism-librem5/phosh/)
- [forums.puri.sm/t/uuu-error-during-reflashing/22500](https://forums.puri.sm/t/uuu-error-during-reflashing/22500)
- [community.nxp.com — i.MX 8M Mini ROM SPL offset](https://community.nxp.com/t5/i-MX-Processors/i-MX8M-Mini-ROM-loader-always-expects-SPL-in-the-same-offset-on/m-p/1224178)
- Local pmaports:
  `~/duranium-build/duranium/pmaports/device/main/device-purism-librem5/{deviceinfo,uboot-script.cmd,flash_script.lst,APKBUILD}`
  and `.../u-boot-librem5/APKBUILD`
