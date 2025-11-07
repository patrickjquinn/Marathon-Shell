#include "waylandcompositor.h"
#include <QDebug>
#include <QTimer>
#include <QPointer>
#include <QDateTime>
#include <QWaylandXdgToplevel>
#include <QWaylandXdgSurface>

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#endif

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
    
    // Configure output for mobile form factor
    QScreen *screen = window->screen();
    if (screen) {
        qreal screenDpi = screen->logicalDotsPerInch();
        qreal devicePixelRatio = screen->devicePixelRatio();
        
        // CRITICAL: For mobile compositor, ALWAYS use scale=1
        // - scale=1 means apps render at native resolution (e.g., 1080x2400 pixels)
        // - Physical output size (mm) determines mobile vs desktop, NOT scale factor
        // - Mobile toolkits (libadwaita, Kirigami) use physical size to trigger adaptive layouts
        // - Using scale>1 causes blur because apps render at lower res then upscale
        int scaleFactor = 1;
        
        m_output->setScaleFactor(scaleFactor);
        
        // CRITICAL: Set physical size to achieve ~96 DPI (standard desktop DPI)
        // 
        // GTK calculates DPI as: pixels / physical_size_mm * 25.4
        // For 540 pixels at 96 DPI: 540 / 96 * 25.4 = 143mm
        // 
        // Why 96 DPI and not higher?
        // - Mobile apps use ADAPTIVE LAYOUTS (triggered by narrow width + LIBADWAITA_MOBILE)
        // - They don't need high DPI scaling (that's for desktop apps on 4K monitors)
        // - Physical size matters for FORM FACTOR detection (narrow = mobile), not DPI
        // - Using small physical size (68mm) caused ~200 DPI → GTK scaled UI 2x → too big!
        //
        // This gives us:
        // - Mobile form factor (narrow width triggers adaptive layouts)
        // - Standard 96 DPI (no unwanted 2x UI scaling)
        // - Sharp rendering (scale=1 means native pixel resolution)
        int physicalWidth = 143;   // millimeters (for 540px at 96 DPI)
        int physicalHeight = 302;  // millimeters (for 1140px at 96 DPI)
        
        // Keep aspect ratio consistent
        QSize pixelSize = window->size();
        qreal aspectRatio = (qreal)pixelSize.height() / (qreal)pixelSize.width();
        physicalHeight = (int)(physicalWidth * aspectRatio);
        
        m_output->setPhysicalSize(QSize(physicalWidth, physicalHeight));
        
        qInfo() << "[WaylandCompositor] Output configured for MOBILE form factor:";
        qInfo() << "[WaylandCompositor]   Scale factor:" << scaleFactor;
        qInfo() << "[WaylandCompositor]   Pixel size:" << pixelSize;
        qInfo() << "[WaylandCompositor]   Physical size:" << physicalWidth << "x" << physicalHeight << "mm (~6\" phone)";
        qInfo() << "[WaylandCompositor]   DPI:" << screenDpi << "devicePixelRatio:" << devicePixelRatio;
    } else {
        m_output->setScaleFactor(1);
        m_output->setPhysicalSize(QSize(68, 136));  // Default mobile size
        qWarning() << "[WaylandCompositor] No screen available, using defaults";
    }
    
    setSocketName("marathon-wayland-0");
    
    create();
    
    // Note: Keyboard focus is managed automatically by QWaylandCompositor in Qt6
    // The defaultInputDevice() API was removed in newer Qt6 versions
    // Keyboard focus handling is now done internally by the compositor
    
    qDebug() << "[WaylandCompositor] Initialized on socket:" << socketName()
             << "output size:" << m_output->window()->size();
    
    // Set RT priority for compositor rendering thread (Priority 75 per spec)
    setCompositorRealtimePriority();
    
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
    
    // CRITICAL FIX: Prevent GTK/GApplication apps from connecting to host/previous instances
    // Apps like Nautilus/Clocks use GApplication's single-instance D-Bus mechanism
    // They check D-Bus for existing instances and send "open window" commands to them
    // This causes windows to open in host compositor OR connect to stale D-Bus names
    // 
    // Solution: Generate UNIQUE GApplication ID per app launch (not just per Marathon instance!)
    // This isolates each launch from host AND previous Marathon launches
    
    // CRITICAL: Use timestamp + command hash for uniqueness per launch
    // GApplication uses this to determine the D-Bus application name
    qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
    uint commandHash = qHash(actualCommand);
    QString uniqueDesktopFile = QString("/tmp/marathon-apps/app-%1-%2.desktop")
        .arg(timestamp)
        .arg(commandHash);
    env.insert("GIO_LAUNCHED_DESKTOP_FILE", uniqueDesktopFile);
    
    // Also set unique application ID to prevent D-Bus collision
    QString uniqueAppId = QString("marathon.app.%1.%2")
        .arg(timestamp)
        .arg(commandHash);
    env.insert("GIO_LAUNCHED_DESKTOP_FILE_PID", QString::number(QCoreApplication::applicationPid()));
    
    qInfo() << "[WaylandCompositor] Isolated app from host single-instance via unique desktop file";
    qInfo() << "[WaylandCompositor] GIO_LAUNCHED_DESKTOP_FILE:" << uniqueDesktopFile;
    qInfo() << "[WaylandCompositor] Unique App ID:" << uniqueAppId;
    
    // Set OUR compositor variables
    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");
    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    
    // CRITICAL: Mobile form factor environment variables
    // These tell GTK4/libadwaita apps to use mobile/adaptive layouts
    env.insert("LIBADWAITA_MOBILE", "1");      // Force libadwaita mobile mode
    env.insert("GTK_USE_PORTAL", "0");         // Disable portals (causes issues in nested compositor)
    env.insert("PURISM_FORM_FACTOR", "phone"); // Phosh compatibility
    
    // Force client-side decorations for GTK apps (better mobile experience)
    env.insert("GTK_CSD", "1");
    
    // NOTE: DO NOT set GDK_SCALE or GDK_DPI_SCALE!
    // These are X11-only variables and are IGNORED on Wayland.
    // Under Wayland, scaling is communicated via wl_output::scale (set to 1 above)
    // and apps receive physical size (68mm) to detect mobile form factor.
    //
    // Reference: https://discourse.gnome.org/t/scaling-ui-for-hidpi-display-under-non-gnome-wayland/17545
    // Reference: https://docs.gtk.org/gtk4/x11.html (these vars are X11-specific)
    
    // Qt mobile hints
    env.insert("QT_QUICK_CONTROLS_MOBILE", "1");
    env.insert("QT_QUICK_CONTROLS_STYLE", "Material");
    
    process->setProcessEnvironment(env);
    
    qInfo() << "[WaylandCompositor] ===== LAUNCHING APP =====";
    qInfo() << "[WaylandCompositor] Original command:" << command;
    qInfo() << "[WaylandCompositor] Actual command:" << actualCommand;
    qInfo() << "[WaylandCompositor] WAYLAND_DISPLAY:" << socketName();
    qInfo() << "[WaylandCompositor] XDG_RUNTIME_DIR:" << runtimeDir;
    qInfo() << "[WaylandCompositor] GDK_BACKEND:" << env.value("GDK_BACKEND");
    qInfo() << "[WaylandCompositor] DBUS_SESSION_BUS_ADDRESS:" << env.value("DBUS_SESSION_BUS_ADDRESS");
    qInfo() << "[WaylandCompositor] 📱 MOBILE ENV VARS:";
    qInfo() << "[WaylandCompositor]   LIBADWAITA_MOBILE:" << env.value("LIBADWAITA_MOBILE");
    qInfo() << "[WaylandCompositor]   PURISM_FORM_FACTOR:" << env.value("PURISM_FORM_FACTOR");
    qInfo() << "[WaylandCompositor]   GTK_USE_PORTAL:" << env.value("GTK_USE_PORTAL");
    qInfo() << "[WaylandCompositor]   GTK_CSD:" << env.value("GTK_CSD");
    qInfo() << "[WaylandCompositor]   QT_QUICK_CONTROLS_MOBILE:" << env.value("QT_QUICK_CONTROLS_MOBILE");
    qInfo() << "[WaylandCompositor] 📡 WAYLAND SCALING (via compositor wl_output protocol):";
    qInfo() << "[WaylandCompositor]   wl_output::scale = 1 (native resolution)";
    qInfo() << "[WaylandCompositor]   wl_output::physical_size = 68x143mm (mobile phone)";
    
    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred,
            this, &WaylandCompositor::handleProcessError);
    
    // Use separate channels to properly capture stderr on errors
    process->setProcessChannelMode(QProcess::SeparateChannels);
    
    // Capture stdout for debugging (only in verbose mode)
    // Use QPointer for safe process access
    QPointer<QProcess> safeProcess(process);
    connect(process, &QProcess::readyReadStandardOutput, this, [safeProcess, command]() {
        if (!safeProcess) return;
        QString output = QString::fromLocal8Bit(safeProcess->readAllStandardOutput());
        QString debugEnv = qgetenv("MARATHON_DEBUG");
        bool debugMode = (debugEnv == "1" || debugEnv.toLower() == "true");
        if (debugMode && !output.trimmed().isEmpty()) {
            qDebug() << "[WaylandCompositor] App stdout:" << command << "->" << output.trimmed();
        }
    });
    
    // Always capture stderr for error reporting
    // Use QPointer for safe process access
    connect(process, &QProcess::readyReadStandardError, this, [safeProcess, command]() {
        if (!safeProcess) return;
        QString error = QString::fromLocal8Bit(safeProcess->readAllStandardError());
        if (!error.trimmed().isEmpty()) {
            qWarning() << "[WaylandCompositor] App stderr:" << command << "->" << error.trimmed();
        }
    });
    
    m_processes[process] = actualCommand;
    
    qDebug() << "[WaylandCompositor] Starting process:" << actualCommand;
    process->start("/bin/sh", {"-c", actualCommand});
    
    // ✅ NON-BLOCKING: Connect to started() signal instead of waitForStarted()
    connect(process, &QProcess::started, this, [this, process, command]() {
        qint64 pid = process->processId();
        qInfo() << "[WaylandCompositor] ✓ App process started successfully, PID:" << pid;
        qInfo() << "[WaylandCompositor] ✓ Waiting for Wayland surface to connect...";
        emit appLaunched(command, pid);
    });
}

void WaylandCompositor::closeWindow(int surfaceId)
{
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
        qInfo() << "[WaylandCompositor] Sending graceful close request (XDG protocol) to surface ID:" << surfaceId;
        xdgSurface->toplevel()->sendClose();
    } else {
        // Fallback: If not XDG shell, close client connection
        QWaylandClient *client = surface->client();
        if (client) {
            qWarning() << "[WaylandCompositor] No XDG toplevel found, falling back to client close for surface ID:" << surfaceId;
            client->close();
        }
    }
    
    // Find the specific process for this surface (by PID mapping)
    qint64 pid = m_surfaceIdToPid.value(surfaceId, -1);
    if (pid <= 0) {
        qDebug() << "[WaylandCompositor] No PID mapping for surface ID:" << surfaceId;
        return;  // Let the surface close naturally
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
        return;  // Process already exited or doesn't exist
    }
    
    // Give the app time to close gracefully (most apps will close within 3-5 seconds)
    // Use QPointer for safe pointer checking (process might be deleted if it exits)
    QPointer<QProcess> safeProcessPtr(targetProcess);
    
    qDebug() << "[WaylandCompositor] Waiting for PID" << pid << "to exit gracefully...";
    QTimer::singleShot(5000, this, [this, safeProcessPtr, surfaceId, pid]() {
        // Check if process object still exists and is still running
        if (!safeProcessPtr) {
            qInfo() << "[WaylandCompositor] Process" << pid << "exited gracefully (object deleted) for surface ID:" << surfaceId;
            return;
        }
        
        if (safeProcessPtr->state() != QProcess::NotRunning) {
            qWarning() << "[WaylandCompositor] Process" << pid << "didn't exit after 5s, sending SIGTERM";
            safeProcessPtr->terminate();
            
            // Last resort: kill after 3 more seconds
            QTimer::singleShot(3000, this, [safeProcessPtr, pid]() {
                if (safeProcessPtr && safeProcessPtr->state() != QProcess::NotRunning) {
                    qWarning() << "[WaylandCompositor] Force killing process" << pid;
                    safeProcessPtr->kill();
                }
            });
        } else {
            qInfo() << "[WaylandCompositor] Process" << pid << "exited gracefully for surface ID:" << surfaceId;
        }
    });
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
        // CRITICAL: Store xdgSurface for graceful close via sendClose()
        m_xdgSurfaceMap[surfaceId] = xdgSurface;
        qInfo() << "[WaylandCompositor] Stored xdgSurface on surface, surfaceId:" << surfaceId;
        
        // NOW emit surfaceCreated with surfaceId, xdgSurface AND toplevel
        emit surfaceCreated(surface, surfaceId, xdgSurface);
        
        // Connect signals with QPointer for safe access to toplevel
        // Note: Explicitly specify 'this' as receiver context to avoid "Could not find receiver" warnings
        QPointer<QWaylandXdgToplevel> safeToplevel(toplevel);
        QPointer<QWaylandSurface> safeSurface(surface);
        
        connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [safeToplevel, safeSurface]() {
            if (safeToplevel && safeSurface) {
                safeSurface->setProperty("title", safeToplevel->title());
                qInfo() << "[WaylandCompositor] *** Title updated to:" << (safeToplevel->title().isEmpty() ? "(empty)" : safeToplevel->title());
            }
        }, Qt::UniqueConnection);
        
        connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, [safeToplevel, safeSurface]() {
            if (safeToplevel && safeSurface) {
                safeSurface->setProperty("appId", safeToplevel->appId());
                qInfo() << "[WaylandCompositor] *** App ID updated to:" << (safeToplevel->appId().isEmpty() ? "(empty)" : safeToplevel->appId());
            }
        }, Qt::UniqueConnection);
        
        qInfo() << "[WaylandCompositor] Signal handlers connected for surfaceId:" << surfaceId;
    }
}

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface)
{
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();
    
    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        int surfaceId = surface->property("surfaceId").toInt();
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());
        
        // Connect signal with QPointer for safe access
        // Note: Explicitly specify 'this' as receiver context to avoid "Could not find receiver" warnings
        QPointer<QWaylandWlShellSurface> safeWlShell(wlShellSurface);
        QPointer<QWaylandSurface> safeSurface(surface);
        connect(wlShellSurface, &QWaylandWlShellSurface::titleChanged, this, [safeWlShell, safeSurface]() {
            if (safeWlShell && safeSurface) {
                safeSurface->setProperty("title", safeWlShell->title());
            }
        }, Qt::UniqueConnection);
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
    m_xdgSurfaceMap.remove(surfaceId);  // Clean up XDG surface mapping too
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

void WaylandCompositor::setCompositorRealtimePriority()
{
#ifdef Q_OS_LINUX
    // Set RT priority 75 for compositor render thread (per Marathon OS spec section 3)
    struct sched_param param;
    param.sched_priority = 75;
    
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) == 0) {
        qInfo() << "[WaylandCompositor] ✓ Compositor thread set to RT priority 75 (SCHED_FIFO)";
    } else {
        qWarning() << "[WaylandCompositor] ⚠ Failed to set RT priority (need CAP_SYS_NICE or limits.conf)";
    }
#else
    qDebug() << "[WaylandCompositor] RT scheduling not available (not Linux)";
#endif
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

