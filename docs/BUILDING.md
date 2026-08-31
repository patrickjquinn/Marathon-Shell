# Building a Marathon OS image from a cold clone

This document walks a new contributor through producing the same r180
HackberryPi CM5 image that's currently on the test devices, starting
from nothing. **Tested against the state at commit `<this commit>`
on 2026-06-20.**

If you only want to build the marathon-shell APK against an existing
image, jump to *Iterating on marathon-shell* at the bottom.

---

## 0. Prerequisites

- Linux host with `sudo`, `podman` (rootless), `git`, `python3`, `gcc`, `dtc`.
- Fedora 41+ / Arch / Debian trixie recommended.
- ~30 GB free in `$HOME` for build artefacts.
- A microSD card + USB reader for the HackberryPi CM5 flash.

The build uses `podman` for transient Alpine containers (one per APK).
It does NOT need Docker, KVM, or root containers.

## 1. Repository layout

Marathon's image build pulls from TWO git trees:

```
$HOME/Developer/Marathon-Shell/        # github.com/patrickjquinn/Marathon-Shell (ux-overhaul)  ← this repo
  └── packaging/                       #   aports + duranium patch series (was Marathon-Image)
$HOME/duranium-build/duranium/         # postmarketos/duranium fork with Marathon patches
$HOME/duranium-build/mkosi-src/        # systemd/mkosi at a known-good tip
```

The first is a normal git clone; packaging/ is in-tree since the
Marathon-Image merge (see [MONOREPO_MIGRATION.md](MONOREPO_MIGRATION.md)).
The second is the awkward one: upstream `postmarketos/duranium` is not
Marathon-owned, and Marathon's divergence (Pi 5 boot pipeline, layer-2
device overlay injection, the device-APK builder script) is not in the
upstream. We carry it as a patch series in
[`packaging/pipeline-patches/`](../packaging/pipeline-patches/) and apply
it via the bootstrap script.

## 2. Bootstrap duranium with Marathon's patches

```sh
cd $HOME/Developer/Marathon-Shell
./packaging/pipeline-patches/bootstrap.sh
```

This clones `postmarketos/duranium` at the pinned merge-base commit
into `$HOME/duranium-build/duranium/` and applies the 10-patch series
in order. Re-run `bootstrap.sh /some/other/path` to stage a second
copy.

If upstream has drifted past the pinned commit (the script's
`PINNED_COMMIT` doesn't apply cleanly), you'll need to rebase the
patches against the new tip — see *Refreshing the patch series*
below.

## 3. mkosi

`bootstrap.sh` (step 2) clones mkosi into `$HOME/duranium-build/mkosi-src`
at the pinned commit and stops there — mkosi runs straight from the
checkout, no install step needed. The build scripts prepend
`$HOME/duranium-build/mkosi-src/bin` to `PATH`.

The pinned mkosi commit is recorded in `bootstrap.sh`'s `MKOSI_COMMIT`
variable. Bump after a successful build against a newer mkosi tip.

## 4. Set up secrets

Two files contain secrets and **must never be committed**:

- A NetworkManager keyfile so the device WiFi-autoconnects on first boot.
- An `~/.ssh/id_ed25519.pub` so you can SSH into the device.

The keyfile lives at `$HOME/.marathon-secrets/SKYZMTGV.nmconnection.raw`
(WiFi SSID is the filename stem; rename if your network is different).
A minimal example:

```ini
[connection]
id=SKYZMTGV
type=wifi
interface-name=wlan0
permissions=

[wifi]
mode=infrastructure
ssid=SKYZMTGV

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=YOUR_PASSWORD_HERE

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
```

`chmod 600 $HOME/.marathon-secrets/SKYZMTGV.nmconnection.raw`. The
build pipeline strips any leading `[sudo]` prompts from this file
before copying it into `duranium-build/duranium/mkosi.extra/etc/NetworkManager/system-connections/`.

For SSH, the build copies `~/.ssh/id_ed25519.pub` into the image's
`/usr/share/factory/home/user/.ssh/authorized_keys`. If you don't have
an ed25519 key:

```sh
ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519
```

## 5. Sudo helper

Several pipeline steps need `sudo` (loop-mount, sfdisk, dd). The build
expects a passwordless wrapper via `SUDO_ASKPASS`. Create:

```sh
cat > /tmp/askpass.sh <<'EOF'
#!/bin/sh
echo YOUR_SUDO_PASSWORD_HERE
EOF
chmod 700 /tmp/askpass.sh
```

Then run all `sudo` calls with `SUDO_ASKPASS=/tmp/askpass.sh sudo -A …`.
The build scripts honour this pattern.

## 6. Build the four Marathon APKs

In dependency order:

```sh
cd $HOME/duranium-build/duranium
PATH=$HOME/duranium-build/mkosi-src/bin:$PATH

# 1/4 marathon-base-config — sysctl, oom, slice, systemd presets.
./marathon-extras/build-marathon-base-config-apk.sh

# 2/4 marathon-shell — the shell binary + app set. Pulls source from
# $MARATHON_SHELL_SRC instead of cloning github when set.
MARATHON_SHELL_SRC=$HOME/Developer/Marathon-Shell \
  ./marathon-extras/build-marathon-shell-apk.sh

# 3/4 device-raspberry-pi5-marathon — generic Pi 5 / CM5 base.
./marathon-extras/build-device-apk.sh device-raspberry-pi5-marathon

# 4/4 device-hackberrypi-cm5-marathon — HackberryPi enclosure layer.
./marathon-extras/build-device-apk.sh device-hackberrypi-cm5-marathon
```

Each script bootstraps abuild in a transient Alpine container, builds
the .apk with a throwaway signing key, and drops it into
`mkosi.packages/`.

## 7. Build the image

```sh
cd $HOME/duranium-build/duranium
PATH=$HOME/duranium-build/mkosi-src/bin:$PATH \
  MARATHON_SHELL_SRC=$HOME/Developer/Marathon-Shell \
  ./scripts/build-image.py device-raspberry-pi5-marathon ui-marathon --release=edge
```

Output lands at:

```
$HOME/duranium-build/duranium/mkosi.output/raspberry-pi5-marathon_marathon_edge/raspberry-pi5-marathon_marathon_edge_*.raw
```

~5 minutes on a warm host. mkosi.workspace + mkosi.cache grow ~10 GB
between builds; clean them if disk is tight:

```sh
rm -rf $HOME/duranium-build/duranium/mkosi.workspace
sudo -A rm -rf $HOME/duranium-build/duranium/mkosi.output/raspberry-pi5-marathon_marathon_edge
```

## 8. Flash to SD card

```sh
# /dev/sda is the typical USB SD-reader path. Verify via lsblk first.
sudo -A dd \
  if=$HOME/duranium-build/duranium/mkosi.output/raspberry-pi5-marathon_marathon_edge/raspberry-pi5-marathon_marathon_edge_*.raw \
  of=/dev/sda \
  bs=16M oflag=direct conv=fsync
sudo -A sync
```

~5m24s at 20 MB/s for a 6.4 GB image. Then pop the card into the
HackberryPi CM5 and power on.

## 9. Verify the device boots

After ~10 s the Marathon Plymouth splash should appear, followed by
the lock-screen and (on first boot) the OOBE. The device WiFi-
autoconnects via the keyfile from step 4. Find its IP via:

```sh
ssh-keyscan -t ed25519 marathon.local >> ~/.ssh/known_hosts
ssh user@marathon.local 'hostname; uptime'
```

mDNS resolution can take 30–60 s after first boot.

---

## Iterating on marathon-shell only

If you already have a working image and just need to rebuild the shell
APK with local edits:

```sh
cd $HOME/duranium-build/duranium
PATH=$HOME/duranium-build/mkosi-src/bin:$PATH \
MARATHON_SHELL_SRC=$HOME/Developer/Marathon-Shell \
  ./marathon-extras/build-marathon-shell-apk.sh
```

The APK lands in `mkosi.packages/marathon-shell-1.0.0-r<N>.apk`. To
ship it without rebuilding the full image, `scp` it to the device and
`apk add --allow-untrusted <file>`. The shell needs to be restarted
(easiest: `sudo reboot`).

## Refreshing the patch series

If the bootstrap fails because the pinned commit is too old to clean-
apply, follow this sequence:

```sh
cd $HOME/duranium-build/duranium
# Fetch the new upstream tip.
git fetch origin
git rebase origin/main
# Resolve any conflicts in the standard git rebase loop.

# Regenerate the patch series and refresh the pinned commit.
cd $HOME/Developer/Marathon-Shell
rm packaging/pipeline-patches/00*.patch
cd $HOME/duranium-build/duranium
git format-patch -o $HOME/Developer/Marathon-Shell/packaging/pipeline-patches origin/main..HEAD
# Update PINNED_COMMIT in packaging/pipeline-patches/bootstrap.sh to the
# new `git merge-base origin/main HEAD`.

cd $HOME/Developer/Marathon-Shell
git add packaging/pipeline-patches/
git commit -m "chore(pipeline-patches): refresh against duranium <new-sha>"
```

## Notes for porters

- **The HackberryPi-specific `usercfg-hackberrypi.txt`** controls
  panel + battery + USB OTG host mode. To port to a different Pi 5
  enclosure, write a sibling aport (e.g. `device-MYBOARD-cm5-marathon`)
  with its own `usercfg-<board>.txt` and DT overlay; `device-raspberry-
  pi5-marathon`'s usercfg.txt's tail `include usercfg-hackberrypi.txt`
  line is the load point. Pi firmware silently skips missing includes.
- **The cgroup_enable=memory kernel cmdline override** is mandatory for
  PSI memory pressure and Phase B freezer policy to work. It's set in
  the patch series (patch 0009). Don't drop it.
- **`marathon-extras/StoreApp.qml`** is a deploy-time override of the
  Store app's QML — it overrides the version compiled into
  marathon-shell's libstoreplugin.so resource bundle via the install
  in `mkosi.images/base/mkosi.postinst`. Lets you iterate Store
  without rebuilding the (slow) marathon-shell APK. The canonical
  pre-compile copy lives in `Marathon-Shell/apps/store/StoreApp.qml`;
  when changes are stable, sync them back to that canonical path so
  the next marathon-shell APK build embeds them. Eventually the
  override block should be retired in favour of the canonical copy.
