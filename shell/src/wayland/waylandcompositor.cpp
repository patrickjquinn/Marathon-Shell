#include "src/wayland/waylandcompositor.h"
#include <QDebug>
#include <QTimer>
#include <QPointer>
#include <QDateTime>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QCoreApplication>
#include <QWaylandXdgToplevel>
#include <QWaylandXdgSurface>
#include <QWaylandXdgPopup>
#include <QtMath>
#include <QQuickItem>
#include <QKeyEvent>

static bool envBool(const char *name, bool defaultValue) {
    const QByteArray raw = qgetenv(name);
    if (raw.isEmpty())
        return defaultValue;
    const QByteArray v = raw.trimmed().toLower();
    if (v == "1" || v == "true" || v == "yes" || v == "on")
        return true;
    if (v == "0" || v == "false" || v == "no" || v == "off")
        return false;
    return defaultValue;
}

static bool wlVerbose() {
    // Opt-in log verbosity for Wayland compositor bring-up/debugging.
    return envBool("MARATHON_WL_VERBOSE", false);
}

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#endif

WaylandCompositor::WaylandCompositor(QQuickWindow *window)
    : QWaylandCompositor()
    , m_window(window)
    , m_nextSurfaceId(1)
    , m_output(nullptr)
    , m_hasIdleInhibitor(false) {

    // Must be set before create().
    const QByteArray socketNameEnv = qgetenv("MARATHON_WL_SOCKET_NAME").trimmed();
    const QByteArray socketNameBytes =
        socketNameEnv.isEmpty() ? QByteArrayLiteral("marathon-wayland-0") : socketNameEnv;
    setSocketName(socketNameBytes);

    // Ensure wl_shm is advertised (many toolkits rely on SHM buffers).
    QList<QWaylandCompositor::ShmFormat> shmFormats;
    shmFormats << QWaylandCompositor::ShmFormat_ARGB8888;
    shmFormats << QWaylandCompositor::ShmFormat_XRGB8888;
    setAdditionalShmFormats(shmFormats);

    // Qt requirement: create() must be called before constructing QWaylandOutput.
    create();

    // Shell extensions (safe after create()).
    m_xdgShell = new QWaylandXdgShell(this);
    // wl_shell is legacy/deprecated; keep it OFF by default and allow opting in for compatibility.
    const bool enableWlShell = envBool("MARATHON_WL_ENABLE_WL_SHELL", false);
    if (enableWlShell) {
        m_wlShell = new QWaylandWlShell(this);
        connect(m_wlShell, &QWaylandWlShell::wlShellSurfaceCreated, this,
                &WaylandCompositor::handleWlShellSurfaceCreated);
        qInfo() << "[WaylandCompositor] wl_shell enabled (legacy compatibility)";
    } else {
        qInfo() << "[WaylandCompositor] wl_shell disabled (legacy protocol)";
    }

    // Protocol globals we intentionally expose. Enabled by default; can be disabled for debugging.
    const bool enableViewporter  = envBool("MARATHON_WL_ENABLE_VIEWPORTER", true);
    const bool enableTextInputV2 = envBool("MARATHON_WL_ENABLE_TEXT_INPUT_V2", true);
    const bool enableIdleInhibit = envBool("MARATHON_WL_ENABLE_IDLE_INHIBIT", true);

    // wp_viewporter: Firefox/GTK use this to set destination size for surface buffers.
    // Without this, some clients render at wrong size despite correct configure events.
    if (enableViewporter) {
        m_viewporter = new QWaylandViewporter(this);
        qInfo() << "[WaylandCompositor] wp_viewporter enabled";
    } else {
        qInfo() << "[WaylandCompositor] wp_viewporter disabled";
    }

    // zwp_text_input_manager_v2: Needed for native Wayland apps + on-screen keyboard integration.
    if (enableTextInputV2) {
        m_textInputManager = new QWaylandTextInputManager(this);
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 enabled";
    } else {
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 disabled";
    }

    // zwp_idle_inhibit_manager_v1: Used by media apps to prevent screen blanking during playback.
    // When disabled, surface->inhibitsIdle() will remain false and we won't honor client inhibitors.
    if (enableIdleInhibit) {
        m_idleInhibitManager = new QWaylandIdleInhibitManagerV1(this);
        qInfo() << "[WaylandCompositor] zwp_idle_inhibit_manager_v1 enabled";
    } else {
        qInfo() << "[WaylandCompositor] zwp_idle_inhibit_manager_v1 disabled";
    }

    connect(defaultSeat(), &QWaylandSeat::keyboardFocusChanged, this,
            [this](QWaylandSurface *newFocus, QWaylandSurface *oldFocus) {
                Q_UNUSED(oldFocus);
                if (wlVerbose() && newFocus)
                    qDebug() << "[WaylandCompositor] Keyboard focus changed to surface:"
                             << newFocus;
            });

    connect(this, &QWaylandCompositor::surfaceCreated, this,
            &WaylandCompositor::handleSurfaceCreated);

    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated, this,
            &WaylandCompositor::handleXdgToplevelCreated);
    connect(m_xdgShell, &QWaylandXdgShell::popupCreated, this,
            &WaylandCompositor::handleXdgPopupCreated);

    // Create output after compositor is initialized.
    m_output = new QWaylandQuickOutput(this, window);
    m_output->setSizeFollowsWindow(true);

    // Required by Qt's XdgToplevelIntegration.
    setDefaultOutput(m_output);

    calculateAndSetPhysicalSize();

    qInfo() << "[WaylandCompositor] Initialized on socket:" << socketName()
            << "output:" << window->size() << "(scale=" << m_output->scaleFactor() << ")";

    // Set RT priority for compositor rendering thread (Priority 75 per spec)
    setCompositorRealtimePriority();

    // Intercept global keys before Wayland clients to avoid double-handling (press/release split).
    m_window->installEventFilter(this);
}

WaylandCompositor::~WaylandCompositor() {
    for (auto process : m_processes.keys()) {
        if (process->state() != QProcess::NotRunning) {
            process->terminate();
            if (!process->waitForFinished(3000)) {
                process->kill();
            }
        }
        process->deleteLater();
    }

    // NOTE: No custom D-Bus session to stop
}

QQmlListProperty<QObject> WaylandCompositor::surfaces() {
    return QQmlListProperty<QObject>(this, &m_surfaces);
}

void WaylandCompositor::launchApp(const QString &command) {
    if (wlVerbose()) {
        qDebug() << "[WaylandCompositor] Launching app:" << command;
        qDebug() << "[WaylandCompositor] Socket name:" << socketName();
        qDebug() << "[WaylandCompositor] XDG_RUNTIME_DIR:" << qgetenv("XDG_RUNTIME_DIR");
    }

    // Handle Flatpak and Snap apps
    QString    actualCommand = command;
    const bool isFlatpak     = command.startsWith("FLATPAK:");
    const bool isSnap        = command.startsWith("SNAP:");
    // If we can represent a command as an argv vector, prefer that to preserve correctness.
    QStringList execPartsOverride;

    if (isFlatpak) {
        // IMPORTANT (correctness): flatpak syntax is:
        //   flatpak run [OPTION...] REF [ARG...]
        // Options must come BEFORE REF. Appending options at the end turns them into app args.
        actualCommand           = command.mid(8); // Remove "FLATPAK:" prefix
        const QStringList parts = QProcess::splitCommand(actualCommand);
        if (parts.size() >= 2 && parts.at(0) == "flatpak" && parts.at(1) == "run") {
            QStringList newParts;
            newParts << "flatpak"
                     << "run"
                     << "--socket=wayland"
                     << QStringLiteral("--filesystem=xdg-run/%1").arg(socketName())
                     << QStringLiteral("--env=WAYLAND_DISPLAY=%1").arg(socketName());
            // Keep the rest of the user's args intact (including any existing options and REF).
            newParts << parts.mid(2);
            execPartsOverride = newParts;
            actualCommand     = newParts.join(' ');
        } else {
            // Best-effort fallback: don't mutate unknown flatpak command shapes.
            qWarning()
                << "[WaylandCompositor] FLATPAK: command did not look like 'flatpak run ...':"
                << actualCommand;
        }
        qInfo() << "[WaylandCompositor] Flatpak command (Wayland socket injected):"
                << actualCommand;
    }

    if (isSnap) {
        actualCommand = command.mid(5); // Remove "SNAP:" prefix
        qInfo() << "[WaylandCompositor] Snap app - wayland interface should be connected";
        qInfo() << "[WaylandCompositor] Run 'snap connections APP' to verify wayland interface";
    }

    QProcess *process = new QProcess(this);

    // Set up Wayland environment
    QProcessEnvironment env        = QProcessEnvironment::systemEnvironment();
    QString             runtimeDir = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR"));

    if (runtimeDir.isEmpty()) {
        qWarning() << "[WaylandCompositor] XDG_RUNTIME_DIR not set! Apps may fail to connect.";
        runtimeDir = "/tmp";
    }

    // CRITICAL: Remove parent compositor's WAYLAND_DISPLAY to force apps to use OUR compositor
    env.remove("WAYLAND_DISPLAY"); // Remove parent Wayland compositor
    env.remove("DISPLAY");         // Remove X11 display (force Wayland)

    // CRITICAL FIX: Prevent GTK/GApplication apps from connecting to host/previous instances
    // Apps like Nautilus/Clocks use GApplication's single-instance D-Bus mechanism
    // They check D-Bus for existing instances and send "open window" commands to them
    // This causes windows to open in host compositor OR connect to stale D-Bus names
    //
    // Solution: Generate UNIQUE GApplication ID per app launch (not just per Marathon instance!)
    // This isolates each launch from host AND previous Marathon launches

    // CRITICAL: Force new instances of GApplication apps
    // GApplication apps check D-Bus for existing instances and send commands to them instead
    // of launching new windows. This causes apps to open in the host compositor.
    //
    // Solution: Create a temporary unique desktop file for each launch
    // GApplication extracts the app ID from the desktop file basename and uses it for D-Bus registration.
    // A unique desktop file path forces a unique D-Bus name, preventing detection of host instances.
    qint64 timestamp   = QDateTime::currentMSecsSinceEpoch();
    uint   commandHash = qHash(actualCommand);

    // For sandboxed Flatpak apps, forcing a synthetic desktop file is unnecessary and can be
    // counter-productive. Keep this behavior for non-Flatpak apps where we observed host instance
    // interference via GApplication single-instance activation.
    //
    // Also skip this for marathon-app-runner launches: runner instances are isolated and do not
    // participate in GApplication single-instance activation.
    const bool isRunner = actualCommand.contains("marathon-app-runner");
    if (!isFlatpak && !isRunner) {
        // Create /tmp/marathon-apps directory if it doesn't exist
        QDir tmpDir("/tmp/marathon-apps");
        if (!tmpDir.exists()) {
            tmpDir.mkpath(".");
        }

        // Create unique desktop file path
        QString uniqueDesktopFile =
            QString("/tmp/marathon-apps/marathon-%1-%2.desktop").arg(timestamp).arg(commandHash);

        // Create a properly formatted desktop file for GApplication
        QFile desktopFile(uniqueDesktopFile);
        if (desktopFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&desktopFile);
            out << "[Desktop Entry]\n";
            out << "Version=1.0\n"; // Desktop Entry Spec version
            out << "Type=Application\n";
            out << "Name=Marathon Embedded App\n";
            out << "GenericName=Application\n";
            out << "Comment=Application running in Marathon OS\n";
            out << "Exec=" << actualCommand << "\n";
            out << "Terminal=false\n";                  // Not a terminal app
            out << "Categories=Utility;\n";             // FreeDesktop category
            out << "StartupNotify=true\n";              // Supports startup notification
            out << "X-GNOME-UsesNotifications=false\n"; // Prevent notification parsing
            out << "X-Marathon-Embedded=true\n";        // Custom field for identification
            desktopFile.close();

            qDebug()
                << "[WaylandCompositor] Created desktop file with full specification compliance";
        } else {
            qWarning() << "[WaylandCompositor] Failed to create desktop file:" << uniqueDesktopFile;
        }

        env.insert("GIO_LAUNCHED_DESKTOP_FILE", uniqueDesktopFile);
        env.insert("GIO_LAUNCHED_DESKTOP_FILE_PID",
                   QString::number(QCoreApplication::applicationPid()));
        // Remember it so we can clean it up when the process exits.
        process->setProperty("marathonDesktopFile", uniqueDesktopFile);

        qDebug() << "[WaylandCompositor] Created unique desktop file:" << uniqueDesktopFile;
    }

    // Set OUR compositor variables
    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");

    // In this dev setup, Qt logging may go to journald instead of the captured stderr.
    // Force stderr logging in debug mode so runner logs show up in the shell log stream.
    {
        const QByteArray debugEnv = qgetenv("MARATHON_DEBUG").trimmed().toLower();
        const bool       debug    = (debugEnv == "1" || debugEnv == "true");
        if (debug)
            env.insert("QT_FORCE_STDERR_LOGGING", "1");
    }
    // Client buffer integration:
    // Prefer GPU/EGL for smooth animations and high FPS.
    //
    // If you need to debug on systems where EGL is flaky, you can force SHM/software via env:
    //   - MARATHON_FORCE_WAYLAND_SHM=1
    //   - QT_QUICK_BACKEND=software   (or QSG_RHI_BACKEND=software)
    const bool forceShm = envBool("MARATHON_FORCE_WAYLAND_SHM", false);
    if (!env.contains("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION")) {
        env.insert("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", forceShm ? "shm" : "wayland-egl");
    }
    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    env.insert("MOZ_ENABLE_WAYLAND", "1"); // Force Firefox/Mozilla to use Wayland
    // Don't force EGL platform for clients; let the chosen backend decide.

    // Mobile form factor environment variables
    // These tell GTK4/libadwaita and Qt apps to use mobile/adaptive layouts
    env.insert("LIBADWAITA_MOBILE", "1");        // Force libadwaita mobile mode
    env.insert("PURISM_FORM_FACTOR", "phone");   // Phosh compatibility (used by Phosh/Purism apps)
    env.insert("QT_QUICK_CONTROLS_MOBILE", "1"); // Qt Quick Controls mobile mode
    // Qt6 Quick Controls does not ship a "Mobile" style plugin. Forcing it causes QML to fail
    // with errors like: module "Mobile" is not installed (seen in Clock's AlarmEditorDialog).
    // Keep the mobile/adaptive *hints* above, but use a real style.
    env.insert("QT_QUICK_CONTROLS_STYLE", "Basic");
    env.insert("GTK_CSD", "1"); // Force client-side decorations for GTK apps
    // Portals:
    // - For Flatpak apps, portals are the standard integration mechanism (file chooser, etc.).
    // - For non-Flatpak nested compositor usage, portals can pop dialogs outside the shell.
    // Keep non-Flatpak default OFF for backwards-compat, but allow opting in for "first-class"
    // desktop integration via MARATHON_ENABLE_PORTALS=1.
    if (!env.contains("GTK_USE_PORTAL")) {
        const bool enablePortals = isFlatpak || envBool("MARATHON_ENABLE_PORTALS", false);
        env.insert("GTK_USE_PORTAL", enablePortals ? "1" : "0");
    }

    // Scaling:
    // Let clients follow Wayland's output scale (wl_output::scaleFactor). Do not force toolkit
    // scaling env vars here, as that double-scales buffers and is a common cause of blur.
    env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1"); // No client-side decorations for Qt

    // For Marathon app runner IPC: allow the runner to verify lifecycle calls come from the shell.
    // Only set this for marathon-app-runner launches.
    if (actualCommand.contains("marathon-app-runner")) {
        env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));
    }

    process->setProcessEnvironment(env);

    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Launching:" << command;

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred, this, &WaylandCompositor::handleProcessError);

    // Use separate channels to properly capture stderr on errors
    process->setProcessChannelMode(QProcess::SeparateChannels);

    // Capture stdout/stderr for debugging (opt-in).
    QPointer<QProcess> safeProcess(process);
    connect(process, &QProcess::readyReadStandardOutput, this, [safeProcess, command]() {
        if (!safeProcess)
            return;
        QString output = QString::fromLocal8Bit(safeProcess->readAllStandardOutput());
        if (wlVerbose() && !output.trimmed().isEmpty())
            qDebug() << "[WaylandCompositor] stdout:" << command << "->" << output.trimmed();
    });

    connect(process, &QProcess::readyReadStandardError, this, [safeProcess, command]() {
        if (!safeProcess)
            return;
        QString error = QString::fromLocal8Bit(safeProcess->readAllStandardError());
        if (wlVerbose() && !error.trimmed().isEmpty())
            qDebug() << "[WaylandCompositor] stderr:" << command << "->" << error.trimmed();
    });

    m_processes[process] = actualCommand;

    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Starting process:" << actualCommand;

    // Prefer direct exec (so the PID we emit matches the real client PID for strict PID↔surface mapping).
    // Only fall back to /bin/sh when the command needs shell features.
    const QStringList parts =
        execPartsOverride.isEmpty() ? QProcess::splitCommand(actualCommand) : execPartsOverride;
    const bool        hasParts = !parts.isEmpty();
    const QString     program  = hasParts ? parts.first() : QString();
    const QStringList args     = hasParts ? parts.mid(1) : QStringList();

    // Heuristic: if splitCommand can't parse, or the string contains obvious shell metacharacters,
    // fall back to /bin/sh -c.
    const bool needsShell = !hasParts || actualCommand.contains('|') ||
        actualCommand.contains('&') || actualCommand.contains(';') ||
        actualCommand.contains("&&") || actualCommand.contains("||") ||
        actualCommand.contains('>') || actualCommand.contains('<');

    // Emit appLaunched once the process actually starts (avoid blocking waitForStarted on the UI thread).
    connect(process, &QProcess::started, this, [this, command, process]() {
        const qint64 pid = process ? process->processId() : -1;
        if (pid > 0) {
            qInfo() << "[WaylandCompositor] Started PID" << pid;
            emit appLaunched(command, static_cast<int>(pid));
        }
    });

    if (!needsShell) {
        process->setProgram(program);
        process->setArguments(args);
        process->start();
    } else {
        process->start("/bin/sh", {"-c", actualCommand});
    }
}

void WaylandCompositor::closeWindow(int surfaceId) {
    if (!m_surfaceMap.contains(surfaceId)) {
        qWarning() << "[WaylandCompositor] closeWindow called for unknown surface ID:" << surfaceId;
        return;
    }

    QWaylandSurface *surface = m_surfaceMap[surfaceId];
    if (!surface) {
        qWarning() << "[WaylandCompositor] Surface is null for ID:" << surfaceId;
        return;
    }

    // CRITICAL FIX: Use XDG shell protocol's sendClose() for graceful shutdown
    // This sends WM_DELETE_WINDOW equivalent, allowing app to save state
    // DO NOT use client->close() - that forcefully kills the connection!

    // Get XDG surface from our map (stored in handleXdgToplevelCreated)
    QWaylandXdgSurface *xdgSurface = m_xdgSurfaceMap.value(surfaceId, nullptr);
    if (xdgSurface && xdgSurface->toplevel()) {
        qInfo()
            << "[WaylandCompositor] Sending graceful close request (XDG protocol) to surface ID:"
            << surfaceId;
        xdgSurface->toplevel()->sendClose();
    } else {
        // Fallback: If not XDG shell, close client connection
        QWaylandClient *client = surface->client();
        if (client) {
            qWarning() << "[WaylandCompositor] No XDG toplevel found, falling back to client close "
                          "for surface ID:"
                       << surfaceId;
            client->close();
        }
    }

    // Find the specific process for this surface (by PID mapping)
    qint64 pid = m_surfaceIdToPid.value(surfaceId, -1);
    if (pid <= 0) {
        qDebug() << "[WaylandCompositor] No PID mapping for surface ID:" << surfaceId;
        return; // Let the surface close naturally
    }

    // Find the process for this PID
    QProcess *targetProcess = nullptr;
    for (auto it = m_processes.begin(); it != m_processes.end(); ++it) {
        QProcess *process = it.key();
        if (process && process->processId() == pid) {
            targetProcess = process;
            break;
        }
    }

    if (!targetProcess) {
        qDebug() << "[WaylandCompositor] No process found for PID:" << pid;
        return; // Process already exited or doesn't exist
    }

    // Give the app time to close gracefully (most apps will close within 3-5 seconds)
    // Use QPointer for safe pointer checking (process might be deleted if it exits)
    QPointer<QProcess> safeProcessPtr(targetProcess);

    qDebug() << "[WaylandCompositor] Waiting for PID" << pid << "to exit gracefully...";
    QTimer::singleShot(5000, this, [this, safeProcessPtr, surfaceId, pid]() {
        // Check if process object still exists and is still running
        if (!safeProcessPtr) {
            qInfo() << "[WaylandCompositor] Process" << pid
                    << "exited gracefully (object deleted) for surface ID:" << surfaceId;
            return;
        }

        if (safeProcessPtr->state() != QProcess::NotRunning) {
            qWarning() << "[WaylandCompositor] Process" << pid
                       << "didn't exit after 5s, sending SIGTERM";
            safeProcessPtr->terminate();

            // Last resort: kill after 3 more seconds
            QTimer::singleShot(3000, this, [safeProcessPtr, pid]() {
                if (safeProcessPtr && safeProcessPtr->state() != QProcess::NotRunning) {
                    qWarning() << "[WaylandCompositor] Force killing process" << pid;
                    safeProcessPtr->kill();
                }
            });
        } else {
            qInfo() << "[WaylandCompositor] Process" << pid
                    << "exited gracefully for surface ID:" << surfaceId;
        }
    });
}

QObject *WaylandCompositor::getSurfaceById(int surfaceId) {
    return m_surfaceMap.value(surfaceId, nullptr);
}

void WaylandCompositor::handleSurfaceCreated(QWaylandSurface *surface) {
    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Surface created:" << surface;

    connect(surface, &QWaylandSurface::surfaceDestroyed, this,
            &WaylandCompositor::handleSurfaceDestroyed);

    int surfaceId           = m_nextSurfaceId++;
    m_surfaceMap[surfaceId] = surface;
    surface->setProperty("surfaceId", surfaceId);

    if (surface->client()) {
        qint64 pid = surface->client()->processId();
        if (pid > 0) {
            m_pidToSurfaceId[pid]       = surfaceId;
            m_surfaceIdToPid[surfaceId] = pid;
            qInfo() << "[WaylandCompositor] Linked PID" << pid << "to surface ID" << surfaceId;
        }
    }

    m_surfaces.append(surface);
    emit surfacesChanged();
    // DON'T emit surfaceCreated yet - wait for XDG toplevel to be created first
}

void WaylandCompositor::activateSurface(int surfaceId) {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(getSurfaceById(surfaceId));
    if (surface && defaultSeat()) {
        defaultSeat()->setKeyboardFocus(surface);
        if (wlVerbose())
            qDebug() << "[WaylandCompositor] Activated surface (set keyboard focus):" << surfaceId;
    } else {
        qWarning() << "[WaylandCompositor] Failed to activate surface:" << surfaceId;
    }
}

void WaylandCompositor::handleXdgToplevelCreated(QWaylandXdgToplevel *toplevel,
                                                 QWaylandXdgSurface  *xdgSurface) {
    if (!toplevel || !xdgSurface) {
        qWarning()
            << "[WaylandCompositor] XDG toplevel creation with null toplevel/xdgSurface - ignoring";
        return;
    }

    if (!m_output) {
        qWarning() << "[WaylandCompositor] No output available for XDG toplevel - ignoring surface";
        return;
    }

    QWaylandSurface *surface = xdgSurface->surface();
    if (!surface || !surface->client()) {
        qWarning()
            << "[WaylandCompositor] XDG surface has no valid Wayland surface or client - ignoring";
        return;
    }

    // Store BOTH the xdgSurface (for ShellSurfaceItem) and toplevel (for configuration)
    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));
    surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
    surface->setProperty("title", toplevel->title());
    surface->setProperty("appId", toplevel->appId());

    int surfaceId = surface->property("surfaceId").toInt();
    // CRITICAL: Store xdgSurface for graceful close via sendClose()
    m_xdgSurfaceMap[surfaceId] = xdgSurface;

    qInfo() << "[WaylandCompositor] New toplevel:" << surfaceId << toplevel->appId() << "-"
            << toplevel->title();

    // NOW emit surfaceCreated with surfaceId, xdgSurface AND toplevel
    emit surfaceCreated(surface, surfaceId, xdgSurface);

    // Connect signals with QPointer for safe access to toplevel and surface
    QPointer<QWaylandXdgToplevel> safeToplevel(toplevel);
    QPointer<QWaylandSurface>     safeSurface(surface);

    connect(toplevel, &QWaylandXdgToplevel::titleChanged, this,
            [this, safeToplevel, safeSurface]() {
                if (safeToplevel && safeSurface) {
                    safeSurface->setProperty("title", safeToplevel->title());
                }
            });

    connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this,
            [this, safeToplevel, safeSurface]() {
                if (safeToplevel && safeSurface) {
                    safeSurface->setProperty("appId", safeToplevel->appId());
                }
            });

    // NOTE (correctness): a surface becoming "unmapped"/hasContent=false is not an authoritative
    // app exit. Many apps intentionally hide/minimize or reconfigure surfaces. Treating this as a
    // close can wrongly delete tasks.
    //
    // If you need legacy behavior for specific environments, enable it explicitly:
    //   MARATHON_TREAT_UNMAP_AS_CLOSE=1
    const bool treatUnmapAsClose = envBool("MARATHON_TREAT_UNMAP_AS_CLOSE", false);
    if (treatUnmapAsClose) {
        connect(
            surface, &QWaylandSurface::hasContentChanged, this, [this, safeSurface, surfaceId]() {
                if (safeSurface && !safeSurface->hasContent()) {
                    qInfo() << "[WaylandCompositor] Surface lost content (window hidden/unmapped) "
                               "- surfaceId:"
                            << surfaceId;
                    qInfo() << "[WaylandCompositor] Treating as app close (legacy mode)";

                    // Emit surfaceDestroyed signal BEFORE cleaning up internal state so QML can react.
                    emit surfaceDestroyed(safeSurface.data(), surfaceId);

                    if (m_surfaceIdToPid.contains(surfaceId)) {
                        qint64 pid = m_surfaceIdToPid[surfaceId];
                        m_pidToSurfaceId.remove(pid);
                        m_surfaceIdToPid.remove(surfaceId);
                        qDebug() << "[WaylandCompositor] Cleaned up PID mapping for" << pid;
                    }

                    m_surfaceMap.remove(surfaceId);
                    m_xdgSurfaceMap.remove(surfaceId);
                    m_surfaces.removeAll(safeSurface);
                    emit surfacesChanged();
                }
            });
    }
}

void WaylandCompositor::handleXdgPopupCreated(QWaylandXdgPopup   *popup,
                                              QWaylandXdgSurface *xdgSurface) {
    // Qt's ShellSurfaceItem.autoCreatePopupItems handles most popup management
    // We just track the surface and emit a signal for debugging/logging

    if (!popup || !xdgSurface) {
        qWarning() << "[WaylandCompositor] XDG popup creation with null objects - ignoring";
        return;
    }

    QWaylandSurface *surface = xdgSurface->surface();
    if (!surface) {
        qWarning() << "[WaylandCompositor] XDG popup has no surface - ignoring";
        return;
    }

    // Assign surfaceId if not already assigned
    int surfaceId = surface->property("surfaceId").toInt();
    if (surfaceId == 0) {
        surfaceId               = m_nextSurfaceId++;
        m_surfaceMap[surfaceId] = surface;
        surface->setProperty("surfaceId", surfaceId);
    }

    if (qEnvironmentVariableIsSet("MARATHON_DEBUG")) {
        // Parent surface info is useful for debugging popup routing.
        QWaylandXdgSurface *parentXdgSurface = popup->parentXdgSurface();
        qWarning() << "[WaylandCompositor] Popup created:" << surfaceId << "parent:"
                   << (parentXdgSurface && parentXdgSurface->surface() ?
                           parentXdgSurface->surface()->property("surfaceId").toInt() :
                           -1);
    }

    // Store popup data
    surface->setProperty("isPopup", true);
    surface->setProperty("xdgPopup", QVariant::fromValue(popup));
    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));

    // Track in surfaces list
    m_surfaces.append(surface);
    m_xdgSurfaceMap[surfaceId] = xdgSurface;
    emit surfacesChanged();
}

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface) {
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();

    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        Q_UNUSED(surface->property("surfaceId").toInt());
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());

        // Connect signal with QPointer for safe access
        QPointer<QWaylandWlShellSurface> safeWlShell(wlShellSurface);
        QPointer<QWaylandSurface>        safeSurface(surface);
        connect(wlShellSurface, &QWaylandWlShellSurface::titleChanged, this,
                [this, safeWlShell, safeSurface]() {
                    if (safeWlShell && safeSurface) {
                        safeSurface->setProperty("title", safeWlShell->title());
                    }
                });
    }
}

void WaylandCompositor::handleSurfaceDestroyed() {
    QWaylandSurface *surface = qobject_cast<QWaylandSurface *>(sender());
    if (!surface)
        return;

    int surfaceId = surface->property("surfaceId").toInt();
    qDebug() << "[WaylandCompositor] Surface destroyed, ID:" << surfaceId;

    if (m_surfaceIdToPid.contains(surfaceId)) {
        qint64 pid = m_surfaceIdToPid[surfaceId];
        m_pidToSurfaceId.remove(pid);
        m_surfaceIdToPid.remove(surfaceId);
        qDebug() << "[WaylandCompositor] Cleaned up PID mapping for" << pid;
    }

    m_surfaceMap.remove(surfaceId);
    m_xdgSurfaceMap.remove(surfaceId); // Clean up XDG surface mapping too
    m_surfaces.removeAll(surface);

    emit surfacesChanged();
    emit surfaceDestroyed(surface, surfaceId);
}

void WaylandCompositor::handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (!process)
        return;

    QString command = m_processes.value(process, "unknown");
    qint64  pid     = process->processId();

    // Clean up any per-launch synthetic desktop file we created.
    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty()) {
        if (QFile::exists(desktopFile)) {
            if (!QFile::remove(desktopFile)) {
                qWarning() << "[WaylandCompositor] Failed to remove temp desktop file:"
                           << desktopFile;
            }
        }
    }

    // gapplication launch spawns a subprocess and exits immediately, so PID tracking doesn't work
    bool isGApplication = command.contains("gapplication launch");

    if (isGApplication) {
        // For gapplication commands, we rely on surface-based tracking, not PID
        qInfo() << "[WaylandCompositor] gapplication process finished:" << command
                << "exitCode:" << exitCode << "(surface tracking active, not PID-based)";
    } else {
        qInfo() << "[WaylandCompositor] Process finished:" << command << "PID:" << pid
                << "exitCode:" << exitCode
                << "status:" << (exitStatus == QProcess::NormalExit ? "normal" : "crashed");

        // Only emit and track PID for non-gapplication commands
        if (pid > 0) {
            emit appClosed(pid);
        }
    }

    // Find and close the associated surface/window (only for PID-tracked apps)
    if (pid > 0 && m_pidToSurfaceId.contains(pid)) {
        int surfaceId = m_pidToSurfaceId[pid];
        qInfo() << "[WaylandCompositor] Closing surface for PID" << pid
                << "surfaceId:" << surfaceId;

        // Clean up the surface if it still exists
        if (m_surfaceMap.contains(surfaceId)) {
            QWaylandSurface *surface = m_surfaceMap[surfaceId];
            if (surface && surface->client()) {
                surface->client()->close();
            }
        }
    }

    m_processes.remove(process);
    process->deleteLater();
}

void WaylandCompositor::calculateAndSetPhysicalSize() {
    if (!m_window || !m_output) {
        qWarning() << "[WaylandCompositor] Cannot configure output metrics - missing window/output";
        return;
    }

    // --- Scale factor (wl_output::scale) ---
    //
    // Proper Wayland behavior: the compositor advertises an integer output scale, and clients
    // render higher-resolution buffers when scale > 1. Hardcoding scale=1 makes all apps blurry
    // on HiDPI displays because their buffers are upscaled.
    QScreen *screen = m_window->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();

    qreal dpr = 1.0;
    if (screen)
        dpr = screen->devicePixelRatio();

    // Wayland core protocol uses an integer scale. Choose the nearest sensible integer.
    const int scale = qMax(1, qRound(dpr));
    if (m_output->scaleFactor() != scale)
        m_output->setScaleFactor(scale);

    // --- Available geometry ---
    // Required for Qt's XdgToplevelIntegration; keep in logical coords (window size).
    const QSize windowSize = m_window->size();
    m_output->setAvailableGeometry(QRect(QPoint(0, 0), windowSize));

    // --- Physical size (wl_output::physical_size) ---
    // Compute proportionally from the host screen's physical size, so DPI remains consistent
    // without inventing a fake "target DPI".
    QSize physicalSizeMm(0, 0);
    if (screen) {
        const QSizeF hostMm = screen->physicalSize();    // millimeters (Qt6 uses QSizeF)
        const QSize  hostPx = screen->geometry().size(); // logical px in Qt coordinate space

        if (hostMm.isValid() && hostMm.width() > 0.0 && hostMm.height() > 0.0 && hostPx.isValid() &&
            hostPx.width() > 0 && hostPx.height() > 0) {
            const qreal rx =
                static_cast<qreal>(windowSize.width()) / static_cast<qreal>(hostPx.width());
            const qreal ry =
                static_cast<qreal>(windowSize.height()) / static_cast<qreal>(hostPx.height());
            physicalSizeMm =
                QSize(qMax(1, qRound(hostMm.width() * rx)), qMax(1, qRound(hostMm.height() * ry)));
        }
    }

    // Fallback: if host physical size is unknown, derive mm from DPI.
    if (!physicalSizeMm.isValid() || physicalSizeMm.width() <= 0 || physicalSizeMm.height() <= 0) {
        const qreal mmPerInch = 25.4;
        qreal       dpi       = 0.0;
        if (screen) {
            dpi = screen->physicalDotsPerInch();
            if (dpi <= 0.0)
                dpi = screen->logicalDotsPerInch();
        }
        if (dpi <= 0.0)
            dpi = 96.0; // last-resort fallback when the platform reports nothing useful

        physicalSizeMm = QSize(qMax(1, qRound((windowSize.width() / dpi) * mmPerInch)),
                               qMax(1, qRound((windowSize.height() / dpi) * mmPerInch)));
    }

    m_output->setPhysicalSize(physicalSizeMm);

    qInfo() << "[WaylandCompositor] Output metrics:"
            << "window=" << windowSize << "scale=" << m_output->scaleFactor()
            << "physical(mm)=" << physicalSizeMm << "screenDpr=" << dpr;
}

void WaylandCompositor::setCompositorRealtimePriority() {
#ifdef Q_OS_LINUX
    // Set RT priority 75 for compositor render thread (per Marathon OS spec section 3)
    struct sched_param param;
    param.sched_priority = 75;

    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) == 0) {
        qInfo() << "[WaylandCompositor] ✓ Compositor thread set to RT priority 75 (SCHED_FIFO)";
    } else {
        qWarning()
            << "[WaylandCompositor]  Failed to set RT priority (need CAP_SYS_NICE or limits.conf)";
    }
#else
    qDebug() << "[WaylandCompositor] RT scheduling not available (not Linux)";
#endif
}

void WaylandCompositor::handleProcessError(QProcess::ProcessError error) {
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (!process)
        return;

    QString command = m_processes.value(process, "unknown");
    QString errorString;

    switch (error) {
        case QProcess::FailedToStart:
            errorString = "Failed to start (executable not found or insufficient permissions)";
            break;
        case QProcess::Crashed: errorString = "Crashed"; break;
        case QProcess::Timedout: errorString = "Timed out"; break;
        case QProcess::WriteError: errorString = "Write error"; break;
        case QProcess::ReadError: errorString = "Read error"; break;
        default: errorString = "Unknown error"; break;
    }

    qWarning() << "[WaylandCompositor] Process error for" << command << ":" << errorString;
    qWarning() << "[WaylandCompositor] Error details:" << process->errorString();

    // If we created a synthetic desktop file for this launch, remove it on failure too.
    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty() && QFile::exists(desktopFile)) {
        QFile::remove(desktopFile);
    }

    // Read any error output
    QString output      = QString::fromLocal8Bit(process->readAllStandardOutput());
    QString errorOutput = QString::fromLocal8Bit(process->readAllStandardError());
    if (!output.isEmpty()) {
        qDebug() << "[WaylandCompositor] stdout:" << output;
    }
    if (!errorOutput.isEmpty()) {
        qDebug() << "[WaylandCompositor] stderr:" << errorOutput;
    }

    // Maintain lifecycle/task-model correctness: if a process never started, ensure we don't
    // keep a stale QProcess entry around.
    if (error == QProcess::FailedToStart) {
        m_processes.remove(process);
        process->deleteLater();
    }
}

void WaylandCompositor::setCompositorActive(bool active) {
    if (!m_window)
        return;

    if (active == m_window->isVisible())
        return;

    qDebug() << "[WaylandCompositor]" << (active ? "Resuming" : "Suspending")
             << "compositor window";
    m_window->setVisible(active);
}

void WaylandCompositor::setOutputOrientation(const QString &orientation) {
    if (!m_output || !m_window) {
        qWarning() << "[WaylandCompositor] Cannot set output orientation: missing output or window";
        return;
    }

    QWaylandOutput::Transform transform      = QWaylandOutput::TransformNormal;
    qreal                     rotation       = 0.0;
    bool                      swapDimensions = false;

    if (orientation == "portrait") {
        transform      = QWaylandOutput::TransformNormal;
        rotation       = 0.0;
        swapDimensions = false;
    } else if (orientation == "landscape") {
        transform      = QWaylandOutput::Transform90;
        rotation       = 90.0;
        swapDimensions = true;
    } else if (orientation == "portrait-inverted") {
        transform      = QWaylandOutput::Transform180;
        rotation       = 180.0;
        swapDimensions = false;
    } else if (orientation == "landscape-inverted") {
        transform      = QWaylandOutput::Transform270;
        rotation       = 270.0;
        swapDimensions = true;
    } else {
        qWarning() << "[WaylandCompositor] Invalid rotation request:" << orientation;
        return;
    }

    qInfo() << "[WaylandCompositor] Applying rotation:" << orientation << "(" << rotation
            << "degrees, Transform =" << transform << ")";

    QQuickItem *contentItem = m_window->contentItem();
    if (contentItem) {
        qreal W = m_window->width();
        qreal H = m_window->height();

        contentItem->setTransformOrigin(QQuickItem::TopLeft);
        contentItem->setRotation(rotation);

        if (swapDimensions) {
            contentItem->setWidth(H);
            contentItem->setHeight(W);
        } else {
            contentItem->setWidth(W);
            contentItem->setHeight(H);
        }

        switch (static_cast<int>(rotation)) {
            case 0:
                contentItem->setX(0);
                contentItem->setY(0);
                break;

            case 90:
                contentItem->setX(W);
                contentItem->setY(0);
                break;

            case 180:
                contentItem->setX(W);
                contentItem->setY(H);
                break;

            case 270:
                contentItem->setX(0);
                contentItem->setY(H);
                break;
        }
    } else {
        qWarning() << "[WaylandCompositor] No content item to rotate";
    }

    m_output->setTransform(transform);
    calculateAndSetPhysicalSize();
}

void WaylandCompositor::injectKey(int key, int modifiers, bool pressed) {
    if (!defaultSeat()) {
        qWarning() << "[WaylandCompositor] No default seat found for key injection";
        return;
    }

    QEvent::Type type = pressed ? QEvent::KeyPress : QEvent::KeyRelease;
    QKeyEvent    event(type, key, static_cast<Qt::KeyboardModifiers>(modifiers));
    defaultSeat()->sendFullKeyEvent(&event);
    qInfo() << "[WaylandCompositor] Injected Key:" << key << "Modifiers:" << modifiers
            << "Pressed:" << pressed;
}

bool WaylandCompositor::checkIdleInhibitors() {
    // Scan all surfaces to check if any inhibit idle behavior
    // This is used by the lock screen timer to prevent blanking during video playback
    bool hasInhibitor = false;

    for (auto it = m_surfaceMap.constBegin(); it != m_surfaceMap.constEnd(); ++it) {
        QWaylandSurface *surface = it.value();
        if (surface && surface->inhibitsIdle()) {
            qDebug() << "[WaylandCompositor] Surface" << it.key() << "inhibits idle";
            hasInhibitor = true;
            break;
        }
    }

    if (hasInhibitor != m_hasIdleInhibitor) {
        m_hasIdleInhibitor = hasInhibitor;
        emit hasIdleInhibitingSurfaceChanged();
        qDebug() << "[WaylandCompositor] Idle inhibitor state changed:" << hasInhibitor;
    }

    return hasInhibitor;
}

bool WaylandCompositor::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window &&
        (event->type() == QEvent::KeyPress || event->type() == QEvent::KeyRelease)) {
        QKeyEvent *keyEvent = static_cast<QKeyEvent *>(event);
        int        key      = keyEvent->key();

        // Trap Back (ESC) and Home (Super_L/Meta)
        // We intercept these globally to ensure consistent behavior across all apps (Native & Marathon)
        if (key == Qt::Key_Escape || key == Qt::Key_Super_L || key == Qt::Key_Meta) {

            // On Press: Simply consume to prevent Client from receiving it (avoids internal navigation)
            if (event->type() == QEvent::KeyPress) {
                return true;
            }

            // On Release: Trigger Shell Logic via signals
            if (event->type() == QEvent::KeyRelease) {
                // Determine which signal to emit
                if (key == Qt::Key_Escape) {
                    emit systemBackTriggered();
                } else {
                    emit systemHomeTriggered();
                }
                return true; // Consume release too
            }
        }
    }

    // Pass everything else through
    return QObject::eventFilter(watched, event);
}
