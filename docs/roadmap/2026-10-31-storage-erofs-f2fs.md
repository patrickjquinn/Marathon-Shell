# Storage layout: read-only erofs OS, f2fs user data

Status: proposed (2026-10-31). Applies to every Duranium target (Pi 5,
HackberryPi CM5, Q25 and the rest); best done once the Q25 pipeline image
is stable.

## Today

Every target ships one writable ext4 root. On the Q25 that root is an ext4
image file on an ext4 carrier inside `userdata`, opened through a loop
device with direct I/O.

## Proposal

1. **OS: erofs + dm-verity, read-only.** mkosi and systemd-repart already
   build a signed verity erofs root (`Format=erofs`, `Verity=data`, hash and
   signature partitions; mkosi puts the roothash on the kernel command line).
   Check the current compressor guidance first: in September 2026 the kernel
   disabled erofs LZ4 rolling decompression over a data-corruption risk.
2. **User data: f2fs** for `/home` and `/var`, per device and only after
   power-cut testing on that device; ext4 stays the fallback. f2fs's fsck is
   weaker than ext4's after a sudden power loss, and the Q25 has had
   watchdog resets that look like one to the filesystem.
3. **Updates: A/B slots with systemd-sysupdate**, rolled back automatically
   through boot counting (the Q25 bless unit already exists).

## What it buys

- Faster boot and app launch: compressed, random-read-friendly OS image.
- An OS that cannot be corrupted by crashes, bad writes or flash bit-rot;
  verity makes it tamper-evident and is the base for verified boot.
- Factory reset is wiping the data partition.
- Smaller OTA downloads (compression, dedupe) and atomic, rollback-safe
  updates.
- Fewer OS writes and log-structured data writes: longer flash life, faster
  small random writes on SD cards and eMMC (app installs, Deckard's Android
  data on the HackberryPi's SD card).

## Acceptance

- Boot time, cold app launch and app-install time measured before and after
  on the HackberryPi and the Q25.
- Repeated hard power cuts during writes on each device with f2fs data before
  it becomes that device's default.
- An A/B update and a forced rollback on each device.

## References

- erofs status: <https://erofs.docs.kernel.org/en/latest/gsoc.html>,
  <https://static.sched.com/hosted_files/ossjapan2025/86/EROFS_JP25.pdf>
- f2fs caveats: <https://wiki.archlinux.org/title/F2FS>
- Verity root with mkosi: <https://github.com/systemd/mkosi/blob/main/docs/root-verity.md>,
  <https://man.archlinux.org/man/systemd-repart.8.en>
