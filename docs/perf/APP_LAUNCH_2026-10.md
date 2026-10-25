# App launch, HackberryPi, 2026-10-25

Measured with an ftrace instance (process execs, forks and v3d GPU
submissions, `trace_clock=mono`) and taps through one persistent
`marathon-touchctl` device, so no uinput hotplug falls inside a launch. Times
are from the tap. "First frame" is the app's first GPU submission.

| App | Kind | Process started | First frame |
|---|---|---:|---:|
| Settings | Marathon (warm runner) | adopted spare | 0.31–0.44 s |
| Terminal | Marathon | 0.20 s | 0.29 s |
| Pacific | Keel host + WPE | 0.09 s | 0.80 s (page content 1.0 s) |
| KWeather | Flatpak (Qt) | 0.17 s | 0.75 s |
| Shortwave | Flatpak (GTK) | 0.31 s | 0.70 s warm, 4.85 s on the first launch after boot |
| Markor | Android | 0.09 s (`deckard-launch`) | 1.17 s, Android booting alongside |

Pacific scrolls Wikipedia at 60 fps: 252 frames over six flings, p95 17.1 ms,
two missed vblanks (the shell: 257 frames, none missed).

## Found and fixed

- A killed or crashed app could not be started again: the shell kept its
  task while the process was still exiting, and every tap "showed" the dead
  surface (r497).
- A Flatpak killed while frozen left its scope frozen with bwrap and
  xdg-dbus-proxy in it; forgetting an app now thaws its cgroup (r497).
- `flatpak run` without `--user` opened the empty system installation: a
  flatpak-system-helper call and gpgconf, gpg and gpgsm on every launch.
  Per-user apps now run with `--user`, which reaches bwrap about 90 ms
  sooner (r498).
- Every app with the storage permission built a MediaLibrary at startup,
  which bus-activated marathon-medialibd; only Gallery uses it, and it is now
  made on first use (r499).
- `marathon-shell-oom-pin` ran `find` every 5 s and the HackberryPi speaker
  keeper ran `bluetoothctl` every 10 s; both now wait on events.

## Open

- Pacific spends about 560 ms in its own process before starting WPE's
  network process: Qt enumerating plugins and loading Pacific's QML. That
  code is Shipwright's.
- Shortwave's first launch after a boot rebuilds its GStreamer registry
  (about 1.2 s of `gst-plugin-scanner`); the plugin files have fixed mtimes,
  so a device dependency (for example `/dev/video*`) is the likely trigger.
- The stock kernel lacks `CONFIG_INET_UDP_DIAG`, so each closed UDP socket
  sends a kernel worker to run `modprobe udp_diag`; linux-rpi-marathon r2
  enables it.
