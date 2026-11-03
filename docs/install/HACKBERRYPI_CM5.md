# Installing Marathon on the HackberryPi CM5

The HackberryPi CM5 boots from its microSD card, and the Marathon image is
the whole card. Nothing is written to the Compute Module itself, so taking
the card out is always a way back.

## What you need

- A microSD card, which will be erased, and a USB card reader.
- A Linux PC with `zstd` (or `xz`/`gzip`, for an image compressed that way).
- The Marathon release image for the HackberryPi CM5, or your own build
  (below). Check it against its `SHA256SUMS`.

## Flash

Find the card with `lsblk` (for example `/dev/sdb`), then:

```sh
./scripts/flash/flash-hackberry-cm5.sh /dev/sdX path/to/image.raw.zst
```

Without an image path it takes the newest build from
`$MARATHON_BUILD_DIR/duranium/mkosi.output/hackberrypi-cm5_marathon_edge/`.
The script refuses the disk the PC runs from, and asks for `FORCE` if the
target is not a removable device. It shows the card, waits for `YES`,
unmounts its partitions, and writes the image with `dd` (`sudo` asks for
your password).

## First boot

Put the card in the HackberryPi and switch it on.

- The first boot takes longer. The image grows to fill the card.
- On an A/B image (built with `MARATHON_IMAGE_LAYOUT=ab`), the data partition
  (`marathon_data`, holding `/var` and `/home`) is encrypted on this first
  boot with an empty passphrase, on the device, so that each card has its own
  key. See [ENCRYPTION.md](../ENCRYPTION.md#first-boot-pi). A single-root
  image has no encrypted partition.
- Setup (the OOBE) starts. On an A/B image, the PIN you choose there locks
  the data partition, and from the next boot on the splash asks for it. Type
  it on the HackberryPi's keyboard.
- If you forget the PIN, the data cannot be recovered. Flash the card again.

## Updates and recovery

- A/B images update one slot while running from the other. A slot that fails
  its first boot falls back to the previous one on the next start. See
  [OTA.md](../OTA.md).
- Settings → System → Erase all content resets an A/B image to setup
  ([FACTORY_RESET.md](../FACTORY_RESET.md)).
- If the card no longer boots, flash it again, or try another card.

## Building the image yourself

```sh
./scripts/build-hackberry-cm5-image.sh                            # single root
MARATHON_IMAGE_LAYOUT=ab ./scripts/build-hackberry-cm5-image.sh   # A/B, needs the update signing key (OTA.md)
```

See [BUILDING.md](../BUILDING.md).
