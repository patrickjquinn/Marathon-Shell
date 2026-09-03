# Marathon → Duranium migration

The strategic intent is to **make Marathon a Duranium UI variant**, not a
parallel mutable-pmOS image. This document is the path to get there.

## Current state (r24)

What's already done shell-side and image-side that makes the migration
mechanical rather than architectural:

| Prereq | Status | Where |
|---|---|---|
| No `/usr` writes at runtime | ✅ | bubblewrap `--ro-bind /usr /usr` per app launch (verified) |
| Default configs under `/usr/share/factory/etc/` | ✅ | `marathon-shell` r23+ |
| `tmpfiles.d` snippet symlinks factory configs into `/etc` at boot | ✅ | `marathon-shell-tmpfiles.conf` |
| Per-app data under `/home/<user>/.local/share/marathon-apps/<id>` | ✅ | bubblewrap binds (verified) |
| UI meta-package shaped like other pmOS UI variants | ✅ | `postmarketos-ui-marathon` |
| Flatpak + xdg-desktop-portal in the image | ✅ | `postmarketos-ui-marathon` `depends`/`_pmb_recommends` |
| Flathub remote registered at first boot | ✅ | `postmarketos-ui-marathon.post-install` |

## What remains for full Duranium adoption

Three discrete tracks. None of them needs Marathon-Shell C++ changes.

### Track 1 — Switch build infrastructure from `apk.static` rootfs to mkosi

Duranium uses mkosi + systemd-sysupdate. Our current `build-rootless-marathon.sh`
produces a single mutable rootfs.img by running `apk.static --root $ROOTFS add ...`.
Duranium produces A/B EROFS slots + UKI + dm-verity hashes via `mkosi build`
against an `mkosi.conf` recipe.

**Reference**: <https://gitlab.postmarketos.org/postmarketOS/duranium>

The Duranium build tool takes a (device, UI) tuple:

```
./build-image.py device-qemu-aarch64 ui-marathon --release=edge
```

This resolves `postmarketos-ui-marathon` from pmaports and builds an
immutable image. We already produce the meta-package; we'd need to:

1. Fork the `duranium` repo
2. Add a recipe entry for `ui-marathon` in `mkosi.images/`
3. Either contribute `postmarketos-ui-marathon` upstream to pmaports
   **OR** point the build at our local fork of pmaports

**Effort**: 1–2 engineering days. The hard part is contributing the meta-
package upstream (review/merge cycle with pmOS maintainers).

### Track 2 — Decommission `build-rootless-marathon.sh`

Once mkosi-based image build works, the shell script we've been using
becomes obsolete. Plan for a deprecation window where both build paths
exist; remove once Duranium-built images cover the same device matrix.

### Track 3 — App ecosystem

The Duranium model is **Flatpak as the primary install path**, with apk
reserved for OS-level packages. Marathon's bundled apps (browser,
calculator, calendar, …) live inside `marathon-shell`'s apk and run via
the in-tree `marathon-app-runner` + bubblewrap. That's fine for the
bundled set; for third-party apps the path is Flathub.

A `FlatpakAppSource` class in marathon-shell that surfaces installed
Flatpaks in the app grid alongside the bundled marathon apps would close
this. Estimated 300–500 LOC plus desktop-file parsing. Not blocking
Duranium adoption; can land later.

## Validation plan (post-migration)

When the mkosi pipeline lands:

1. Build a `device-qemu-aarch64 ui-marathon edge` Duranium image
2. Boot in QEMU with virtio-gpu-gl-pci + Venus
3. Verify:
   - `/usr` is read-only EROFS (try `touch /usr/x` → `EROFS`)
   - dm-verity is active (`dmsetup status | grep verity`)
   - Two `/usr` slots exist (`systemd-sysupdate list`)
   - `systemd-tmpfiles-setup.service` materialised the marathon-shell
     factory symlinks in `/etc`
4. Run the existing test matrix (Phase 1–9 from the validation session)
5. Trigger a fake update: stage a new image, call `systemd-sysupdate update`,
   reboot — verify rollback works if we corrupt the new slot's UKI

## What this gives us

| Gap (pre-migration) | Status post-migration |
|---|---|
| OTA framework | Closed (A/B + verified + auto-rollback) |
| Verified Boot | Closed (dm-verity + UKI signing) |
| App distribution + signing (partial) | Closed for Flatpak apps |
| Data-at-rest encryption | Closed (LUKS2 root) |
| Atomic upgrades | Closed |

Telephony depth, DRM video, NFC HCE, hardware-backed keystore,
biometrics, voice assistant, RCS — these remain industry-wide Linux
mobile gaps and aren't Duranium-solvable.

## Reading list

- [Duranium announcement (pmOS, Mar 2026)](https://postmarketos.org/blog/2026/03/17/introducing-duranium/)
- [Duranium image listing](https://duranium.postmarketos.org/images/)
- [Duranium repo](https://gitlab.postmarketos.org/postmarketOS/duranium)
- [pmaports — `postmarketos-ui-plasma-mobile` reference APKBUILD](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/master/main/postmarketos-ui-plasma-mobile/APKBUILD)
- [Flathub `.flatpakrepo` format](https://docs.flatpak.org/en/latest/repositories.html)
