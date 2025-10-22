#include "waylandcompositor.h"
#include <QDebug>
#include <QWaylandXdgToplevel>
#include <QWaylandXdgSurface>

WaylandCompositor::WaylandCompositor(QQuickWindow *window)
    : QWaylandCompositor()
    , m_window(window)
    , m_nextSurfaceId(1)
{
    m_xdgShell = new QWaylandXdgShell(this);
    m_wlShell = new QWaylandWlShell(this);

    connect(this, &QWaylandCompositor::surfaceCreated,
            this, &WaylandCompositor::handleSurfaceCreated);
    
    connect(m_xdgShell, &QWaylandXdgShell::toplevelCreated,
            this, &WaylandCompositor::handleXdgToplevelCreated);
    
    connect(m_wlShell, &QWaylandWlShell::wlShellSurfaceCreated,
            this, &WaylandCompositor::handleWlShellSurfaceCreated);

    m_output = new QWaylandQuickOutput(this, window);
    m_output->setSizeFollowsWindow(true);
    
    setSocketName("marathon-wayland-0");
    
    create();
    
    // Note: Keyboard focus is managed automatically by QWaylandCompositor in Qt6
    // The defaultInputDevice() API was removed in newer Qt6 versions
    // Keyboard focus handling is now done internally by the compositor
    
    qDebug() << "[WaylandCompositor] Initialized on socket:" << socketName()
             << "output size:" << m_output->window()->size();
    
    // NOTE: We no longer create a custom D-Bus session - apps use the host's session
    // This prevents 25-second timeouts waiting for system services (GeoClue2, etc.)
}

WaylandCompositor::~WaylandCompositor()
{
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

QQmlListProperty<QObject> WaylandCompositor::surfaces()
{
    return QQmlListProperty<QObject>(this, &m_surfaces);
}

void WaylandCompositor::launchApp(const QString &command)
{
    qDebug() << "[WaylandCompositor] Launching app:" << command;
    qDebug() << "[WaylandCompositor] Socket name:" << socketName();
    qDebug() << "[WaylandCompositor] XDG_RUNTIME_DIR:" << qgetenv("XDG_RUNTIME_DIR");
    
    // Handle Flatpak and Snap apps
    QString actualCommand = command;
    bool isFlatpak = command.startsWith("FLATPAK:");
    bool isSnap = command.startsWith("SNAP:");
    
    if (isFlatpak) {
        actualCommand = command.mid(8); // Remove "FLATPAK:" prefix
        QString socketPath = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR")) + "/" + socketName();
        
        // Add Wayland permissions to Flatpak command
        actualCommand += " --socket=wayland";
        actualCommand += " --env=WAYLAND_DISPLAY=" + socketName();
        actualCommand += " --filesystem=xdg-run/" + socketName();
        actualCommand += " --unset-env=DBUS_SESSION_BUS_ADDRESS";
        
        qInfo() << "[WaylandCompositor] Flatpak command with permissions:" << actualCommand;
    }
    
    if (isSnap) {
        actualCommand = command.mid(5); // Remove "SNAP:" prefix
        qInfo() << "[WaylandCompositor] Snap app - wayland interface should be connected";
        qInfo() << "[WaylandCompositor] Run 'snap connections APP' to verify wayland interface";
    }
    
    QProcess *process = new QProcess(this);
    
    // Set up Wayland environment
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    QString runtimeDir = QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR"));
    
    if (runtimeDir.isEmpty()) {
        qWarning() << "[WaylandCompositor] XDG_RUNTIME_DIR not set! Apps may fail to connect.";
        runtimeDir = "/tmp";
    }
    
    // CRITICAL: Remove parent compositor's WAYLAND_DISPLAY to force apps to use OUR compositor
    env.remove("WAYLAND_DISPLAY");  // Remove parent Wayland compositor
    env.remove("DISPLAY");          // Remove X11 display (force Wayland)
    
    // KEEP the host's D-Bus session for system services (GeoClue2, NetworkManager, etc.)
    // Don't remove DBUS_SESSION_BUS_ADDRESS - apps need access to system services!
    // Our isolated D-Bus session was causing 25-second timeouts for missing services
    
    // NOTE: We do NOT create a custom D-Bus session anymore - apps use the host's session
    // This gives them access to:
    // - GeoClue2 (location services for Weather)
    // - NetworkManager (network status)
    // - UPower (battery status)
    // - Portal services (file dialogs, etc.)
    // This is the standard approach for nested compositors
    
    // Set OUR compositor variables
    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");
    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    
    process->setProcessEnvironment(env);
    
    qInfo() << "[WaylandCompositor] ===== LAUNCHING APP =====";
    qInfo() << "[WaylandCompositor] Original command:" << command;
    qInfo() << "[WaylandCompositor] Actual command:" << actualCommand;
    qInfo() << "[WaylandCompositor] WAYLAND_DISPLAY:" << socketName();
    qInfo() << "[WaylandCompositor] XDG_RUNTIME_DIR:" << runtimeDir;
    qInfo() << "[WaylandCompositor] GDK_BACKEND:" << env.value("GDK_BACKEND");
    qInfo() << "[WaylandCompositor] DBUS_SESSION_BUS_ADDRESS:" << env.value("DBUS_SESSION_BUS_ADDRESS");
    
    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred,
            this, &WaylandCompositor::handleProcessError);
    
    // Use separate channels to properly capture stderr on errors
    process->setProcessChannelMode(QProcess::SeparateChannels);
    
    // Capture stdout for debugging (only in verbose mode)
    connect(process, &QProcess::readyReadStandardOutput, this, [process, command]() {
        QString output = QString::fromLocal8Bit(process->readAllStandardOutput());
        QString debugEnv = qgetenv("MARATHON_DEBUG");
        bool debugMode = (debugEnv == "1" || debugEnv.toLower() == "true");
        if (debugMode && !output.trimmed().isEmpty()) {
            qDebug() << "[WaylandCompositor] App stdout:" << command << "->" << output.trimmed();
        }
    });
    
    // Always capture stderr for error reporting
    connect(process, &QProcess::readyReadStandardError, this, [process, command]() {
        QString error = QString::fromLocal8Bit(process->readAllStandardError());
        if (!error.trimmed().isEmpty()) {
            qWarning() << "[WaylandCompositor] App stderr:" << command << "->" << error.trimmed();
        }
    });
    
    m_processes[process] = actualCommand;
    
    qDebug() << "[WaylandCompositor] Starting process:" << actualCommand;
    process->start("/bin/sh", {"-c", actualCommand});
    
    if (process->waitForStarted(3000)) {
        qint64 pid = process->processId();
        qInfo() << "[WaylandCompositor] ✓ App process started successfully, PID:" << pid;
        qInfo() << "[WaylandCompositor] ✓ Waiting for Wayland surface to connect...";
        emit appLaunched(command, pid);
    } else {
        qWarning() << "[WaylandCompositor] ✗ Failed to start app:" << actualCommand;
        qWarning() << "[WaylandCompositor] ✗ Error:" << process->errorString();
        m_processes.remove(process);
        process->deleteLater();
    }
}

void WaylandCompositor::closeWindow(int surfaceId)
{
    if (m_surfaceMap.contains(surfaceId)) {
        QWaylandSurface *surface = m_surfaceMap[surfaceId];
        if (surface) {
            QWaylandClient *client = surface->client();
            if (client) {
                qDebug() << "[WaylandCompositor] Terminating client for surface ID:" << surfaceId;
                client->close();
                
                for (auto it = m_processes.begin(); it != m_processes.end(); ++it) {
                    QProcess *process = it.key();
                    if (process && process->state() != QProcess::NotRunning) {
                        process->terminate();
                        if (!process->waitForFinished(1000)) {
                            qDebug() << "[WaylandCompositor] Force killing process for surface ID:" << surfaceId;
                            process->kill();
                        }
                        break;
                    }
                }
            }
        }
    }
}

QObject* WaylandCompositor::getSurfaceById(int surfaceId)
{
    return m_surfaceMap.value(surfaceId, nullptr);
}

void WaylandCompositor::handleSurfaceCreated(QWaylandSurface *surface)
{
    qDebug() << "[WaylandCompositor] Surface created:" << surface;
    
    connect(surface, &QWaylandSurface::surfaceDestroyed,
            this, &WaylandCompositor::handleSurfaceDestroyed);
    
    int surfaceId = m_nextSurfaceId++;
    m_surfaceMap[surfaceId] = surface;
    surface->setProperty("surfaceId", surfaceId);
    
    if (surface->client()) {
        qint64 pid = surface->client()->processId();
        if (pid > 0) {
            m_pidToSurfaceId[pid] = surfaceId;
            m_surfaceIdToPid[surfaceId] = pid;
            qInfo() << "[WaylandCompositor] Linked PID" << pid << "to surface ID" << surfaceId;
        }
    }
    
    m_surfaces.append(surface);
    emit surfacesChanged();
    // DON'T emit surfaceCreated yet - wait for XDG toplevel to be created first
}

void WaylandCompositor::handleXdgToplevelCreated(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface)
{
    qInfo() << "[WaylandCompositor] XDG Toplevel created:"
             << "title=" << (toplevel->title().isEmpty() ? "(empty)" : toplevel->title())
             << "appId=" << (toplevel->appId().isEmpty() ? "(empty)" : toplevel->appId());
    
    QWaylandSurface *surface = xdgSurface->surface();
    if (surface) {
        qInfo() << "[WaylandCompositor] Setting up signal handlers for title/appId changes...";
        // Store BOTH the xdgSurface (for ShellSurfaceItem) and toplevel (for configuration)
        surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));
        surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
        surface->setProperty("title", toplevel->title());
        surface->setProperty("appId", toplevel->appId());
        
        int surfaceId = surface->property("surfaceId").toInt();
        qInfo() << "[WaylandCompositor] Stored xdgSurface on surface, surfaceId:" << surfaceId;
        
        // NOW emit surfaceCreated with surfaceId, xdgSurface AND toplevel
        emit surfaceCreated(surface, surfaceId, xdgSurface);
        
        // Connect signals WITHOUT Qt::UniqueConnection and QPointer - use direct pointers
        // The 'this' context ensures proper cleanup when compositor is destroyed
        bool titleConnected = connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [surface, toplevel]() {
            surface->setProperty("title", toplevel->title());
            qInfo() << "[WaylandCompositor] *** Title updated to:" << (toplevel->title().isEmpty() ? "(empty)" : toplevel->title());
        });
        
        bool appIdConnected = connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, [surface, toplevel]() {
            surface->setProperty("appId", toplevel->appId());
            qInfo() << "[WaylandCompositor] *** App ID updated to:" << (toplevel->appId().isEmpty() ? "(empty)" : toplevel->appId());
        });
        
        qInfo() << "[WaylandCompositor] Signal handlers connected: titleChanged=" << titleConnected << "appIdChanged=" << appIdConnected;
    }
}

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface)
{
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();
    
    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());
        
        // Connect signal with direct pointers - 'this' context ensures cleanup
        connect(wlShellSurface, &QWaylandWlShellSurface::titleChanged, this, [surface, wlShellSurface]() {
            surface->setProperty("title", wlShellSurface->title());
        });
    }
}

void WaylandCompositor::handleSurfaceDestroyed()
{
    QWaylandSurface *surface = qobject_cast<QWaylandSurface*>(sender());
    if (!surface) return;
    
    int surfaceId = surface->property("surfaceId").toInt();
    qDebug() << "[WaylandCompositor] Surface destroyed, ID:" << surfaceId;
    
    if (m_surfaceIdToPid.contains(surfaceId)) {
        qint64 pid = m_surfaceIdToPid[surfaceId];
        m_pidToSurfaceId.remove(pid);
        m_surfaceIdToPid.remove(surfaceId);
        qDebug() << "[WaylandCompositor] Cleaned up PID mapping for" << pid;
    }
    
    m_surfaceMap.remove(surfaceId);
    m_surfaces.removeAll(surface);
    
    emit surfacesChanged();
    emit surfaceDestroyed(surface, surfaceId);
}

void WaylandCompositor::handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    QProcess *process = qobject_cast<QProcess*>(sender());
    if (!process) return;
    
    QString command = m_processes.value(process, "unknown");
    qint64 pid = process->processId();
    
    // gapplication launch spawns a subprocess and exits immediately, so PID tracking doesn't work
    bool isGApplication = command.contains("gapplication launch");
    
    if (isGApplication) {
        // For gapplication commands, we rely on surface-based tracking, not PID
        qInfo() << "[WaylandCompositor] gapplication process finished:" << command
                 << "exitCode:" << exitCode
                 << "(surface tracking active, not PID-based)";
    } else {
        qInfo() << "[WaylandCompositor] Process finished:" << command
                 << "PID:" << pid
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
        qInfo() << "[WaylandCompositor] Closing surface for PID" << pid << "surfaceId:" << surfaceId;
        
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

void WaylandCompositor::handleProcessError(QProcess::ProcessError error)
{
    QProcess *process = qobject_cast<QProcess*>(sender());
    if (!process) return;
    
    QString command = m_processes.value(process, "unknown");
    QString errorString;
    
    switch (error) {
        case QProcess::FailedToStart:
            errorString = "Failed to start (executable not found or insufficient permissions)";
            break;
        case QProcess::Crashed:
            errorString = "Crashed";
            break;
        case QProcess::Timedout:
            errorString = "Timed out";
            break;
        case QProcess::WriteError:
            errorString = "Write error";
            break;
        case QProcess::ReadError:
            errorString = "Read error";
            break;
        default:
            errorString = "Unknown error";
            break;
    }
    
    qWarning() << "[WaylandCompositor] Process error for" << command << ":" << errorString;
    qWarning() << "[WaylandCompositor] Error details:" << process->errorString();
    
    // Read any error output
    QString output = QString::fromLocal8Bit(process->readAllStandardOutput());
    QString errorOutput = QString::fromLocal8Bit(process->readAllStandardError());
    if (!output.isEmpty()) {
        qDebug() << "[WaylandCompositor] stdout:" << output;
    }
    if (!errorOutput.isEmpty()) {
        qDebug() << "[WaylandCompositor] stderr:" << errorOutput;
    }
}

