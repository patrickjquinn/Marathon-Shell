# Over-the-air updates

Marathon OS updates as whole images: a signed feed, two `/usr` slots, a boot
counter that tries a new image a few times, and a health check that only
marks a boot good once the shell has drawn a frame. A bad image rolls back by
itself.

Today this works on one target, the QEMU dev-sim, built with
`MARATHON_IMAGE_LAYOUT=ab`. Every other device keeps its single-root image and
Settings says it can't install updates. [Per-device status](#per-device-status)
lists what each one still needs.

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
                                                 CheckNew / GetAppStream / Update / Job.Progress
 systemd-sysupdate: verify SHA256SUMS.gpg with /usr/lib/systemd/import-pubring.pgp,
   write the free /usr + verity slot (label duranium_<v>_usr/_vty), then EFI/Linux/<id>_<v>+3-0.efi
 reboot → systemd-boot boots the newest entry with tries left, renaming it +2-1, +1-2, +0-3
   → marathon-boot-health waits for $XDG_RUNTIME_DIR/marathon-shell-ready (shell's first frame)
       ok:   boot-complete.target → systemd-bless-boot drops the counter, the entry is good
       fail: no blessing; reboot if that leads somewhere; at +0-3 systemd-boot boots the previous good entry
```

### Image layout (`MARATHON_IMAGE_LAYOUT=ab`)

Pipeline patch 0035 restores duranium's partitions for devices in
`AB_DEVICES` (`scripts/mkosi-configure.py`, qemu-aarch64 only for now):

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

## Per-device status

| Device | Boot chain | Rollback today | Needed |
|---|---|---|---|
| QEMU dev-sim (qemu-aarch64) | UEFI (AAVMF) → systemd-boot → UKI | yes, with `MARATHON_IMAGE_LAYOUT=ab` | validation on an image build (below); then make `ab` the QEMU default |
| Librem 5 | U-Boot `boot.scr` → kernel + initramfs from ext4 partition 1 | no | either U-Boot's EFI loader → systemd-boot (duranium's plan; FAT write and EFI variables at runtime to verify), or U-Boot `bootcount`/`bootlimit`/`altbootcmd` choosing the slot, with marathon-health clearing `bootcount`/`upgrade_available` via `fw_setenv` |
| PinePhone | U-Boot (our `u-boot-pinephone-marathon` fork) `boot.scr` | no | same as the Librem 5; we already build its U-Boot, so `CONFIG_BOOTCOUNT_LIMIT` is in reach |
| Raspberry Pi 5 / HackberryPi CM5 | Pi firmware → `kernel_2712.img` + initramfs + `cmdline.txt`, MBR | no | two boot partitions selected by `autoboot.txt` (`tryboot_a_b=1`), a hook after sysupdate that runs `reboot '0 tryboot'`, and marathon-health rewriting `autoboot.txt` once the try boots. The firmware does not count tries: one failed try falls back. |
| OnePlus 6 | Android boot.img → U-Boot → EFI | untested | the EFI path should work as on QEMU; needs a device |

`AB_DEVICES` and the device branches in `mkosi-configure.py` are the per-device
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
