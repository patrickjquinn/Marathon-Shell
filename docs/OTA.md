# Over-the-air updates

Marathon OS updates as whole images: a signed feed, two `/usr` slots, a boot
counter that tries a new image a few times, and a health check that only
marks a boot good once the shell has drawn a frame. A bad image rolls back by
itself.

Two targets build this way with `MARATHON_IMAGE_LAYOUT=ab`: the QEMU dev-sim,
and the Raspberry Pi 5 / HackberryPi CM5, which has no boot counter and uses
the Pi firmware's one-shot tryboot instead ([Raspberry Pi](#raspberry-pi-5--hackberrypi-cm5)).
Every other device keeps its single-root image and Settings says it can't
install updates. [Per-device status](#per-device-status) lists what each one
still needs.

## Choice: systemd-sysupdate

| | systemd-sysupdate | RAUC | SWUpdate / Mender | OSTree | btrfs + apk snapshots |
|---|---|---|---|---|---|
| Already in the stack | yes. systemd 262 on the image is built with `-Dsysupdate -Dsysupdated`, and duranium is designed around it | Alpine ships rauc 1.10, but nothing uses it | no | no | apk, yes. btrfs, no |
| Signing | GPG detached signature over `SHA256SUMS`, and every payload is checked against it | X.509 / CMS bundles | CMS/RSA / server-side | GPG commits | apk index signatures only, no image-level signature |
| A/B with verity | partitions matched by GPT label; mkosi puts `usrhash=` in each UKI | slots + verity bundles | slots | file-level deployments, not verity | snapshots |
| Rollback | systemd-boot boot counting + `boot-complete.target` + `systemd-bless-boot` | U-Boot/barebox/GRUB/EFI backends; RPi firmware backend is only a PR | U-Boot bootcount | ostree-boot integration | needs grub-btrfs-style boot integration we don't have |
| Unprivileged UI client | `org.freedesktop.sysupdate1` (systemd-sysupdated) with polkit, active session allowed | `de.pengutronix.rauc.Installer` | daemon-specific | rpm-ostree D-Bus | none |
| Delta / streaming | no, full images (zstd) | adaptive and streaming updates | SWUpdate: rdiff/zchunk deltas; Mender: deltas in its commercial tier | object-level deltas | per-package |

systemd-sysupdate wins on fit. It is what duranium, Marathon's image base, is
built for. It needs no new daemon. Its D-Bus API was written for this exact
client, a session UI behind polkit. Boot assessment is part of the boot chain
the QEMU image already runs: UEFI → systemd-boot → UKI.

RAUC is the strongest alternative. It has X.509 signing, adaptive updates, and
the most bootloader backends. Its Raspberry Pi firmware/tryboot backend is still
an open PR, though, so the Pi needs custom code under either tool. Choosing it
would also mean a second update stack beside duranium's. The real cost of
sysupdate is that it sends full images. Downloads are therefore blocked on
metered networks, and delta updates are the first thing to revisit if image size
becomes a problem.

Sources: duranium `DESIGN.md` (in the generated tree), [sysupdate.d(5)](https://www.freedesktop.org/software/systemd/man/latest/sysupdate.d.html),
[org.freedesktop.sysupdate1(5)](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.sysupdate1.html),
[Automatic Boot Assessment](https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/),
[systemd-bless-boot.service(8)](https://www.freedesktop.org/software/systemd/man/latest/systemd-bless-boot.service.html),
[AppStream bundles for sysupdate](https://systemd.io/APPSTREAM_BUNDLE/),
[RAUC](https://rauc.readthedocs.io/),
[Bootlin: safe updates with RAUC on the Pi 5](https://bootlin.com/?p=19769),
[Pi `autoboot.txt` / tryboot](https://www.raspberrypi.com/documentation/computers/config_txt.html#autoboot-txt),
[U-Boot boot count limit](https://docs.u-boot-project.org/en/latest/api/bootcount.html).

## How it fits together

```
 build host                              thrivelobal.com (MARATHON_OTA_URL)
 ──────────                              ───────────────────────────────────
 build-image.sh MARATHON_IMAGE_LAYOUT=ab  <url>/<image-id>/
   └ mkosi: ESP + erofs /usr + verity       <id>_<v>.usr-arm64.<uuid>.raw.zst
 marathon-ota publish ──── rsync ────────►  <id>_<v>.usr-arm64-verity.<uuid>.raw.zst
   zstd, SHA256SUMS, gpg --detach-sign      <id>_<v>.efi
                                            SHA256SUMS, SHA256SUMS.gpg
                                            marathon-os.metainfo.xml
 device
 ──────
 Settings ─ UpdateClient ─(session bus)─► shell UpdateService ── gate: NM Metered, UPower ≥30 %/charging
                                            └ SysupdateBackend ─(system bus)─► systemd-sysupdated
                                                 CheckNew / GetAppStream / Install / Job.Progress
 systemd-sysupdate: verify SHA256SUMS.gpg with /usr/lib/systemd/import-pubring.pgp,
   write the free /usr + verity slot (label duranium_<v>_usr/_vty), then EFI/Linux/<id>_<v>+3-0.efi
 reboot → systemd-boot boots the newest entry with tries left, renaming it +2-1, +1-2, +0-3
   → marathon-boot-health waits for $XDG_RUNTIME_DIR/marathon-shell-ready (shell's first frame)
       ok:   boot-complete.target → systemd-bless-boot drops the counter, the entry is good
       fail: no blessing; reboot if that leads somewhere; at +0-3 systemd-boot boots the previous good entry
```

### Image layout (`MARATHON_IMAGE_LAYOUT=ab`)

Pipeline patch 0035 restores duranium's partitions on qemu-aarch64 (the Pi's
layout is [below](#layout-mkosirepartab-pi-pipeline-patches-0037-and-0038)):

| Partition | Created by | Size |
|---|---|---|
| ESP (`pmOS_boot`): systemd-boot, UKIs in `EFI/Linux` | mkosi | 1 GiB |
| `/usr` A, erofs lz4, label `duranium_<v>_usr` | mkosi | 5 GiB |
| `/usr` A verity, label `duranium_<v>_vty` | mkosi | 400 MiB |
| `/usr` B and its verity, label `_empty` | systemd-repart, first boot | 5 GiB + 400 MiB |
| root, ext4 on LUKS (empty passphrase, auto-unlocked), label `pmOS_root` | systemd-repart, first boot | rest of the disk |

The root partition definitions come from postmarketos-duranium's
`/usr/lib/repart.d`. Each UKI carries its own `usrhash=`, so it mounts the
`/usr` it was built with. `/etc` is duranium's mutable confext, and `/var` and
`/home` live on root, so both slots share them. `/usr` is read-only: `apk add`
on the device does not persist, and app installs belong in the home directory,
as Store installs already do.

### Feed and signing

`scripts/ota/marathon-ota` writes the feed and keeps the newest `--keep`
versions (2 by default, matching `InstancesMax=2`). It refuses a version that
is already published or older than the newest one. Payloads land first, and
`SHA256SUMS` and its signature land last, so a client never sees a version whose
files are missing. With `--upload` it rsyncs the payloads, then the manifest,
then deletes pruned files.

`--notes FILE` becomes the release's AppStream description: blank lines
separate paragraphs, and lines starting `- ` or `* ` are list items, which
Settings shows as bullets.

Keys:

```sh
scripts/ota/marathon-ota keygen --gnupghome ~/.marathon-secrets/ota/gnupg \
    --export packaging/ota/marathon-ota.asc
```

The private key never leaves `~/.marathon-secrets/ota/gnupg`. Commit the
public half at `packaging/ota/marathon-ota.asc` (or point
`MARATHON_OTA_PUBKEY` at it). `build-image.sh` dearmors it into
`/usr/lib/systemd/import-pubring.pgp`, the keyring systemd-pull checks
`SHA256SUMS.gpg` against. Patch 0036 stops trusting pmOS's key and drops
postmarketos-duranium's transfers, so a Marathon image only ever updates from
Marathon's feed. To rotate keys, ship an image whose keyring holds both keys,
then start signing with the new one.

The transfers are templates in `packaging/ota/sysupdate.d/`, rendered with
`MARATHON_OTA_URL` (default `https://thrivelobal.com/marathon/updates`). The UKI
transfer is named last, so a new boot entry appears only after its `/usr` is
written. Its `AppStream=` points at the catalog that gives Settings each
release's download size and notes.

### Shell and Settings

`UpdateService` (`shell/src/services/updateservice.*`) is the state machine.
`SysupdateBackend` talks to systemd-sysupdated. The Settings page shows:

| State | Meaning |
|---|---|
| `unsupported` | no sysupdate host target (single-root image) or no `IMAGE_VERSION` |
| `idle` / `checking` / `upToDate` | checked every 6 h (first check 30 s after start) and from the pull-down menu |
| `available` | version, download size and notes from the AppStream catalog; "Download and install" |
| `downloading` | `Job.Progress`, with Cancel |
| `readyToReboot` | installed; "Restart now" goes through logind |
| `rolledBack` | an image the shell installed in an earlier boot is on disk but not running, so it failed its health check |
| `error` | the sysupdated error, e.g. a signature failure |

Downloads start only if NetworkManager's `Metered` is not yes/guess-yes and,
when UPower reports a battery, the battery is at 30 % or more or charging. A
blocked install says why: connect to Wi-Fi, or charge.

**Automatic updates** (Settings switch, on by default, as on iOS and Android):
a check that finds an update downloads it as soon as those gates allow; a
download the person cancelled is not restarted by itself. An installed
update then restarts between 02:00 and 05:00 local time, only on charge (or
with no battery) and with the screen off and no call or alarm. "Restart
tonight" (Settings, or Tonight on the notification) asks for the same with
automatic updates off. The shell re-evaluates when the screen, a call or
alarm, the charger, Wi-Fi or a resume changes, and arms a
`marathon-wake-update-restart` wake timer for the window, as alarms do.

**Notifications** come from the shell's own notification server as "Software
update" (Settings' update icon), each replacing the previous one, and a tap
opens Settings → Software updates:

| When | Notification | Buttons |
|---|---|---|
| an update is found and not downloading by itself | Update available, Marathon `<v>` | Download, Later |
| an update is installed | Restart to finish updating | Restart now, Tonight |
| the update failed its health check | Marathon `<v>` didn't start: went back to `<running>` | |
| the first boot into a new version | Updated to Marathon `<v>` | (tap: what's new) |

Each fires once per version (`notice/<kind>` in the shell's settings group
`updates`). A new version is told from `lastSeenVersion`. Settings shows
"What's new" from the running version's AppStream release notes.

**Boot splash**: `marathon-update-splash` (in marathon-plymouth-theme) shows
"Finishing update…" on the Plymouth splash while the booting `IMAGE_VERSION`
differs from the last one whose shell came up, which it records in
`/var/lib/marathon-update-splash/started-version` once
`/run/user/*/marathon-shell-ready` appears. That covers the first boot after
an update and every retry of a trial boot; a rollback or a fresh flash shows
the plain splash. It never fails a boot.

The update channel picker is gone. Channels were GitHub pre-releases, and
images are built for one release (`edge`), which sysupdate matches as `%w`.
Staged rollout is not implemented. Promoting a build from a test feed to the
public one is the manual equivalent.

### Health check

`marathon-boot-health.service` (crate `crates/marathon-health`) is required by
`boot-complete.target` and runs only when systemd-boot is counting
(`LoaderBootCountPath` set). It waits up to `MARATHON_HEALTH_TIMEOUT_SECS`
(300 s) for any `/run/user/*/marathon-shell-ready`. The shell writes that file
on its first frame. If the file never appears, the unit fails and the boot is
not blessed. marathon-health then reboots, but only if the reboot can lead
somewhere: either the entry still has tries left, or another entry in
`EFI/Linux` is good or has tries. An entry already at zero that is the only one
left stays up, so a device with nothing to fall back to never reboot-loops.
Blessed entries are not counted, so it never runs on them.

## Raspberry Pi 5 / HackberryPi CM5

The Pi 5 has no UEFI: its firmware loads `config.txt`, `kernel_2712.img`,
`initramfs_2712` and `cmdline.txt` from a FAT partition, and the postmarketOS
mkinitfs initramfs mounts an ext4 root. A/B follows the Raspberry Pi
[`autoboot.txt`](https://www.raspberrypi.com/documentation/computers/config_txt.html#autoboot-txt)
design: whole boot and root partitions per slot, chosen by `autoboot.txt`.
systemd-sysupdate only writes partitions on a GPT disk ("Disk … has no GPT
disk label, not suitable"), so the A/B image is GPT; the Pi 5 bootloader
reads GPT ([rpi-eeprom release notes](https://github.com/raspberrypi/rpi-eeprom/blob/master/firmware-2712/release-notes.md)).
[Bootlin's RAUC backend for the Pi 5](https://bootlin.com/?p=19769) and
[Ubuntu's piboot](https://ubuntu.com/hardware/docs/boards/explanations/piboot-ab/)
do the same swap.

### Layout (`mkosi.repart.ab-pi`, pipeline patches 0037 and 0038)

| # | GPT label | Type | Size | Holds |
|---|---|---|---|---|
| 1 | `marathon_autoboot` | ESP | 256 MiB | `autoboot.txt` only |
| 2 | `marathon_<v>_boot` | basic data | 512 MiB | the slot's whole boot partition: `config.txt`, `usercfg*.txt`, kernel, initramfs, `cmdline.txt`, DTBs, overlays |
| 3 | `_empty`, then the other boot slot | basic data | 512 MiB | |
| 4 | `marathon_<v>_root` | root (arm64) | 6 GiB | the slot's full ext4 root, `/etc` included |
| 5 | `_empty`, then the other root slot | root (arm64) | 6 GiB | |
| 6 | `marathon_data` | var | 1 GiB, grown to the end of the card on first boot | `/var`, `/home` (as `/var/home`), the `/etc` overlay's upper layer |

The second slot pair is created empty in the image. `autoboot.txt` starts as

```
[all]
tryboot_a_b=1
boot_partition=2
[tryboot]
boot_partition=3
```

Each boot slot's `cmdline.txt` names its own root and boot partition by GPT
label, `pmos_root=/dev/disk/by-partlabel/marathon_<v>_root` and
`pmos_boot=…_boot`, so boot slot `<v>` finds root slot `<v>` wherever
sysupdate put it. It adds `panic=10` and drops `pmos.force-partition-resize`.

The mkinitfs hook `hooks-cleanup/50-marathon-ab.sh` runs after the slot's root
is mounted. On first boot it grows `marathon_data` to the end of the card and
seeds it from the slot's `/var` and `/home`. Every boot it mounts it on
`/var`, binds `/var/home` on `/home`, and mounts `/etc` as an overlay whose
upper layer is `/var/lib/marathon-ab/etc/upper`, so `/etc` changes made
before and after PID 1 starts persist across slots. Anything else written to
`/` stays in its slot. The sources are in `packaging/ota/pi/`;
`build-image.sh` installs them, and the transfers in
`packaging/ota/pi/sysupdate.d/`, for Pi A/B builds.

### Update, trial and commit

1. sysupdate writes the root slot, then the boot slot, into the pair that
   does not hold the running version (`ProtectVersion=%A`).
2. At shutdown, `marathon-tryboot.service` runs `marathon-health --mode arm`:
   if a newer version has both slots written, it points `[tryboot]` at its
   boot partition, records the partition's start in its FAT32 hidden
   sectors, and writes `0 tryboot` to `/run/systemd/reboot-param`. Settings'
   "Restart now" (a logind reboot) then becomes `reboot '0 tryboot'`.
3. A version installed before a power-off or power loss is tried at the next
   boot: the same unit's `--mode boot` arms it and reboots before greetd.
   Each version gets two trial boots, counted once per boot, in
   `/var/lib/marathon-health/tryboot`.
4. On the trial boot `marathon-tryboot-health.service` waits for the shell's
   first frame, then swaps the two partitions in `autoboot.txt`, rewritten in
   place at the same length. Without a frame within
   `MARATHON_HEALTH_TIMEOUT_SECS` it reboots.
5. The firmware clears the tryboot flag before it starts the kernel, so any
   reboot or reset during a trial, including `panic=10`, the initramfs guard
   hook (180 s) and the 15 s systemd watchdog, boots the committed slot.

Settings shows a version that failed its trials as rolled back, from the same
`GetVersion` logic as on QEMU.

## Per-device status

| Device | Boot chain | Rollback today | Needed |
|---|---|---|---|
| QEMU dev-sim (qemu-aarch64) | UEFI (AAVMF) → systemd-boot → UKI | yes, with `MARATHON_IMAGE_LAYOUT=ab` | validation on an image build (below); then make `ab` the QEMU default |
| Librem 5 | U-Boot `boot.scr` → kernel + initramfs from ext4 partition 1 | no | either U-Boot's EFI loader → systemd-boot (duranium's plan; FAT write and EFI variables at runtime to verify), or U-Boot `bootcount`/`bootlimit`/`altbootcmd` choosing the slot, with marathon-health clearing `bootcount`/`upgrade_available` via `fw_setenv` |
| PinePhone | U-Boot (our `u-boot-pinephone-marathon` fork) `boot.scr` | no | same as the Librem 5; we already build its U-Boot, so `CONFIG_BOOTCOUNT_LIMIT` is in reach |
| Raspberry Pi 5 / HackberryPi CM5 | Pi firmware → `autoboot.txt` (`tryboot_a_b=1`) → the slot's FAT boot partition → mkinitfs → ext4 root slot by GPT label | yes, with `MARATHON_IMAGE_LAYOUT=ab` (GPT) | validated on the HackberryPi 2026-10-17 ([results](#hackberrypi-validation)). One failed trial falls back; each version gets two |
| OnePlus 6 | Android boot.img → U-Boot → EFI | untested | the EFI path should work as on QEMU; needs a device |

`AB_DEVICES` in `mkosi-configure.py` (`qemu-aarch64`, `raspberry-pi5`), with
each device's repart directory, and its device branches are the per-device
hooks. A device joins once its boot chain can try a slot and fall back.

## QEMU validation

No step here has been run yet: the pieces are unit-tested, and
`scripts/ota/test_marathon_ota.py` runs the real `systemd-sysupdate` against a
published feed (UKI transfer only, since partitions need a disk).

Disk: about 30 GB free. Each A/B build leaves about 5 GB in `mkosi.output`
(the raw disk plus split partitions), and a build needs about 8 GB more while it
runs. The device disk copy grows to about 6 GB once its root and second slot
are written. Each published version is about 2 GB.

1. **Trees.** The existing duranium tree predates 0035/0036, and bootstrap.sh
   refuses to update it. Restore the locally rewritten `mkosi.conf`
   (setup-trees.sh redoes its RootPassword edit), then apply:
   ```sh
   D=~/.cache/marathon-build/duranium
   git -C $D checkout -- mkosi.conf
   git -C $D am $PWD/packaging/pipeline-patches/0035-*.patch $PWD/packaging/pipeline-patches/0036-*.patch
   ```
   Drop the cached shell and base-config apks, since their pkgrel did not
   change: `rm $D/mkosi.packages/marathon-shell-1*.apk $D/mkosi.packages/marathon-base-config-*.apk`.
2. **Key.** `scripts/ota/marathon-ota keygen --gnupghome ~/.marathon-secrets/ota/gnupg --export packaging/ota/marathon-ota.asc`
3. **Image N.** `MARATHON_IMAGE_LAYOUT=ab MARATHON_OTA_URL=http://10.0.2.2:8080 scripts/build-qemu-image.sh --bump`
   (10.0.2.2 is the host as QEMU's user network sees it). Copy it out as the
   device disk: `mkdir -p ~/ota-test && cp --sparse=always $D/mkosi.output/qemu-aarch64_marathon_edge/qemu-aarch64_marathon_edge_<N>.raw ~/ota-test/device.raw`
4. **First boot.** `MARATHON_QEMU_IMAGE=~/ota-test/device.raw scripts/qemu/lib/boot-image.sh`
   (UEFI, because the image has a `/usr` partition; VNC on :5905, SSH on
   :2233, root password `marathon`). Check:
   - `lsblk -o NAME,PARTLABEL,SIZE` shows `duranium_<N>_usr`, `duranium_<N>_vty`, two `_empty` partitions, and `pmOS_root` (LUKS)
   - `systemctl status marathon-boot-health systemd-bless-boot` both succeeded, and `bootctl list` shows the `<N>` entry with no tries left/done (blessed)
   - `busctl call org.freedesktop.sysupdate1 /org/freedesktop/sysupdate1 org.freedesktop.sysupdate1.Manager ListTargets` lists `host`
   - Settings → Software updates: "Not checked yet", Marathon OS `<N>`
5. **Image N+1 and publish.** `MARATHON_IMAGE_LAYOUT=ab MARATHON_OTA_URL=http://10.0.2.2:8080 scripts/build-qemu-image.sh --bump`, then
   ```sh
   scripts/ota/marathon-ota publish --image-dir $D/mkosi.output/qemu-aarch64_marathon_edge \
       --version <N+1> --feed ~/ota-test/feed --gnupghome ~/.marathon-secrets/ota/gnupg --notes notes.txt
   python3 -m http.server 8080 --bind 127.0.0.1 --directory ~/ota-test/feed
   ```
6. **Gating.** In the guest, `nmcli connection modify "Wired connection 1" connection.metered yes`.
   Settings → pull down → Check now → "Marathon OS <N+1> is available" with its
   size and notes. Tap Download and install → "Connect to Wi-Fi…", with nothing
   downloaded (the http.server log shows only `SHA256SUMS*` and the catalog).
   Set `connection.metered no`.
7. **Update.** Download and install → progress → "ready to install" →
   Restart now. `bootctl list` shows `<N+1>` booted and blessed. `IMAGE_VERSION`
   in `/etc/os-release` is `<N+1>`, and Settings shows Up to date after a check.
   The splash says "Finishing update…" on that boot, the Hub then has
   "Updated to Marathon `<N+1>`" (and no "Restart to finish updating" left
   over), and a second reboot shows the plain splash.
   Negative check: re-sign `SHA256SUMS` with another key and Check now gives an
   error naming the signature.
8. **Forced failure → rollback.** Build N+2 with a shell that never starts and a
   short health timeout. These are one-off files in the generated tree's
   `mkosi.extra`; remove them right after the build:
   ```sh
   mkdir -p $D/mkosi.extra/usr/lib/systemd/system/greetd.service.d $D/mkosi.extra/usr/lib/systemd/system/marathon-boot-health.service.d
   printf '[Unit]\nConditionPathExists=/ota-test-never\n' > $D/mkosi.extra/usr/lib/systemd/system/greetd.service.d/ota-test.conf
   printf '[Service]\nEnvironment=MARATHON_HEALTH_TIMEOUT_SECS=60\n' > $D/mkosi.extra/usr/lib/systemd/system/marathon-boot-health.service.d/ota-test.conf
   MARATHON_IMAGE_LAYOUT=ab MARATHON_OTA_URL=http://10.0.2.2:8080 scripts/build-qemu-image.sh --bump
   rm -r $D/mkosi.extra/usr/lib/systemd/system/greetd.service.d $D/mkosi.extra/usr/lib/systemd/system/marathon-boot-health.service.d
   scripts/ota/marathon-ota publish --image-dir $D/mkosi.output/qemu-aarch64_marathon_edge --version <N+2> --feed ~/ota-test/feed --gnupghome ~/.marathon-secrets/ota/gnupg
   ```
   On the guest (still on N+1), install `<N+2>` from Settings and restart. Expect
   three boots of `<N+2>`, each about 60 s after boot with no shell, then a
   reboot (`journalctl -b -1 -u marathon-boot-health` shows "no shell frame
   within 60s"). The fourth boot is `<N+1>`. Settings then shows "Marathon OS
   <N+2> didn't start" and "Your phone went back to <N+1>", and `bootctl list`
   shows the `<N+2>` entry with 0 tries left.
9. Clean up: `rm -rf ~/ota-test`, and delete the extra builds from `$D/mkosi.output`.

## HackberryPi validation

Run on 2026-10-17 (images 26101702 → 26101705 → 26101706), all steps passed:

| Step | Result |
|---|---|
| 3. Image N (26101702), flashed in place over SSH from RAM | boots GPT on EEPROM 2025-06-13; six partitions, data grown to 16.5 GiB; tryboot 0, partition 2; `/etc` overlay and `/var`, `/home` on data |
| 4. N+1 (26101705) | automatic check found it, downloaded in the background with progress and notes, "Restart to finish updating" notification; Restart now → one reboot (31 s) to tryboot 1, partition 3; "partition 3 committed"; `[all]` 3 / `[tryboot]` 2; Bluetooth pairing, files, settings and Wi-Fi kept; "Updated to Marathon 26101705" on the lock screen |
| 5. Bad N+2 (26101706, no shell) | two trials on partition 2, each falling back after 60 s, the second armed by the early-boot catch-all; then "26101706 failed its trial boots; staying on 26101705"; `[all]` still 3; lock screen and Settings say it didn't start and went back |
| Later: 26101709 → 26101801 (2026-10-18) | Check now → download and install in under 5 min with bulleted notes → Restart now → one reboot, no firmware stall; "partition 2 committed" 9 s after boot; `/etc` upper layer kept, the image's new `device-profile.conf` took effect |

Found and fixed on the way: A/B builds never reached mkosi's configure
script (patch 0039); systemd 262's sysupdate1 has `Acquire` + `Install`, not
`Update`; duranium's first-boot `systemd-repart` ran on the Pi. One
post-fallback boot stalled 90 s in `plymouth show-splash`, and the firmware
sometimes stops at its "loading … starting" handoff; both predate A/B and are
tracked in docs/testing/OEM_TEST_HACKBERRYPI_2026-10-17.md.

The host serves the feed at 192.168.68.78; the device is
`root@192.168.68.79`. Reading the tryboot flag and booted partition:
`printf '%d\n' 0x$(od -An -tx1 -v /proc/device-tree/chosen/bootloader/tryboot | tr -d ' \n')`
(likewise `partition`).

1. **Before.** On the device: `du -sh /boot; du -sxh /; df -h /` (the slots
   are 512 MiB and 6 GiB). Power it off and back up the
   card with the USB reader: `sudo dd if=/dev/sdX of=~/hackberry-backups/pre-ab.img bs=4M`.
2. **Trees.** As in [QEMU validation](#qemu-validation) step 1, apply
   0035–0038 to the existing duranium tree (stash its local `mkosi.conf`
   edit around `git am`), and drop the cached `marathon-shell` apk.
3. **Image N.** `MARATHON_IMAGE_LAYOUT=ab MARATHON_OTA_URL=http://192.168.68.78:8080 scripts/build-hackberry-cm5-image.sh --bump`,
   then `scripts/flash/flash-hackberry-cm5.sh /dev/sdX`. This first boot is
   also the test that this card boots GPT. Check `lsblk -o NAME,PARTLABEL,PARTTYPE,SIZE`
   (six partitions, `marathon_data` grown), tryboot 0 and partition 2,
   `findmnt /var /home /etc /boot`, `systemd-sysupdate list`, and Settings →
   Software updates showing N. Add a Wi-Fi network, change the time zone,
   put a file in `~`, note `/etc/machine-id`, reboot twice: all unchanged.
4. **Image N+1.** Build again with `--bump`, then
   ```sh
   scripts/ota/marathon-ota publish --image-dir $D/mkosi.output/raspberry-pi5_marathon_edge \
       --version <N+1> --feed ~/ota-test/feed --gnupghome ~/.marathon-secrets/ota/gnupg --notes notes.txt
   python3 -m http.server 8080 --bind 192.168.68.78 --directory ~/ota-test/feed
   ```
   (open 8080/tcp on the host while testing). Settings → Check now → install
   → Restart now. Expect one reboot to tryboot 1, partition 3, `IMAGE_VERSION`
   N+1, `journalctl -u marathon-tryboot-health` saying partition 3 was
   committed, and `autoboot.txt` (mount partition 1 read-only) with
   `boot_partition=3` under `[all]` and `2` under `[tryboot]`. A plain reboot
   stays on N+1 with tryboot 0, and step 3's changes are still there.
   Variant: install, power off, power on: one extra reboot into the trial.
5. **Bad image N+2.** Build with the one-off drop-ins from QEMU step 8, using
   `marathon-tryboot-health.service.d` for the 60 s timeout, publish, install,
   restart. Expect a trial on partition 2 with no shell, "no shell frame
   within 60s", a reboot to N+1 on partition 3, a second trial, then N+1
   staying up; Settings shows N+2 didn't start; `[all]` is still 3.
6. Clean up: `rm -rf ~/ota-test`, close the port.

If the card does not boot at step 3, re-flash the backup. A torn
`autoboot.txt` (power lost during a commit) is fixed by mounting partition 1
on the host and rewriting it.

## Known gaps

- Full-image downloads only (about 2 GB per update); no delta or casync.
- No staged rollout percentage; one public feed per image id.
- duranium's dev-tools sysext/confext are no longer updated: their pmOS
  transfers are dropped, and Marathon does not publish them yet.
- The UEFI boot path cannot take the dev-sim's extra kernel arguments
  (`video=`, serial console) because systemd-stub ignores SMBIOS extras on
  this image. The display mode comes from the virtio-gpu EDID.
- A hang before userspace (kernel or initrd) does not reboot on its own; it
  needs a watchdog or a manual reset to spend the try.
- `duranium-set-channel` (from postmarketos-duranium) only rewrites pmOS's
  URLs, so it does nothing on Marathon images.
- Raspberry Pi: a kernel that hangs without panicking before PID 1 starts its
  watchdog sits until the device is power-cycled, which then boots the
  committed slot. The bootloader watchdog (EEPROM 2025-06-20 and later) and
  `PARTITION_WALK=1` (on by default from 2025-08-13) would harden this; the
  HackberryPi's EEPROM is 2025-06-13.
- Raspberry Pi: `IMAGE_ID` is `raspberry-pi5` for vanilla Pi 5 and HackberryPi
  builds alike, so both would share one feed directory. Publish HackberryPi
  builds only.
- Raspberry Pi: going from the single-root image to A/B needs a re-flash.
