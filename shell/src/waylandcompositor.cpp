#include "waylandcompositor.h"
#include "settingsmanager.h"
#include <QDebug>
#include <QTimer>
#include <QPointer>
#include <QDateTime>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QWaylandXdgToplevel>
#include <QWaylandXdgSurface>
#include <QtMath>

#ifdef Q_OS_LINUX
#include <sched.h>
#include <pthread.h>
#endif

WaylandCompositor::WaylandCompositor(QQuickWindow *window, SettingsManager *settingsManager)
    : QWaylandCompositor()
    , m_window(window)
    , m_settingsManager(settingsManager)
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
    
    // CRITICAL: Force Wayland output scale factor to 1 for sharp rendering
    //
    // Even though we disabled Qt's HiDPI scaling in main.cpp, the host display may still have
    // devicePixelRatio=2. By explicitly setting scaleFactor=1, we tell Wayland clients to render
    // at 1:1 pixel ratio (540x1140) instead of being influenced by the host's HiDPI settings.
    //
    // This ensures sharp, non-blurry rendering of embedded native apps.
    m_output->setScaleFactor(1);
    
    // CRITICAL: Set physical size for mobile DPI detection
    // This tells GTK, Qt, and other toolkits that this is a mobile device
    calculateAndSetPhysicalSize();
    
    setSocketName("marathon-wayland-0");
    
    create();
    
    // Note: Keyboard focus is managed automatically by QWaylandCompositor in Qt6
    // The defaultInputDevice() API was removed in newer Qt6 versions
    // Keyboard focus handling is now done internally by the compositor
    
    qDebug() << "[WaylandCompositor] Initialized on socket:" << socketName() 
             << "- output:" << window->size() << "(scale=" << m_output->scaleFactor() << ")";
    
    // Set RT priority for compositor rendering thread (Priority 75 per spec)
    setCompositorRealtimePriority();
    
    // NOTE: We no longer create a custom D-Bus session - apps use the host's session
    // This prevents 25-second timeouts waiting for system services (GeoClue2, etc.)
    
    // React to user scale factor changes
    connect(m_settingsManager, &SettingsManager::userScaleFactorChanged,
            this, &WaylandCompositor::calculateAndSetPhysicalSize);
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
    
    // CRITICAL: Force new instances of GApplication apps
    // GApplication apps check D-Bus for existing instances and send commands to them instead
    // of launching new windows. This causes apps to open in the host compositor.
    //
    // Solution: Create a temporary unique desktop file for each launch
    // GApplication extracts the app ID from the desktop file basename and uses it for D-Bus registration.
    // A unique desktop file path forces a unique D-Bus name, preventing detection of host instances.
    qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
    uint commandHash = qHash(actualCommand);
    
    // Create /tmp/marathon-apps directory if it doesn't exist
    QDir tmpDir("/tmp/marathon-apps");
    if (!tmpDir.exists()) {
        tmpDir.mkpath(".");
    }
    
    // Create unique desktop file path
    QString uniqueDesktopFile = QString("/tmp/marathon-apps/marathon-%1-%2.desktop")
        .arg(timestamp)
        .arg(commandHash);
    
    // Create a properly formatted desktop file for GApplication
    // GApplication uses the desktop file basename for D-Bus name generation and parses
    // various fields. Including all standard fields prevents GLib warnings and ensures
    // proper application behavior across GTK, Qt, and other toolkits.
    QFile desktopFile(uniqueDesktopFile);
    if (desktopFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&desktopFile);
        out << "[Desktop Entry]\n";
        out << "Version=1.0\n";                                    // Desktop Entry Spec version
        out << "Type=Application\n";
        out << "Name=Marathon Embedded App\n";
        out << "GenericName=Application\n";
        out << "Comment=Application running in Marathon OS\n";
        out << "Exec=" << actualCommand << "\n";
        out << "Terminal=false\n";                                 // Not a terminal app
        out << "Categories=Utility;\n";                            // FreeDesktop category
        out << "StartupNotify=true\n";                             // Supports startup notification
        out << "X-GNOME-UsesNotifications=false\n";                // Prevent notification parsing
        out << "X-Marathon-Embedded=true\n";                       // Custom field for identification
        desktopFile.close();
        
        qDebug() << "[WaylandCompositor] Created desktop file with full specification compliance";
    } else {
        qWarning() << "[WaylandCompositor] Failed to create desktop file:" << uniqueDesktopFile;
    }
    
    env.insert("GIO_LAUNCHED_DESKTOP_FILE", uniqueDesktopFile);
    env.insert("GIO_LAUNCHED_DESKTOP_FILE_PID", QString::number(QCoreApplication::applicationPid()));
    
    qDebug() << "[WaylandCompositor] Created unique desktop file:" << uniqueDesktopFile;
    
    // Set OUR compositor variables
    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", runtimeDir);
    env.insert("QT_QPA_PLATFORM", "wayland");
    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    
    // Mobile form factor environment variables
    // These tell GTK4/libadwaita and Qt apps to use mobile/adaptive layouts
    env.insert("LIBADWAITA_MOBILE", "1");              // Force libadwaita mobile mode
    env.insert("PURISM_FORM_FACTOR", "phone");         // Phosh compatibility (used by Phosh/Purism apps)
    env.insert("QT_QUICK_CONTROLS_MOBILE", "1");       // Qt Quick Controls mobile mode
    env.insert("QT_QUICK_CONTROLS_STYLE", "Mobile");   // Qt Quick Controls mobile style
    env.insert("GTK_CSD", "1");                        // Force client-side decorations for GTK apps
    env.insert("GTK_USE_PORTAL", "0");                 // Disable portals (can cause issues in nested compositors)
    
    process->setProcessEnvironment(env);
    
    qDebug() << "[WaylandCompositor] Launching:" << command;
    
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
    
    if (process->waitForStarted(3000)) {
        qint64 pid = process->processId();
        qInfo() << "[WaylandCompositor] Started PID" << pid;
        emit appLaunched(command, pid);
    } else {
        qWarning() << "[WaylandCompositor] Failed to start:" << actualCommand << "-" << process->errorString();
        m_processes.remove(process);
        process->deleteLater();
    }
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
    qDebug() << "[WaylandCompositor] XDG Toplevel created for surface";
    
    QWaylandSurface *surface = xdgSurface->surface();
    if (surface) {
        // Store BOTH the xdgSurface (for ShellSurfaceItem) and toplevel (for configuration)
        surface->setProperty("xdgSurface", QVariant::fromValue(xdgSurface));
        surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
        surface->setProperty("title", toplevel->title());
        surface->setProperty("appId", toplevel->appId());
        
        int surfaceId = surface->property("surfaceId").toInt();
        // CRITICAL: Store xdgSurface for graceful close via sendClose()
        m_xdgSurfaceMap[surfaceId] = xdgSurface;
        
        // NOW emit surfaceCreated with surfaceId, xdgSurface AND toplevel
        emit surfaceCreated(surface, surfaceId, xdgSurface);
        
        // Connect signals with QPointer for safe access to toplevel and surface
        QPointer<QWaylandXdgToplevel> safeToplevel(toplevel);
        QPointer<QWaylandSurface> safeSurface(surface);
        
        connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [this, safeToplevel, safeSurface]() {
            if (safeToplevel && safeSurface) {
                safeSurface->setProperty("title", safeToplevel->title());
            }
        });
        
        connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, [this, safeToplevel, safeSurface]() {
            if (safeToplevel && safeSurface) {
                safeSurface->setProperty("appId", safeToplevel->appId());
            }
        });
        
        // CRITICAL: Monitor hasContent changes to detect when app hides its window
        // Many GNOME/GTK apps don't terminate when you click their internal X button
        // They just unmap the surface and keep running in the background
        connect(surface, &QWaylandSurface::hasContentChanged, this, [this, safeSurface, surfaceId]() {
            if (safeSurface && !safeSurface->hasContent()) {
                qInfo() << "[WaylandCompositor] Surface lost content (window hidden/unmapped) - surfaceId:" << surfaceId;
                qInfo() << "[WaylandCompositor] Treating as app close and destroying surface";
                
                // CRITICAL: Emit surfaceDestroyed signal BEFORE cleaning up internal state
                // so QML handlers can still access the surface if needed
                qInfo() << "[WaylandCompositor] Emitting surfaceDestroyed signal for surfaceId:" << surfaceId;
                emit surfaceDestroyed(safeSurface.data(), surfaceId);
                qInfo() << "[WaylandCompositor] surfaceDestroyed signal emitted";
                
                // Clean up our internal state
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

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface)
{
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();
    
    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        int surfaceId = surface->property("surfaceId").toInt();
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());
        
        // Connect signal with QPointer for safe access
        QPointer<QWaylandWlShellSurface> safeWlShell(wlShellSurface);
        QPointer<QWaylandSurface> safeSurface(surface);
        connect(wlShellSurface, &QWaylandWlShellSurface::titleChanged, this, [this, safeWlShell, safeSurface]() {
            if (safeWlShell && safeSurface) {
                safeSurface->setProperty("title", safeWlShell->title());
            }
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

void WaylandCompositor::calculateAndSetPhysicalSize()
{
    if (!m_window || !m_output || !m_settingsManager) {
        qWarning() << "[WaylandCompositor] Cannot calculate physical size - missing dependencies";
        return;
    }
    
    // ====================================================================================
    // DYNAMIC PHYSICAL SIZE CALCULATION FOR MOBILE APP DETECTION
    // ====================================================================================
    //
    // Problem: GTK4/libadwaita, Qt/KDE, and Firefox determine if they're running on a 
    // mobile device by calculating DPI from wl_output::physical_size and window dimensions.
    // Without physical_size, they default to ~96 DPI (desktop) regardless of window size.
    //
    // Solution: Calculate physical size based on:
    //   1. Window dimensions (from m_window->size())
    //   2. Target mobile DPI (typically 150-250 for phones)
    //   3. User's UI scale factor (from Settings)
    //
    // Formula: DPI = pixels / (mm / 25.4)
    //          mm = (pixels / DPI) * 25.4
    //
    // With user scale compensation:
    //   effectiveDPI = targetDPI / userScale
    //   (If user wants 125% scale, we report a "larger" physical size to compensate)
    //
    // ====================================================================================
    
    // Constants
    const qreal TARGET_MOBILE_DPI = 200.0;  // Typical modern phone: 200-300 PPI
    const qreal MM_PER_INCH = 25.4;
    
    // Get current state
    QSize windowSize = m_window->size();
    qreal userScale = m_settingsManager->userScaleFactor();  // 1.0 = 100%, 1.25 = 125%, etc.
    
    // Validate user scale
    if (userScale <= 0.0) {
        qWarning() << "[WaylandCompositor] Invalid user scale factor:" << userScale << "- using 1.0";
        userScale = 1.0;
    }
    
    // Calculate effective DPI accounting for user's scale preference
    // If user wants larger UI (scale > 1.0), we report smaller DPI to compensate
    qreal effectiveDPI = TARGET_MOBILE_DPI / userScale;
    
    // Calculate physical dimensions in millimeters
    qreal physicalWidthMM = (windowSize.width() / effectiveDPI) * MM_PER_INCH;
    qreal physicalHeightMM = (windowSize.height() / effectiveDPI) * MM_PER_INCH;
    
    QSize physicalSize(qRound(physicalWidthMM), qRound(physicalHeightMM));
    
    // Set the physical size on the output
    m_output->setPhysicalSize(physicalSize);
    
    // Calculate resulting DPI for logging
    qreal actualDPI = (windowSize.width() / physicalWidthMM) * MM_PER_INCH;
    qreal diagonalInches = qSqrt(qPow(physicalWidthMM / MM_PER_INCH, 2) + 
                                  qPow(physicalHeightMM / MM_PER_INCH, 2));
    
    qInfo() << "[WaylandCompositor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qInfo() << "[WaylandCompositor] Physical Size Configuration (Mobile Detection)";
    qInfo() << "[WaylandCompositor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qInfo() << "[WaylandCompositor]   Window size:       " << windowSize.width() << "x" << windowSize.height() << "px";
    qInfo() << "[WaylandCompositor]   User scale:        " << QString::number(userScale * 100, 'f', 0) << "% (" << userScale << ")";
    qInfo() << "[WaylandCompositor]   Target DPI:        " << TARGET_MOBILE_DPI;
    qInfo() << "[WaylandCompositor]   Effective DPI:     " << QString::number(effectiveDPI, 'f', 1);
    qInfo() << "[WaylandCompositor]   Physical size:     " << physicalSize.width() << "x" << physicalSize.height() << " mm";
    qInfo() << "[WaylandCompositor]   Resulting DPI:     " << QString::number(actualDPI, 'f', 1) << " (GTK/Qt will calculate this)";
    qInfo() << "[WaylandCompositor]   Screen diagonal:   " << QString::number(diagonalInches, 'f', 2) << " inches (virtual)";
    qInfo() << "[WaylandCompositor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qInfo() << "[WaylandCompositor] ✓ Apps will detect as mobile device";
    qInfo() << "[WaylandCompositor]   - GTK/libadwaita: Will use mobile layouts (AdwBreakpoint narrow mode)";
    qInfo() << "[WaylandCompositor]   - Qt/KDE: Will respect QT_QUICK_CONTROLS_MOBILE";
    qInfo() << "[WaylandCompositor]   - Firefox: Will calculate mobile-appropriate DPI";
    qInfo() << "[WaylandCompositor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
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
        qWarning() << "[WaylandCompositor]  Failed to set RT priority (need CAP_SYS_NICE or limits.conf)";
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

void WaylandCompositor::setCompositorActive(bool active)
{
    if (!m_window)
        return;

    if (active == m_window->isVisible())
        return;

    qDebug() << "[WaylandCompositor]" << (active ? "Resuming" : "Suspending") << "compositor window";
    m_window->setVisible(active);
}
