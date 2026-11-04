# Security model: app sandboxing

How Marathon confines apps, as the code does it today. Each layer names
the file that implements it. Where a layer has a gap, the gap is listed.

## Who is trusted

| App kind | How it runs | Confinement |
|----------|-------------|-------------|
| Marathon QML apps (bundled and `.marathon` packages) | `bwrap` + `marathon-app-runner`, launched by `Tasks` (`crates/marathon-shell-native/src/tasks/launch.rs`) | bwrap, seccomp and Landlock in the runner, security-context Wayland socket, shell D-Bus permission gate |
| Marathon WebEngine apps (Browser, Maps) | as above | as above, without the namespace rules and Landlock's file rules, plus Chromium's own sandbox inside |
| Flatpak apps | `flatpak run`, launched by the compositor | Flatpak's sandbox and portals; Flatpak's security-context socket |
| Sailfish apps that declare Sailjail permissions | `marathon-keel-host --sailjail` | bwrap built from the Sailjail permissions (`tools/marathon-app-runner/sailjail.cpp`) |
| Other Sailfish apps | `marathon-keel-host` | none, like native apps |
| Native apps (distro packages, `.desktop` files) | plain process, launched by the compositor | none |

### Native apps are trusted

A native app is a distro package installed by root through `apk`, the
same trust as the shell itself. It runs unconfined, as it does under
GNOME, Phosh and Plasma Mobile. Marathon does not pretend otherwise:
there is no partial sandbox around native apps.

Third-party software should come as a Flatpak (or a `.marathon` package),
not as a native package. A native app cannot be confined usefully without
knowing which of the user's files it needs; Flatpak solves that with
per-app manifests and portals, and reinventing it per app is out of scope.

`tools/marathon-sandbox` (Landlock + seccomp around native apps, opt-in
through `MARATHON_ENABLE_SANDBOX`) was removed because it protected
nothing it claimed to and, switched on, would have broken the apps it
wrapped:

- Landlock left all of `$HOME` readable and `~/.config`, `~/.cache` and
  `~/.local/share` writable. That is where the shell's settings, app
  permissions, notification store and keyrings live.
- Its network rule allowed TCP 80, 443 and 53 to apps without the network
  permission. Native apps never had that permission, so every native app
  would have lost IMAP, XMPP and the like, while UDP stayed open because
  Landlock cannot filter it.
- The Librem 5 and PinePhone kernels are built without Landlock, so on
  those devices only the seccomp half would have run.
- The seccomp filter did not check the syscall architecture.
- Each app got a private `dbus-run-session` bus (policy: own and eavesdrop
  on anything), which cut it off from portals, notifications, the Secret
  Service and the shell, while the real session bus stayed reachable
  through the writable `$XDG_RUNTIME_DIR`.
- Around `marathon-app-runner` it applied seccomp and Landlock before
  `bwrap`, which then could not mount and failed every launch. Marathon
  apps now get both from the runner itself, after bwrap (layer 2).

## Layer 1: bwrap around Marathon apps

`sandbox::argv` (`crates/marathon-shell-native/src/sandbox.rs`) builds the
sandbox for each launch and for the warm runner pool (`tasks/pool.rs`):

- New user, PID, UTS, IPC and cgroup namespaces, and a network namespace
  with only loopback unless the app holds the `network` permission.
- Read-only `/usr`, `/etc`, `/lib*`, `/bin`, `/sbin`, `/sys`; a fresh
  `/dev` with only the DRM render node; `/tmp`, `/dev/shm` and `$HOME`
  as tmpfs, except that an app with `terminal` gets
  `~/.local/share/marathon-apps/<app>/home` as its `$HOME`.
- Read-write only `~/.local/share/marathon-apps/<app>` and
  `~/.cache/marathon-apps/<app>`; the user directories only with the
  `storage` permission.
- `$XDG_RUNTIME_DIR` is a private tmpfs (mode 0700) holding only the
  session bus (`bus`), PipeWire (`pipewire-0`, not `pipewire-0-manager`),
  PulseAudio (`pulse/native`), dconf's change flag (`dconf/`) and the
  app's own Wayland socket (layer 3). Apps with `system` (Settings) and
  pool spares also see the Store handler's `marathon-store-state/`
  read-only, and with `MARATHON_STARTUP_TIMING` set every runner sees
  `marathon-startup.log`.
  The keyring, systemd's user manager, `at-spi`, `doc`, other apps' Keel
  sockets and every other socket there are out of sight. A Keel app's
  host socket stays in its own tmpfs.
- `--die-with-parent`, `--new-session`.

`MARATHON_DISABLE_SANDBOX=1` (or a missing `bwrap`) runs apps without any
of this, and the shell logs a warning for every such launch.

Gaps:

- There is no `xdg-dbus-proxy`: an app can call any session bus service,
  and any system bus service its policy allows (`/run/dbus` is bound). The
  shell's own services check the caller (layer 5); other services do not
  know which app is calling: an app can, for example, read every Secret
  Service item or write any dconf key.
- A session bus anywhere but `$XDG_RUNTIME_DIR/bus` (the
  `dbus-run-session` fallback in `marathon-shell-session`) is not bound;
  apps reach it only if it is an abstract socket and they share the
  network namespace, as before.
- Screen readers cannot see Marathon apps: the accessibility bus is not
  bound, because unfiltered it would let an app read every other app's
  accessible text.
- The pool runner is spawned before its app is known, so it binds the
  parent `marathon-apps` data and cache directories and shares the network.
  A spare has the user directories or not, and becomes only an app with
  the `storage` permission or only one without. User-installed, WebEngine,
  camera and terminal apps never use the pool.

## Layer 2: seccomp and Landlock inside the runner

bwrap mounts first; then `marathon-app-runner` confines itself at the top
of `main()`, before Qt, any thread or any app code
(`crates/marathon-app-native/src/confine.rs`, called through
`marathon::runner::confine`). A pool spare does it at start-up, with the
spare's paths. The runner does this only when the shell's bwrap set
`MARATHON_SANDBOX_WRITABLE`, so `MARATHON_DISABLE_SANDBOX=1` runs apps
without either. Both are best effort: a failure is logged in the app's
journal under `sandbox` and the app still starts.

**seccomp** (the `seccompiler` crate, no libseccomp). A deny list in the
style of Flatpak's, every other syscall allowed. The BPF program checks
the syscall architecture first and kills the process on a mismatch, so a
32-bit compat syscall cannot slip past the rules. `/proc/<pid>/status`
shows `Seccomp: 2`.

- EPERM: `syslog`, `acct`, `quotactl`, `add_key`, `keyctl`,
  `request_key`, `perf_event_open`, `bpf`, `userfaultfd`, `kexec_load`,
  `init_module`, `finit_module`, `delete_module`, `mount`, `umount2`,
  `pivot_root`, `setns`; `ioctl` with `TIOCSTI` or `TIOCLINUX`;
  `personality` other than `PER_LINUX` or a query.
- EPERM, except for WebEngine apps and apps with `camera`: `unshare`,
  `chroot`, and `clone` with `CLONE_NEWUSER`, so an app cannot make a user
  namespace and gain capabilities in it. libcamera runs an IPA module
  whose signature it cannot verify in a user and network namespace of its
  own.
- ENOSYS, so callers fall back: `clone3` (seccomp cannot read its flags),
  the new mount API (`open_tree`, `move_mount`, `fsopen`, `fsconfig`,
  `fsmount`, `fspick`, `mount_setattr`) and `io_uring_setup`.

**Landlock** (the `landlock` crate), probed at run time up to ABI 6:

- Writes, file creation, removal, truncation and device ioctls only in
  what the shell's bwrap made writable: the app's home (its own tmpfs;
  an app with `terminal` keeps it in its data directory), its data and
  cache directories (a spare: the parent `marathon-apps` ones), `/tmp`,
  `/dev/shm`, the private `$XDG_RUNTIME_DIR`, and the user directories
  with the `storage` permission. Files under `/dev` (render node, camera,
  pty, `/dev/null`) and `/proc` may be written to, and devices under
  `/dev` take ioctls. Everything else is read-only. The shell passes the list in
  `MARATHON_SANDBOX_WRITABLE`.
- Scopes (ABI 6, Linux 6.12): no signals to processes outside the app,
  and no connecting to abstract Unix sockets made outside it. That matters
  for apps with `network`, which share the host's network namespace and so
  its abstract sockets. The abstract scope is left off when the session
  bus itself is abstract.
- On older ABIs the crate drops what the kernel lacks. The Librem 5 and
  PinePhone kernels have no Landlock; there the runner logs
  `Landlock not enforced` and only seccomp applies.

WebEngine apps keep `unshare`, `chroot` and `CLONE_NEWUSER` for Chromium's
own sandbox (layer 4), and get only Landlock's scopes: QtWebEngine keeps
its profile under the tmpfs home, which the file rules would forbid.

Gaps:

- Landlock's file rules add little to bwrap's mounts, which already decide
  what is writable. They are a second fence if a mount is ever bound
  read-write by mistake.
- Connecting to a path socket is not restricted (that is Landlock ABI 9,
  Linux 7.1); the private runtime dir decides which sockets exist.
- No socket-family filter (Flatpak's allows only `AF_UNIX`, `AF_INET`,
  `AF_INET6` and `AF_NETLINK`) and no `ptrace` rule; the PID namespace
  already limits `ptrace` to the app's own processes.
- In Terminal, writes to the home directory outside the user directories
  fail.

## Layer 3: security-context-v1 Wayland sockets

The compositor implements `wp_security_context_v1`
(`shell/src/wayland/securitycontextv1.{h,cpp}`).

**Marathon apps.** Before each launch `Tasks` asks the
compositor (`WaylandCompositor::openSandboxSocket`) for a socket at
`$XDG_RUNTIME_DIR/marathon-sandbox/<instance-uuid>`. The compositor tags
every client that connects there with engine `org.marathonos.AppRunner`,
the app id and the instance id. bwrap mounts that socket over
`$XDG_RUNTIME_DIR/marathon-wayland-0` (so `WAYLAND_DISPLAY` is unchanged)
and the rest of the private runtime dir holds neither `marathon-sandbox/`
nor the compositor's own socket, so the app can neither reach the
unrestricted socket nor connect through another app's socket. The
listener closes when the app's process exits. A pool spare gets a socket
with no app id; adoption fills it in (`assignSandboxApp`). If the socket
cannot be created, the app is not launched.

The listener is created in the compositor process rather than through the
protocol because the launcher already lives there: there is no separate
sandbox engine to hand fds to, no extra connection, and the socket's
lifetime follows the process the shell itself started. The resulting
state is the same as a protocol-registered listener.

**Flatpak.** `flatpak run` (1.15.6 and later; 1.16 fixed a regression
with compositors that set `WAYLAND_DISPLAY` for the apps they launch, as
this one does) registers its own listener
through the protocol with engine `org.flatpak` and the Flatpak app id, and
hangs up `close_fd` when the sandbox exits; the compositor keeps the
listener after Flatpak destroys the context object, as the protocol
requires. The compositor only adds `--socket=wayland`.

**What a tagged client cannot see.** The global filter
(`WaylandCompositor::filterGlobal` → `SecurityContextManagerV1::allowsGlobal`)
hides privileged globals from tagged clients. The list follows sway's
`is_privileged()`: screen capture (wlr-screencopy, ext-image-copy-capture
and its sources, wlr-export-dmabuf), clipboard snooping (wlr and ext
data-control), input injection and capture (input-method v1/v2, virtual
keyboard and pointer, keyboard-shortcuts-inhibit, transient seat), shell
surfaces (layer-shell, session-lock), window and workspace enumeration
(foreign-toplevel, ext-workspace), output control (output management and
power, gamma, xdg-output, DRM lease) and the security-context manager
itself, so a sandboxed client cannot mint a less restricted context. Of
these the compositor currently advertises only the security-context
manager; the rest are filtered by interface name so a capture or
input protocol added later is hidden from sandboxed clients from its first
commit.

**App identity.** A sandboxed client is the app its context names,
whatever `xdg_toplevel.app_id` it sets, and its surfaces match that
app's launch even when its process is not a descendant of the launched
one (`Tasks::window_mapped`, `tasks/launch.rs`). Only an app the
shell runs may open a dialog window over others.

Gaps: Sailfish apps under `marathon-keel-host` and native apps connect on
the unrestricted socket.

## Layer 4: Chromium's sandbox inside WebEngine apps

Browser and Maps run QtWebEngine without `--no-sandbox`. Chromium's
layer-1 namespace sandbox (a further user, PID and network namespace per
renderer) nests inside bwrap, and its renderers run under its layer-2
seccomp-bpf policy (`/proc/<renderer>/status` shows `Seccomp: 2`). QtWebEngine
runs the GPU in the browser process, so there is no separate GPU sandbox
to fail. Verified on a Fedora 7.1 kernel with bwrap 0.12 and QtWebEngine
6.11.2 using the exact namespace set above; the device kernels all have
`CONFIG_USER_NS`, `CONFIG_PID_NS`, `CONFIG_NET_NS` and
`CONFIG_SECCOMP_FILTER`, and Alpine's `qt6-qtwebengine` carries the musl
sandbox patches its Chromium uses.

Flatpak'd Chromium needs zypak because Flatpak's seccomp filter forbids
nested user namespaces; the runner's filter (layer 2) leaves user
namespaces, `unshare` and `chroot` to WebEngine apps, so the namespace
sandbox works as on a desktop.

If a device build ever fails here, `QTWEBENGINE_CHROMIUM_FLAGS` in the
shell's environment replaces the default flags for every WebEngine app.

## Layer 5: the shell's D-Bus permission gate

Shell services on the session bus (`crates/marathon-shell-native/src`, `ipc::admit`)
resolve the caller's app from its PID (the launcher's PID map, then the
process ancestry up to the shell) and check the app's granted
permissions before acting. See `docs/PERMISSION_GUIDE.md`.

## Remote login over SSH

Nothing listens on port 22 on a release image: the preset disables
`sshd.service`, the user's password is locked (`!`) and root has no key.
There are two ways in.

**Developer images** are built with `MARATHON_DEV_SSH_KEY` (pipeline
patch 0050). That key logs in as root and as the user, key only, and sshd
runs from the first boot.

**Remote connection** (Settings > Developer tools) is the owner's switch,
as in Sailfish OS. Turning it on, or saving a new password, takes the
quick PIN where one is set. The shell then runs
`pkexec /usr/libexec/marathon-remote-connection on` with the password on
stdin (polkit action `org.marathonos.shell.remote-connection`, active
session only; sandboxed apps can't use pkexec). The helper:

- sets the password of the caller's own account (`PKEXEC_UID`, never
  below 1000) with `chpasswd -c SHA512`;
- writes `/etc/ssh/sshd_config.d/50-marathon-remote-connection.conf`:
  passwords on, `PermitRootLogin prohibit-password`, `MaxAuthTries 3`,
  `LoginGraceTime 30`, `PerSourcePenalties authfail:30s invaliduser:30s`.
  It sorts before a developer image's `99-marathon-dev.conf`, and sshd
  keeps the first value it reads;
- enables and starts `sshd.service`, so it survives reboots (`/etc` is the
  confext's writable upper layer).

`off` disables and stops sshd, ends open sessions through the unit's
`cgroup.kill`, removes the drop-in and locks the password again.

sshd listens on every interface: the USB gadget (`172.16.42.1`), Wi-Fi,
and mobile data, where an IPv6 address may be reachable from outside.

The password is the user's system password, so while remote connection
is on it also unlocks the lock screen and passes the Security page's
password checks. It is also the password for `sudo` and polkit, which
treat the `wheel` group, the user's, as administrators. So whoever has
it has root, as Sailfish's developer password does through `devel-su`.

## Not covered here

Package signing and install-time verification: `docs/CODE_SIGNING_GUIDE.md`.
Lock screen authentication: `docs/ARCHITECTURE.md`.
