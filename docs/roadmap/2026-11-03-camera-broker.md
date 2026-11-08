# One camera broker: the app in front gets the camera

Status: proposed (2026-11-03). Long-term version of the camera sharing
Marathon and Deckard ship today.

## Today

libcamera owns the sensors, and every client opens them itself: Marathon
Camera (and any Keel app using Qt Multimedia) through libcamerasrc in its own
process, Deckard's Android apps through `deckard-camera`, which runs the same
libcamerasrc path for Deckard's camera HAL (Marathon-Deckard
`docs/camera.md`). On the Q25 both sensors share one media device, so one
camera streams at a time, and libcamera's media-device lock decides who has
it.

What makes it feel like iOS today:

- Marathon apps release the camera when they leave the foreground: Qt's
  `QCamera::stop()` takes libcamerasrc to `NULL`, which releases it, and the
  Camera app stops when `applicationActive` goes false, which the shell
  sets on home, in the switcher and with the screen off or locked.
- Android apps close the camera when they pause (Camera2 guidance), and
  cameraserver arbitrates between Android clients by its own priority.
- `deckard-camera` waits up to 1.5 s for a camera another process is
  releasing, so an Android app brought forward does not lose the race with
  the app that just left.

What it cannot do:

- Take the camera from a client that keeps it: an Android app that does not
  close on pause, or a Marathon app that keeps streaming while inactive.
- Share one stream: two clients cannot preview at once even where the
  hardware could (one sensor, two consumers).
- Show one camera-in-use indicator or keep one per-app permission record.

## Proposal

One host service owns libcamera and hands out streams; nothing else opens
the camera.

1. **PipeWire with the libcamera SPA plugin** owns the sensors. WirePlumber
   policy decides who gets a camera node, by foreground first: the shell
   tells it which app is in front (`Navigation1` already knows), and a node
   is taken from a background client by stopping its stream, which a client
   sees as the camera going away (Android: `ERROR_CAMERA_DISCONNECTED`, as
   on iOS an interruption).
2. **Access through the camera portal.** The shell implements
   `org.freedesktop.impl.portal.Settings` and `FileChooser` today, not the
   camera; it adds `org.freedesktop.impl.portal.Camera`
   (`AccessCamera`), answered from Marathon's permission store and prompt,
   and xdg-desktop-portal hands the app a PipeWire remote limited to camera
   nodes (`OpenPipeWireRemote`). Deckard asks with its per-package identity
   (Marathon-Deckard `docs/design.md`, identity broker), so Android apps get
   the same prompt, record and revocation.
3. **Clients move to PipeWire.** Qt Multimedia's GStreamer backend uses
   `pipewiresrc`; `deckard-camera` swaps `libcamerasrc` for `pipewiresrc` and
   keeps its socket and HAL unchanged. The camera-in-use indicator reads the
   broker's active streams.
4. **One stream, many consumers** where it helps: the broker can serve a
   preview to two clients from one capture.

## Order of work

1. Build PipeWire with the libcamera SPA plugin on the camera devices and
   check that SoftISP's GPU debayer and the Q25 patches work under it.
2. Camera portal in the shell, backed by the permission store.
3. Foreground policy in WirePlumber, fed by the shell.
4. Move Marathon Camera, then `deckard-camera`, to `pipewiresrc`.

Until then the rules in "Today" hold.
