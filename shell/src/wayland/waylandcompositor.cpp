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
#include <QWaylandInputMethodControl>
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
    return envBool("MARATHON_WL_VERBOSE", false);
}

static bool appLogsEnabled() {
    return envBool("MARATHON_APP_LOGS", false) || envBool("MARATHON_DEBUG", false);
}

static bool appLogsAllEnabled() {
    return envBool("MARATHON_APP_LOGS_ALL", false);
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

    const QByteArray socketNameEnv = qgetenv("MARATHON_WL_SOCKET_NAME").trimmed();
    const QByteArray socketNameBytes =
        socketNameEnv.isEmpty() ? QByteArrayLiteral("marathon-wayland-0") : socketNameEnv;
    setSocketName(socketNameBytes);

    QList<QWaylandCompositor::ShmFormat> shmFormats;
    shmFormats << QWaylandCompositor::ShmFormat_ARGB8888;
    shmFormats << QWaylandCompositor::ShmFormat_XRGB8888;
    setAdditionalShmFormats(shmFormats);

    create();

    m_xdgShell               = new QWaylandXdgShell(this);
    const bool enableWlShell = envBool("MARATHON_WL_ENABLE_WL_SHELL", false);
    if (enableWlShell) {
        m_wlShell = new QWaylandWlShell(this);
        connect(m_wlShell, &QWaylandWlShell::wlShellSurfaceCreated, this,
                &WaylandCompositor::handleWlShellSurfaceCreated);
        qInfo() << "[WaylandCompositor] wl_shell enabled (legacy compatibility)";
    } else {
        qInfo() << "[WaylandCompositor] wl_shell disabled (legacy protocol)";
    }

    const bool enableViewporter  = envBool("MARATHON_WL_ENABLE_VIEWPORTER", true);
    const bool enableTextInputV2 = envBool("MARATHON_WL_ENABLE_TEXT_INPUT_V2", true);
    const bool enableIdleInhibit = envBool("MARATHON_WL_ENABLE_IDLE_INHIBIT", true);

    if (enableViewporter) {
        m_viewporter = new QWaylandViewporter(this);
        qInfo() << "[WaylandCompositor] wp_viewporter enabled";
    } else {
        qInfo() << "[WaylandCompositor] wp_viewporter disabled";
    }

    if (enableTextInputV2) {
        m_textInputManager = new QWaylandTextInputManager(this);
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 enabled";
    } else {
        qInfo() << "[WaylandCompositor] zwp_text_input_manager_v2 disabled";
    }

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

    m_output = new QWaylandQuickOutput(this, window);
    m_output->setSizeFollowsWindow(true);

    setDefaultOutput(m_output);

    calculateAndSetPhysicalSize();

    qInfo() << "[WaylandCompositor] Initialized on socket:" << socketName()
            << "output:" << window->size() << "(scale=" << m_output->scaleFactor() << ")";

    setCompositorRealtimePriority();

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

    QString     actualCommand = command;
    const bool  isFlatpak     = command.startsWith("FLATPAK:");
    const bool  isSnap        = command.startsWith("SNAP:");
    QStringList execPartsOverride;

    if (isFlatpak) {
        actualCommand           = command.mid(8);
        const QStringList parts = QProcess::splitCommand(actualCommand);
        if (parts.size() >= 2 && parts.at(0) == "flatpak" && parts.at(1) == "run") {
            QStringList newParts;
            newParts << "flatpak"
                     << "run"
                     << "--socket=wayland"
                     << QStringLiteral("--filesystem=xdg-run/%1").arg(socketName())
                     << QStringLiteral("--env=WAYLAND_DISPLAY=%1").arg(socketName());
            newParts << parts.mid(2);
            execPartsOverride = newParts;
            actualCommand     = newParts.join(' ');
        } else {
            qWarning()
                << "[WaylandCompositor] FLATPAK: command did not look like 'flatpak run ...':"
                << actualCommand;
        }
        qInfo() << "[WaylandCompositor] Flatpak command (Wayland socket injected):"
                << actualCommand;
    }

    if (isSnap) {
        actualCommand = command.mid(5);
        qInfo() << "[WaylandCompositor] Snap app - wayland interface should be connected";
        qInfo() << "[WaylandCompositor] Run 'snap connections APP' to verify wayland interface";
    }

    QProcess           *process = new QProcess(this);

    QProcessEnvironment env        = QProcessEnvironment::systemEnvironment();
    QString             runtimeDir = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR"));

    if (runtimeDir.isEmpty()) {
        qWarning() << "[WaylandCompositor] XDG_RUNTIME_DIR not set! Apps may fail to connect.";
        runtimeDir = "/tmp";
    }

    env.remove("WAYLAND_DISPLAY");
    env.remove("DISPLAY");

    qint64     timestamp   = QDateTime::currentMSecsSinceEpoch();
    uint       commandHash = qHash(actualCommand);

    const bool isRunner = actualCommand.contains("marathon-app-runner");
    if (!isFlatpak && !isRunner) {
        QDir tmpDir("/tmp/marathon-apps");
        if (!tmpDir.exists()) {
            tmpDir.mkpath(".");
        }

        QString uniqueDesktopFile =
            QString("/tmp/marathon-apps/marathon-%1-%2.desktop").arg(timestamp).arg(commandHash);

        QFile desktopFile(uniqueDesktopFile);
        if (desktopFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&desktopFile);
            out << "[Desktop Entry]\n";
            out << "Version=1.0\n";
            out << "Type=Application\n";
            out << "Name=Marathon Embedded App\n";
            out << "GenericName=Application\n";
            out << "Comment=Application running in Marathon OS\n";
            out << "Exec=" << actualCommand << "\n";
            out << "Terminal=false\n";
            out << "Categories=Utility;\n";
            out << "StartupNotify=true\n";
            out << "X-GNOME-UsesNotifications=false\n";
            out << "X-Marathon-Embedded=true\n";
            desktopFile.close();

            qDebug()
                << "[WaylandCompositor] Created desktop file with full specification compliance";
        } else {
            qWarning() << "[WaylandCompositor] Failed to create desktop file:" << uniqueDesktopFile;
        }

        env.insert("GIO_LAUNCHED_DESKTOP_FILE", uniqueDesktopFile);
        env.insert("GIO_LAUNCHED_DESKTOP_FILE_PID",
                   QString::number(QCoreApplication::applicationPid()));
        process->setProperty("marathonDesktopFile", uniqueDesktopFile);

        qDebug() << "[WaylandCompositor] Created unique desktop file:" << uniqueDesktopFile;
    }

    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");

    {
        const QByteArray debugEnv = qgetenv("MARATHON_DEBUG").trimmed().toLower();
        const bool       debug    = (debugEnv == "1" || debugEnv == "true");
        if (debug)
            env.insert("QT_FORCE_STDERR_LOGGING", "1");
    }
    const bool forceShm = envBool("MARATHON_FORCE_WAYLAND_SHM", false);
    if (!env.contains("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION")) {
        // wayland-egl for hardware accelerated rendering
        env.insert("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", forceShm ? "shm" : "wayland-egl");
    }

    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    env.insert("MOZ_ENABLE_WAYLAND", "1");

    env.insert("LIBADWAITA_MOBILE", "1");
    env.insert("PURISM_FORM_FACTOR", "phone");
    env.insert("QT_QUICK_CONTROLS_MOBILE", "1");
    env.insert("QT_QUICK_CONTROLS_STYLE", "Basic");
    env.insert("GTK_CSD", "1");
    if (!env.contains("GTK_USE_PORTAL")) {
        const bool enablePortals = isFlatpak || envBool("MARATHON_ENABLE_PORTALS", false);
        env.insert("GTK_USE_PORTAL", enablePortals ? "1" : "0");
    }

    env.insert("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");

    env.insert("QT_MEDIA_BACKEND", "ffmpeg");

    if (actualCommand.contains("marathon-app-runner")) {
        env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));
    }

    process->setProcessEnvironment(env);

    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Launching:" << command;

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred, this, &WaylandCompositor::handleProcessError);

    process->setProcessChannelMode(QProcess::SeparateChannels);
    process->setProperty("marathonStdoutTail", QString());
    process->setProperty("marathonStderrTail", QString());

    QPointer<QProcess> safeProcess(process);
    connect(process, &QProcess::readyReadStandardOutput, this, [safeProcess, command]() {
        if (!safeProcess)
            return;
        QString output = QString::fromLocal8Bit(safeProcess->readAllStandardOutput());
        if (!output.isEmpty()) {
            QString tail = safeProcess->property("marathonStdoutTail").toString();
            tail += output;
            if (tail.size() > 64 * 1024)
                tail = tail.right(64 * 1024);
            safeProcess->setProperty("marathonStdoutTail", tail);

            if (wlVerbose() && !output.trimmed().isEmpty())
                qDebug() << "[WaylandCompositor] stdout:" << command << "->" << output.trimmed();

            if (appLogsEnabled() && command.contains("marathon-app-runner") &&
                !output.trimmed().isEmpty()) {
                const QStringList lines = output.split('\n');
                int               shown = 0;
                for (const QString &l : lines) {
                    const QString line = l.trimmed();
                    if (line.isEmpty())
                        continue;
                    if (!appLogsAllEnabled()) {
                        if (line.startsWith("libEGL warning") || line.startsWith("MESA-LOADER:"))
                            continue;
                    }
                    qWarning().noquote() << "[AppRunner stdout]" << command << "->" << line;
                    if (++shown >= 25)
                        break;
                }
            }
        }
    });

    connect(process, &QProcess::readyReadStandardError, this, [safeProcess, command]() {
        if (!safeProcess)
            return;
        QString error = QString::fromLocal8Bit(safeProcess->readAllStandardError());
        if (!error.isEmpty()) {
            QString tail = safeProcess->property("marathonStderrTail").toString();
            tail += error;
            if (tail.size() > 64 * 1024)
                tail = tail.right(64 * 1024);
            safeProcess->setProperty("marathonStderrTail", tail);

            if (wlVerbose() && !error.trimmed().isEmpty())
                qDebug() << "[WaylandCompositor] stderr:" << command << "->" << error.trimmed();

            if (appLogsEnabled() && command.contains("marathon-app-runner") &&
                !error.trimmed().isEmpty()) {
                const QStringList lines = error.split('\n');
                int               shown = 0;
                for (const QString &l : lines) {
                    const QString line = l.trimmed();
                    if (line.isEmpty())
                        continue;
                    if (!appLogsAllEnabled()) {
                        if (line.startsWith("libEGL warning") || line.startsWith("MESA-LOADER:"))
                            continue;
                    }
                    qWarning().noquote() << "[AppRunner stderr]" << command << "->" << line;
                    if (++shown >= 25)
                        break;
                }
            }
        }
    });

    m_processes[process] = actualCommand;

    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Starting process:" << actualCommand;

    const QStringList parts =
        execPartsOverride.isEmpty() ? QProcess::splitCommand(actualCommand) : execPartsOverride;
    const bool        hasParts = !parts.isEmpty();
    const QString     program  = hasParts ? parts.first() : QString();
    const QStringList args     = hasParts ? parts.mid(1) : QStringList();

    const bool        needsShell = !hasParts || actualCommand.contains('|') ||
        actualCommand.contains('&') || actualCommand.contains(';') ||
        actualCommand.contains("&&") || actualCommand.contains("||") ||
        actualCommand.contains('>') || actualCommand.contains('<');

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

    QWaylandXdgSurface *xdgSurface = m_xdgSurfaceMap.value(surfaceId, nullptr);
    if (xdgSurface && xdgSurface->toplevel()) {
        qInfo()
            << "[WaylandCompositor] Sending graceful close request (XDG protocol) to surface ID:"
            << surfaceId;
        xdgSurface->toplevel()->sendClose();
    } else {
        QWaylandClient *client = surface->client();
        if (client) {
            qWarning() << "[WaylandCompositor] No XDG toplevel found, falling back to client close "
                          "for surface ID:"
                       << surfaceId;
            client->close();
        }
    }

    qint64 pid = m_surfaceIdToPid.value(surfaceId, -1);
    if (pid <= 0) {
        qDebug() << "[WaylandCompositor] No PID mapping for surface ID:" << surfaceId;
        return;
    }

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
        return;
    }

    // Mark this process as being closed by the shell (avoid mislabeling signal-based termination as a crash).
    targetProcess->setProperty("marathonCloseRequested", true);

    QPointer<QProcess> safeProcessPtr(targetProcess);

    qDebug() << "[WaylandCompositor] Waiting for PID" << pid << "to exit gracefully...";
    QTimer::singleShot(5000, this, [this, safeProcessPtr, surfaceId, pid]() {
        if (!safeProcessPtr) {
            qInfo() << "[WaylandCompositor] Process" << pid
                    << "exited gracefully (object deleted) for surface ID:" << surfaceId;
            return;
        }

        if (safeProcessPtr->state() != QProcess::NotRunning) {
            qWarning() << "[WaylandCompositor] Process" << pid
                       << "didn't exit after 5s, sending SIGTERM";
            safeProcessPtr->setProperty("marathonForceTerminated", true);
            safeProcessPtr->terminate();

            QTimer::singleShot(3000, this, [safeProcessPtr, pid]() {
                if (safeProcessPtr && safeProcessPtr->state() != QProcess::NotRunning) {
                    qWarning() << "[WaylandCompositor] Force killing process" << pid;
                    safeProcessPtr->setProperty("marathonForceKilled", true);
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

    if (auto *inputControl = surface->inputMethodControl()) {
        connect(inputControl, SIGNAL(enabledChanged(bool)), this,
                SLOT(handleTextInputEnabled(bool)));
    }

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

void WaylandCompositor::handleTextInputEnabled(bool enabled) {
    if (wlVerbose())
        qDebug() << "[WaylandCompositor] Native text input enabled changed:" << enabled;
    emit nativeTextInputPanelRequested(enabled);
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

    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));
    surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
    surface->setProperty("title", toplevel->title());
    surface->setProperty("appId", toplevel->appId());

    int surfaceId              = surface->property("surfaceId").toInt();
    m_xdgSurfaceMap[surfaceId] = xdgSurface;

    qInfo() << "[WaylandCompositor] New toplevel:" << surfaceId << toplevel->appId() << "-"
            << toplevel->title();

    emit                          surfaceCreated(surface, surfaceId, xdgSurface);

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

    const bool treatUnmapAsClose = envBool("MARATHON_TREAT_UNMAP_AS_CLOSE", false);
    if (treatUnmapAsClose) {
        connect(
            surface, &QWaylandSurface::hasContentChanged, this, [this, safeSurface, surfaceId]() {
                if (safeSurface && !safeSurface->hasContent()) {
                    qInfo() << "[WaylandCompositor] Surface lost content (window hidden/unmapped) "
                               "- surfaceId:"
                            << surfaceId;
                    qInfo() << "[WaylandCompositor] Treating as app close (legacy mode)";

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

    if (!popup || !xdgSurface) {
        qWarning() << "[WaylandCompositor] XDG popup creation with null objects - ignoring";
        return;
    }

    QWaylandSurface *surface = xdgSurface->surface();
    if (!surface) {
        qWarning() << "[WaylandCompositor] XDG popup has no surface - ignoring";
        return;
    }

    int surfaceId = surface->property("surfaceId").toInt();
    if (surfaceId == 0) {
        surfaceId               = m_nextSurfaceId++;
        m_surfaceMap[surfaceId] = surface;
        surface->setProperty("surfaceId", surfaceId);
    }

    if (qEnvironmentVariableIsSet("MARATHON_DEBUG")) {
        QWaylandXdgSurface *parentXdgSurface = popup->parentXdgSurface();
        qWarning() << "[WaylandCompositor] Popup created:" << surfaceId << "parent:"
                   << (parentXdgSurface && parentXdgSurface->surface() ?
                           parentXdgSurface->surface()->property("surfaceId").toInt() :
                           -1);
    }

    surface->setProperty("isPopup", true);
    surface->setProperty("xdgPopup", QVariant::fromValue(popup));
    surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));

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
    m_xdgSurfaceMap.remove(surfaceId);
    m_surfaces.removeAll(surface);

    emit surfacesChanged();
    emit surfaceDestroyed(surface, surfaceId);
}

void WaylandCompositor::handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (!process)
        return;

    QString       command = m_processes.value(process, "unknown");
    qint64        pid     = process->processId();

    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty()) {
        if (QFile::exists(desktopFile)) {
            if (!QFile::remove(desktopFile)) {
                qWarning() << "[WaylandCompositor] Failed to remove temp desktop file:"
                           << desktopFile;
            }
        }
    }

    bool       isGApplication = command.contains("gapplication launch");
    const bool closeRequested = process->property("marathonCloseRequested").toBool();

    if (isGApplication) {
        qInfo() << "[WaylandCompositor] gapplication process finished:" << command
                << "exitCode:" << exitCode << "(surface tracking active, not PID-based)";
    } else {
        const QString statusStr =
            (exitStatus == QProcess::NormalExit ? "normal" :
                                                  (closeRequested ? "terminated" : "crashed"));
        qInfo() << "[WaylandCompositor] Process finished:" << command << "PID:" << pid
                << "exitCode:" << exitCode << "status:" << statusStr;

        const bool abnormal = (exitStatus != QProcess::NormalExit) || (exitCode != 0);
        if (abnormal && !closeRequested) {
            const QString outputTail = process->property("marathonStdoutTail").toString();
            const QString errTail    = process->property("marathonStderrTail").toString();
            const QString output =
                outputTail + QString::fromLocal8Bit(process->readAllStandardOutput());
            const QString err = errTail + QString::fromLocal8Bit(process->readAllStandardError());
            if (!output.trimmed().isEmpty())
                qWarning() << "[WaylandCompositor] stdout tail for" << command << ":\n"
                           << output.trimmed();
            if (!err.trimmed().isEmpty())
                qWarning() << "[WaylandCompositor] stderr tail for" << command << ":\n"
                           << err.trimmed();
        }

        if (pid > 0) {
            emit appClosed(pid);
        }
    }

    if (pid > 0 && m_pidToSurfaceId.contains(pid)) {
        int surfaceId = m_pidToSurfaceId[pid];
        qInfo() << "[WaylandCompositor] Closing surface for PID" << pid
                << "surfaceId:" << surfaceId;

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

    QScreen *screen = m_window->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();

    qreal dpr = 1.0;
    if (screen)
        dpr = screen->devicePixelRatio();

    const int scale = qMax(1, qRound(dpr));
    if (m_output->scaleFactor() != scale)
        m_output->setScaleFactor(scale);

    const QSize windowSize = m_window->size();
    m_output->setAvailableGeometry(QRect(QPoint(0, 0), windowSize));

    QSize physicalSizeMm(0, 0);
    if (screen) {
        const QSizeF hostMm = screen->physicalSize();
        const QSize  hostPx = screen->geometry().size();

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

    if (!physicalSizeMm.isValid() || physicalSizeMm.width() <= 0 || physicalSizeMm.height() <= 0) {
        const qreal mmPerInch = 25.4;
        qreal       dpi       = 0.0;
        if (screen) {
            dpi = screen->physicalDotsPerInch();
            if (dpi <= 0.0)
                dpi = screen->logicalDotsPerInch();
        }
        if (dpi <= 0.0)
            dpi = 96.0;

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

    QString    command        = m_processes.value(process, "unknown");
    const bool closeRequested = process->property("marathonCloseRequested").toBool();
    QString    errorString;

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

    if (error == QProcess::Crashed && closeRequested) {
        qInfo() << "[WaylandCompositor] Process exited after close request for" << command;
        return;
    }

    qWarning() << "[WaylandCompositor] Process error for" << command << ":" << errorString;
    qWarning() << "[WaylandCompositor] Error details:" << process->errorString();

    const QString desktopFile = process->property("marathonDesktopFile").toString();
    if (!desktopFile.isEmpty() && QFile::exists(desktopFile)) {
        QFile::remove(desktopFile);
    }

    const QString outputTail = process->property("marathonStdoutTail").toString();
    const QString errTail    = process->property("marathonStderrTail").toString();
    const QString output = outputTail + QString::fromLocal8Bit(process->readAllStandardOutput());
    const QString err    = errTail + QString::fromLocal8Bit(process->readAllStandardError());

    // Always dump recent output on errors (even if MARATHON_WL_VERBOSE=0).
    if (!output.trimmed().isEmpty())
        qWarning() << "[WaylandCompositor] stdout tail for" << command << ":\n" << output.trimmed();
    if (!err.trimmed().isEmpty())
        qWarning() << "[WaylandCompositor] stderr tail for" << command << ":\n" << err.trimmed();

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

        if (key == Qt::Key_Escape || key == Qt::Key_Super_L || key == Qt::Key_Meta) {

            if (event->type() == QEvent::KeyPress) {
                return true;
            }

            if (event->type() == QEvent::KeyRelease) {
                if (key == Qt::Key_Escape) {
                    emit systemBackTriggered();
                } else {
                    emit systemHomeTriggered();
                }
                return true;
            }
        }
    }

    return QObject::eventFilter(watched, event);
}
