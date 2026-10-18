# Pipeline patches

Marathon's divergence from upstream postmarketOS duranium, as a `git am`
series. `bootstrap.sh` clones duranium at the pinned commit (`394290c6`),
applies every `*.patch` here in order, and checks out a pinned mkosi
beside it. `scripts/build-image.sh` runs it on every build; an already
patched tree is left alone if its log contains the newest patch's subject.

The tree it produces (`~/.cache/marathon-build/duranium/` by default) is
generated. To change duranium, add the next numbered patch here.

There are 39 patches. **There is no 0011**: it vendored a loose
`StoreApp.qml` copy and was removed by 0019.

| # | Subject | What it is for |
|---|---------|----------------|
| 0001 | add marathon-mail-oauth to base image + extend verify-mail.sh | Ships the mail OAuth/Secret Service helper the QMF credential plugins need; QMF dev package in the shell build so Mail is not compiled out. |
| 0002 | feat(mail-oauth): source oauth-clients.env from shell src tree | Bakes Google/Microsoft OAuth client IDs into the helper when the gitignored env file exists. |
| 0003 | feat(base): avahi + nss-mdns + hostname=marathon for SSH discovery | `marathon.local` over mDNS. |
| 0004 | fix(ssh): sshd actually starts on real hardware + pubkey auth baked in | sshd enabled and configured through `/usr/share/factory`, since `/etc` is fresh on first boot. |
| 0005 | build(marathon-shell): pull qt6-qtwebchannel-dev for Maps build | WebChannel for the Maps app. |
| 0006 | fix(base): drop nss-mdns; Alpine edge removed the package mid-2026 | Keeps the build resolving; avahi still advertises the host. |
| 0007 | fix(base): synthesize /boot/loader/entries/*.conf when pmOS leaves it empty | finalize needs a loader entry to find kernel, initrd, cmdline and DTB. |
| 0008 | chore(pipeline): r180 image bringup snapshot | Pi 5 / CM5 bring-up: single ext4 root partition, `pmOS_boot`/`pmOS_root` labels, pinned `linux-rpi`, PAM overrides, factory shell config. |
| 0009 | fix(mkosi.finalize): r180 cmdline + drop usercfg.txt writes | Pi cmdline (splash, `cgroup_enable=memory`); device aports own `usercfg.txt`. |
| 0010 | feat(pipeline): layer-2 device overlay injection + generic device-APK builder | Lets the HackberryPi overlay layer on top of the Pi 5 overlay. |
| 0012 | feat(librem5): pipeline detection — Bootloader=uki, kernel pin, /etc stash | Librem 5 joins the raw-kernel + mkinitfs boot path. |
| 0013 | feat(build-image): auto-sync Marathon-Image device aports into pmaports | Copies Marathon's device aports into pmaports so the mkosi sandbox can read them. |
| 0014 | feat(librem5): boot composer (vmlinuz + initramfs + DTBs from UKI) | Lays out `/boot` for the Librem 5's `boot.scr`. |
| 0015 | fix(librem5): move boot composer into if-EXISTING-ENTRY branch + bump boot part to 512 MiB | The composer never ran; the boot partition was too small. |
| 0016 | fix(tools): use systemd-ukify, not the dropped ukify package | Fedora tools tree builds again. |
| 0017 | fix(initrd): mask NetworkManager-config-initrd.service | The unit cannot succeed on Alpine and failed every boot. |
| 0018 | feat(pipeline): local apk trust, Plymouth in the initrd, L5 boot script | Marathon's locally signed apks, the Marathon splash from the initramfs, the L5 `marathon-boot.cmd`. |
| 0019 | fix(store): stop shadowing the compiled Store with a loose QML copy | Store loads its compiled module like the other apps; removes 0011. |
| 0020 | fix(base): drop postmarketos-base-nofde | Package set resolvable again. |
| 0021 | fix(store): run the store handler outside the app sandbox, report progress | Store installs land in the real home and report progress and failures. |
| 0022 | feat(pinephone): boot the original PinePhone through U-Boot like the Librem 5 | PinePhone image: MBR, U-Boot at 8 KiB, shared boot composer. |
| 0023 | fix(finalize): name the device in the U-Boot boot script step | Log and image names say which device. |
| 0024 | fix(store): let the store handler cancel an install or update | One transient unit per job. |
| 0025 | fix(store): drop the bash store handler | The Rust `marathon-store-handler` from the shell package replaces it. |
| 0026 | fix(user-units): keep Marathon's per-user services out of root's session | `ConditionUser=!root` on per-user units. |
| 0027 | fix(factory): stop seeding dev-tool and CM5-only settings | Home grid filter and scale factor back to defaults on every device. |
| 0028 | feat(browser): open web links in Pacific | Pacific as the default HTTP(S) handler. |
| 0029 | fix(cm5): actually layer the HackberryPi overlay | The device name check never matched. |
| 0030 | fix(finalize): run mkinitfs from /usr/bin, never ship a kmods-only initrd | Pi 5 / CM5 and PinePhone got an initramfs with no `/init`. |
| 0031 | fix(finalize): plain-cpio initramfs on the Pi from zstd too | mkinitfs 2.12 writes zstd. |
| 0032 | fix(pi): boot partition laid out as Raspberry Pi OS does | FAT32, MBR type 0x0c, correct hidden sectors; HackberryPi mounts root. |
| 0033 | fix(pi): grow the root partition to fill the card | `pmos.force-partition-resize` on the Pi cmdline. |
| 0034 | fix(factory): drop the HackberryPi's 110 % interface size | `FORCE_DPI` in the device profile gives the right scale. |
| 0035 | feat(qemu): A/B /usr layout for systemd-sysupdate | `MARATHON_IMAGE_LAYOUT=ab` restores duranium's erofs + verity `/usr` slots on QEMU, for OTA updates with rollback (docs/OTA.md). |
| 0036 | fix(ota): trust only Marathon's sysupdate feed | Drops postmarketos-duranium's transfers and pmOS's signing key; Marathon's come from build-image.sh. |
| 0037 | feat(pi): A/B GPT layout for systemd-sysupdate | `MARATHON_IMAGE_LAYOUT=ab` on raspberry-pi5: GPT, `autoboot.txt` partition, two FAT boot and two ext4 root slots, shared data partition (docs/OTA.md). |
| 0038 | fix(finalize): A/B Pi slots name their own root and boot partition | Each boot slot's `cmdline.txt` names its root and boot partition by GPT label; `panic=10`, no `pmos.force-partition-resize`. |
| 0039 | fix(build): A/B builds reach mkosi's configure script | `build-image.py` passes `MARATHON_IMAGE_LAYOUT` with `--environment` (PassEnvironment never saw it, so A/B builds got the single-root layout) and refuses an A/B Pi image without an autoboot partition. |
| 0040 | fix(pi): keep fbcon off tty1 so the splash survives greetd | `fbcon=vc:2-63` on the Pi cmdline: greetd's KD_TEXT on tty1 no longer repaints the console over the splash, so it stays until the shell's first frame. |

`scripts/check-patch-numbers.sh` lists duplicate numbers and gaps.
