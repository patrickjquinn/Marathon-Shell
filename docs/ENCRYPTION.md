# Data-at-rest encryption

The person's data sits on a LUKS2 partition that the quick PIN unlocks at
startup. The OS partitions stay plain: they are the signed, verified images
the updater writes, and they hold no personal data.

## What is encrypted

| Image | Encrypted partition | Holds | Created |
|---|---|---|---|
| Raspberry Pi 5 / HackberryPi CM5, A/B layout | `marathon_data` | `/var`, `/home` (as `/var/home`), the `/etc` overlay's upper layer | by the initramfs on first boot ([below](#first-boot-pi)) |
| QEMU dev-sim, A/B layout | `pmOS_root` | the whole root, `/var` and `/home` included | by duranium's systemd-repart on first boot |
| Single-root images (Librem 5, PinePhone, OnePlus 6, QEMU single) | none | | |

The container is LUKS2, aes-xts-plain64 with a 512-bit key. It is always
created on the device, so every phone has its own volume key; a container made
at image build time would share one key with every card flashed from that
image.

## Keyslots

A partition is in one of two states, and never both:

| State | Keyslot the person can use at boot | PBKDF |
|---|---|---|
| `open`: no PIN, opens by itself | the empty passphrase | pbkdf2, 1000 iterations (there is no secret to stretch) |
| `pin`: the quick PIN unlocks it | the PIN | argon2id, 512 MiB, 4 lanes, `--iter-time 1500` benchmarked on the phone when the PIN is set (cryptsetup lowers the memory if 512 MiB cannot meet the time) |

Alongside it there is always a **device key**: 64 random bytes in
`/var/lib/marathon-data-key/device.key` (root, 0600), in its own pbkdf2 slot.
The file lives on the encrypted partition, so it can only be read while the
partition is unlocked; it is useless at boot. It lets root change the PIN
without knowing the old one, which matters when the person has forgotten the
PIN but got in with their system password.

## Unlock at boot

**Pi (mkinitfs).** `packaging/ota/pi/mkinitfs/hooks-cleanup/50-marathon-ab.sh`
runs after the slot's root is mounted, before `switch_root`. For a LUKS
`marathon_data` it tries the empty passphrase, then asks for the PIN with
`plymouth ask-for-password`. The Marathon splash (`marathon.script`) shows
"Enter PIN" under the logo and a teal dot per character; a wrong PIN shows
"Wrong PIN. Try again", and it keeps asking until the partition opens. Each
try costs one argon2id run (about 1.5 s). With a PIN set, the first boot
attempt with the empty passphrase costs the same before the prompt appears.
Without Plymouth (`nosplash` on the kernel command line) unl0kr asks instead.

Input: the HackberryPi types the PIN on its keyboard, which needs the CM5's
dwc2 USB host in the initramfs (`device-hackberrypi-cm5-marathon`). Plymouth
reads only keyboards; it has no touch input, so a Plymouth digit pad for
touch-only phones is not possible. unl0kr, which pmOS already puts in the
initramfs, has an on-screen keyboard (full layout, not a digit pad) and is the
prompt a touch-only phone would use.

**QEMU (systemd in the initrd).** duranium's crypttab, `root
PARTLABEL=pmOS_root /dev/null luks,keyfile-timeout=0`, tries the empty
passphrase and then asks through `unl0kr-agent` (duranium masks Plymouth's
agent in favour of it). systemd-cryptsetup gives up after three wrong PINs and
the boot drops to the emergency target; restart to try again.

## Setting, changing and removing the PIN

The shell's `SecurityManager` runs
`pkexec /usr/libexec/marathon-data-key set|clear` with the PIN on stdin. The
polkit action `org.marathonos.shell.data-key` allows the active session;
Marathon's sandboxed apps run with `no_new_privs` and can't use pkexec.

| Helper | Does | Exit |
|---|---|---|
| `status` | prints `plain`, `open` or `pin` | 0 |
| `set` | the stdin line becomes the only passphrase | 0 done, 2 empty PIN, 3 not encrypted, 4 no device key and the empty passphrase doesn't open it, 1 other failure |
| `clear` | the empty passphrase becomes the only one | as above |

Each change adds the new slot, opens the partition with it, and only then
removes the other slots (except the device key's). A crash, a power cut or a
failed step leaves the old slot in place, often next to the new one, never
neither. LUKS2 writes its header twice, so a single header update is atomic.
The helper notes the result in `/var/lib/marathon-data-key/state`, which the
shell reads (with whether `$HOME` is on dm-crypt) for Settings.

- **OOBE:** the PIN is stored for the lock screen, then enrolled in the
  background. If that fails the phone still starts without a PIN, and
  Settings → Security says the data isn't locked.
- **Settings, change:** after the system password check the startup PIN
  changes first, and the lock screen's PIN only if that worked. A failure
  leaves both on the old PIN and the PIN dialog shows why.
- **Settings, remove:** the partition goes back to the empty passphrase, so
  the phone starts without asking. A device-bound key would be no stronger:
  with no hardware keystore it would sit unencrypted on the card next to the
  data. The empty passphrase is also the state new installs and reset phones
  start in, so the boot path has one "no PIN" case. The remove dialog warns
  that anyone holding the phone can then read the data.
- **Forgotten PIN, phone still unlocked** (system password at the lock
  screen): set a new PIN in Settings; the device key authorises it.
- **Forgotten PIN at boot:** the data can't be recovered. Erase or reflash.

Settings → Security shows "Locked by PIN", "Encrypted, not locked" or "Not
encrypted", from the shell's `dataEncryption` (`pin`, `open`, `off`: an A/B
Pi set up before encryption, which erasing fixes, or `none`: an image without
an encrypted partition). While a startup PIN is set, updates never restart
overnight by themselves (the phone would wait at the prompt, alarms
included); Settings offers "Restart now" only.

## First boot (Pi)

The image's `marathon_data` is an empty ext4 file system. On the first boot,
after growing it to the end of the card, the hook checks that it holds nothing
but `lost+found`, then runs `luksFormat` (empty passphrase), makes a fresh
ext4 inside and seeds it from the slot's `/var` and `/home`. If encryption
fails it formats the partition plain and boots unencrypted. A partition that
holds anything is never reformatted.

## Factory reset contract

"Erase all content" (another change) owns the request and the boot-time wipe.
After its wipe the data partition must be one of these, and the next boot then
goes to the OOBE without a PIN prompt; the PIN chosen there enrolls a slot:

1. **LUKS2, freshly formatted**: `luksFormat` with a new volume key (a
   `luksErase` alone leaves a container nothing can open), exactly one
   keyslot holding the empty passphrase, and an empty ext4 inside:
   ```sh
   echo | cryptsetup -q --force-password luksFormat --type luks2 \
       --pbkdf pbkdf2 --pbkdf-force-iterations 1000 /dev/disk/by-partlabel/marathon_data
   echo | cryptsetup open /dev/disk/by-partlabel/marathon_data marathon_data
   mke2fs -q -F -t ext4 /dev/mapper/marathon_data
   ```
2. **A plain ext4 file system with nothing but `lost+found`**: the initramfs
   encrypts it on that boot as on first boot. This is how a phone set up
   before encryption gets it.

The device key, the state file and the `.marathon-seeded` marker all live on
the partition and go with it. A container that doesn't open with the empty
passphrase makes the next boot ask for a PIN nobody knows, so never leave one
behind. On QEMU, duranium's factory reset (`FactoryResetRequest=yes` on
`pmOS_root`) recreates the LUKS root with the empty key, which matches case 1.

## Existing devices and updates

- **An update from an image before this change:** `marathon_data` holds data
  and a `.marathon-seeded` marker, so it stays unencrypted and untouched.
  Settings says "Not encrypted" and suggests erasing to start again with
  encryption. The quick PIN works as before (the helper exits 3). There is no
  in-place conversion: `cryptsetup reencrypt` would need room for the header
  and a crash-safe resume path in the initramfs, which isn't worth the risk
  to people's only copy of their data yet.
- **Rolling back:** an image from before this change can't mount an encrypted
  `marathon_data`. sysupdate never installs an older version, and both slots
  of an encrypted phone hold versions that know about encryption, so this
  only happens if someone flashes an old boot slot by hand.
- **Trial boots** (Pi): the initramfs guard reboots a trial boot that is still
  there after 180 s, so the PIN must be typed within three minutes; otherwise
  the committed slot boots and asks again. An update installed before a
  power-off is tried on the next boot, so the PIN is asked for twice then.

## How strong it is

There is no hardware keystore, so someone who copies the storage can guess
the PIN offline as fast as their hardware allows. Each guess costs one
argon2id run sized to about 1.5 s on the phone. A desktop GPU or a large CPU
manages perhaps 5 to 50 guesses a second at these settings (argon2id is
bound by memory bandwidth, which is where they beat a phone), which puts all
one million 6-digit PINs at roughly six hours to a few days, half that on
average, and a 4-digit PIN at minutes. This protects a lost or stolen phone from casual reading and from
anyone without time and hardware. It does not stop a determined attacker who
images the storage.

- A longer passphrase would hold out: the helper and the boot prompt accept
  any text, and the HackberryPi can type it. Settings ties the startup secret
  to the quick PIN, which is digits only; a separate startup passphrase needs
  its own Settings flow and is not done.
- There is no wipe after a number of wrong PINs at boot, only the argon2id
  cost per try. A wipe would turn a mistyped PIN into lost data.
- While the phone runs, root can read everything, including the device key
  and the volume key in memory.
- The `open` state encrypts without protecting; what it buys is a reset that
  only has to destroy the keyslots.

## Recovery

If the PIN prompt never appears on the Pi:

1. Put the card in another computer and add `nosplash` to `cmdline.txt` on
   the booting slot's boot partition (`marathon_<version>_boot`); unl0kr then
   asks instead of Plymouth.
2. Or remove the PIN from another Linux machine, which makes the phone start
   without asking:
   ```sh
   read -rs PIN    # type the PIN, then Enter
   # The PIN authorises a new slot whose passphrase is empty.
   printf '%s\n\n' "$PIN" | sudo cryptsetup luksAddKey -q --force-password \
       --pbkdf pbkdf2 --pbkdf-force-iterations 1000 /dev/sdX6
   ```
   Then set the PIN again in Settings, which removes that slot.
