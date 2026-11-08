# Getting started with Marathon OS

Marathon OS is a touch-first Linux phone OS built on postmarketOS. This page
takes you from download to a working phone. Building images yourself is in
the [README](../README.md#building-an-image).

## 1. Pick an image

| Device | What to use |
|---|---|
| Zinwa Q25 | Released images: [marathon-updates releases](https://github.com/patrickjquinn/marathon-updates/releases). Take the newest "Marathon OS … for the Zinwa Q25 (new install)". Install with [install/ZINWA_Q25.md](install/ZINWA_Q25.md). |
| HackberryPi CM5 | Build it (`scripts/build-hackberry-cm5-image.sh`), then follow [install/HACKBERRYPI_CM5.md](install/HACKBERRYPI_CM5.md). |
| Librem 5, PinePhone, Raspberry Pi 5 | Build it; see [Devices](../README.md#devices). |
| No phone | The QEMU simulator: `./scripts/build-qemu-image.sh --boot`. |

Check a download before you flash it:

```sh
sha256sum -c --ignore-missing q25-duranium-*.SHA256SUMS
```

Installing replaces the phone's own OS and erases its internal storage.

## 2. First boot

- The first boot takes a few minutes longer while the phone sets up its
  storage.
- Setup walks through language, Wi-Fi, a passcode, the look and text size,
  and a short practice of the gestures.
- The passcode unlocks the phone and also encrypts `/home`, so the boot
  splash asks for it before Marathon starts. On the Q25 the digits are on
  Alt.
- A forgotten passcode cannot be recovered: `/home` has to be erased by
  installing again.

## 3. Getting around

Everything starts from the pill at the bottom of the screen:

| Gesture | Does |
|---|---|
| Swipe left | Back |
| Swipe right | Forward, where there is one |
| Short swipe up | Home |
| Long swipe up | Active Frames, the running apps |
| Pull down | Quick settings |
| Touch and hold | Pilot, the assistant, when installed |

A swipe in from the left edge of the screen peeks at the Hub, where
notifications and messages collect.

The Q25's keys: the green key answers a ringing call or opens Phone, the red
key declines or ends a call and otherwise switches between Active Frames and
the app grid, and the back key is back.

## 4. Connect

- **Wi-Fi:** Quick settings or Settings > Wi-Fi.
- **Mobile data and calls:** put in a SIM; Settings > Mobile network shows
  the carrier, signal and mobile data. MMS is set up from the carrier where
  it can be; see [MMS.md](MMS.md).
- **Bluetooth:** Quick settings or Settings > Bluetooth.

## 5. Apps

- **Store:** installs Marathon apps and Android apps. Marathon's own apps
  (Phone, Messages, Email, Calendar, Maps, Camera, Gallery, Browser, Music,
  Notes and more) are already installed.
- **Android apps:** run through Deckard, with microG in place of Google
  Play services. Settings > Android apps starts Android, lists the
  installed apps and their permissions, and turns Google services on or
  off. See [ANDROID_APPS.md](ANDROID_APPS.md).
- Native GTK, libadwaita and KDE apps (Flatpaks) run too, in Marathon's
  theme and gestures.

## 6. Updates

Settings > Software updates checks for a new release. An update is a whole
signed system image: it downloads in the background, and the phone starts
it at the next restart. The previous system stays on the phone as a
fallback; if the new one fails to start three times, the phone goes back to
it. `/home`, your settings, Wi-Fi networks, Bluetooth pairings and the
modem's settings carry over. Details: [OTA.md](OTA.md).

## 7. For developers

- Logging in from a computer: Settings > Developer tools turns on SSH (off
  by default; images have no remote login until you do).
- Writing apps: [APP_DEVELOPMENT.md](APP_DEVELOPMENT.md) and the
  [Developer CLI](DEV_CLI.md).
- Device problems: [DEVICE_TROUBLESHOOTING.md](DEVICE_TROUBLESHOOTING.md).

## Help

Report problems at
[github.com/patrickjquinn/Marathon-Shell/issues](https://github.com/patrickjquinn/Marathon-Shell/issues),
with the device, the image version (Settings > About device) and what you did.
Known limitations for each Q25 release are in its release notes.
