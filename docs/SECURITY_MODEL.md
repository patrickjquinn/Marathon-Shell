# Security model: app sandboxing

How Marathon confines apps, as the code does it today. Each layer names
the file that implements it. Where a layer has a gap, the gap is listed.

## Who is trusted

| App kind | How it runs | Confinement |
|----------|-------------|-------------|
| Marathon QML apps (bundled and `.marathon` packages) | `bwrap` + `marathon-app-runner`, launched by `AppLaunchService` | bwrap, security-context Wayland socket, shell D-Bus permission gate |
| Marathon WebEngine apps (Browser, Maps) | as above | as above, plus Chromium's own sandbox inside |
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
  `bwrap`, which then could not mount and failed every launch.

## Layer 1: bwrap around Marathon apps

`AppLaunchService::launchMarathonApp` (`shell/src/services/applaunchservice.cpp`)
and the warm runner pool (`spareSandboxArgs`) build the sandbox:

- New user, PID, UTS, IPC and cgroup namespaces, and a network namespace
  with only loopback unless the app holds the `network` permission.
- Read-only `/usr`, `/etc`, `/lib*`, `/bin`, `/sbin`, `/sys`; a fresh
  `/dev` with only the DRM render node; `/tmp`, `/dev/shm` and `$HOME`
  as tmpfs.
- Read-write only `~/.local/share/marathon-apps/<app>` and
  `~/.cache/marathon-apps/<app>`; the user directories only with the
  `storage` permission.
- `$XDG_RUNTIME_DIR` is bound (session bus, PipeWire), with the Wayland
  socket replaced, see layer 2.
- `--die-with-parent`, `--new-session`.

`MARATHON_DISABLE_SANDBOX=1` (or a missing `bwrap`) runs apps without any
of this, and the shell logs a warning for every such launch.

Gaps:

- The whole `$XDG_RUNTIME_DIR` is visible, so an app can reach any session
  socket there. There is no `xdg-dbus-proxy`: an app can call any session
  bus service. The shell's own services check the caller (next section);
  other services do not know which app is calling.
- The pool runner is spawned before its app is known, so it binds the
  parent `marathon-apps` data and cache directories and shares the network.
  A spare has the user directories or not, and becomes only an app with
  the `storage` permission or only one without. User-installed and
  WebEngine apps never use the pool.

## Layer 2: security-context-v1 Wayland sockets

The compositor implements `wp_security_context_v1`
(`shell/src/wayland/securitycontextv1.{h,cpp}`).

**Marathon apps.** Before each launch `AppLaunchService` asks the
compositor (`WaylandCompositor::openSandboxSocket`) for a socket at
`$XDG_RUNTIME_DIR/marathon-sandbox/<instance-uuid>`. The compositor tags
every client that connects there with engine `org.marathonos.AppRunner`,
the app id and the instance id. bwrap mounts that socket over
`$XDG_RUNTIME_DIR/marathon-wayland-0` (so `WAYLAND_DISPLAY` is unchanged)
and puts a tmpfs over `marathon-sandbox/`, so the app can neither reach
the unrestricted socket nor connect through another app's socket. The
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
one (`AppLaunchService::onCompositorSurfaceCreated`). Only an app the
shell runs may open a dialog window over others.

Gaps: Sailfish apps under `marathon-keel-host` and native apps connect on
the unrestricted socket.

## Layer 3: Chromium's sandbox inside WebEngine apps

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
nested user namespaces; Marathon's bwrap installs no seccomp filter, so
the namespace sandbox works as on a desktop.

If a device build ever fails here, `QTWEBENGINE_CHROMIUM_FLAGS` in the
shell's environment replaces the default flags for every WebEngine app.

## Layer 4: the shell's D-Bus permission gate

Shell services on the session bus (`shell/src/ipc/shellservices.cpp`)
resolve the caller's app from its PID (the launcher's PID map, then the
process ancestry up to the shell) and check the app's granted
permissions before acting. See `docs/PERMISSION_GUIDE.md`.

## Not covered here

Package signing and install-time verification: `docs/CODE_SIGNING_GUIDE.md`.
Lock screen authentication: `docs/ARCHITECTURE.md`.
