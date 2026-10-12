# Host end-to-end flows

`run.sh` boots the real `marathon-shell-bin` under Xvfb at the 390×844 design
canvas (`MARATHON_FORCE_DPI=160`), with its own HOME, runtime dir, session bus
and AT-SPI bus, launches the real apps through `marathon-app-runner`, and
drives it with xdotool: taps, swipes and the bottom-pill gestures.

Checks read the shell log (`MARATHON_DEBUG=1`), the shell's D-Bus API and the
accessibility tree (`a11y.py`, which also finds what to tap by name), so they
do not depend on pixel positions except for the on-screen keyboard and a few
gestures. Every step leaves a screenshot.

## Prerequisites

- `build-tests` built (`cmake --build build-tests`): the shell, the runner and
  the icon theme come from there. A run copies the binaries first, so a
  rebuild during the run does not affect it.
- The apps built and installed into a directory of their own:

  ```sh
  cmake -S apps -B /tmp/apps-build -G Ninja -DKEEL_QML=$KEEL_QML \
        -DMARATHON_APPS_DIR=/tmp/apps-install
  ninja -C /tmp/apps-build install
  ```

- `KEEL_QML` pointing at a Keel build's `qml` directory.
- Host tools: Xvfb, xdotool, ImageMagick (`import`, `magick`), dbus-daemon,
  gdbus, at-spi2-core (`at-spi-bus-launcher`, `at-spi2-registryd`),
  python3-gobject, sqlite3.

## Running

```sh
export KEEL_QML=~/Developer/Shipwright/build/keel/qml
export E2E_APPS_DIR=/tmp/apps-install
tests/e2e/run.sh                  # every flow, in order
tests/e2e/run.sh search appinfo   # some flows; an unlocked session is set up
```

Flows: `firstrun pin6 pin4 paging apps switcher notifications quicksettings
search appinfo keyboard settings alarm screenshot`. `E2E_APP_LIST` narrows the
apps flow (`"music:Music notes:Notes"`).

Output goes to `$E2E_OUT` (default `/tmp/marathon-e2e`): `results.txt`,
`shots/NN-step.png`, one shell log per session, and `xdg-open.log` with any
URL the shell or an app tried to open on the desktop. The exit status is
non-zero when a check fails.

## What the host does not have

The shell still talks to the host's system bus: NetworkManager, BlueZ,
ModemManager, UPower and logind. The flows never switch a radio or suspend,
because those calls would act on the host. Mail is skipped unless
`MarathonOS.Services` was built (it needs QMF).
