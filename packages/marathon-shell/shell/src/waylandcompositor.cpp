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
        delete process;
    }
}

QQmlListProperty<QObject> WaylandCompositor::surfaces()
{
    return QQmlListProperty<QObject>(this, &m_surfaces);
}

void WaylandCompositor::launchApp(const QString &command)
{
    qDebug() << "[WaylandCompositor] Launching app:" << command;
    
    QProcess *process = new QProcess(this);
    
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("WAYLAND_DISPLAY", socketName());
    env.insert("XDG_RUNTIME_DIR", qgetenv("XDG_RUNTIME_DIR"));
    env.insert("QT_QPA_PLATFORM", "wayland");
    env.insert("GDK_BACKEND", "wayland");
    env.insert("CLUTTER_BACKEND", "wayland");
    env.insert("SDL_VIDEODRIVER", "wayland");
    process->setProcessEnvironment(env);
    
    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &WaylandCompositor::handleProcessFinished);
    connect(process, &QProcess::errorOccurred,
            this, &WaylandCompositor::handleProcessError);
    
    m_processes[process] = command;
    
    process->start("/bin/sh", {"-c", command});
    
    if (process->waitForStarted()) {
        qDebug() << "[WaylandCompositor] App launched successfully, PID:" << process->processId();
        emit appLaunched(command, process->processId());
    } else {
        qDebug() << "[WaylandCompositor] Failed to launch app:" << command;
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
            qDebug() << "[WaylandCompositor] Linked PID" << pid << "to surface ID" << surfaceId;
        }
    }
    
    m_surfaces.append(surface);
    emit surfacesChanged();
    emit surfaceCreated(surface);
}

void WaylandCompositor::handleXdgToplevelCreated(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface)
{
    qDebug() << "[WaylandCompositor] XDG Toplevel created:"
             << "title=" << toplevel->title()
             << "appId=" << toplevel->appId();
    
    QWaylandSurface *surface = xdgSurface->surface();
    if (surface) {
        surface->setProperty("xdgToplevel", QVariant::fromValue(toplevel));
        surface->setProperty("title", toplevel->title());
        surface->setProperty("appId", toplevel->appId());
        
        connect(toplevel, &QWaylandXdgToplevel::titleChanged, this, [surface, toplevel]() {
            surface->setProperty("title", toplevel->title());
        });
        
        connect(toplevel, &QWaylandXdgToplevel::appIdChanged, this, [surface, toplevel]() {
            surface->setProperty("appId", toplevel->appId());
        });
    }
}

void WaylandCompositor::handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface)
{
    qDebug() << "[WaylandCompositor] WlShell surface created:" << wlShellSurface->title();
    
    QWaylandSurface *surface = wlShellSurface->surface();
    if (surface) {
        surface->setProperty("wlShellSurface", QVariant::fromValue(wlShellSurface));
        surface->setProperty("title", wlShellSurface->title());
        
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
    emit surfaceDestroyed(surface);
}

void WaylandCompositor::handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    QProcess *process = qobject_cast<QProcess*>(sender());
    if (!process) return;
    
    QString command = m_processes.value(process, "unknown");
    qDebug() << "[WaylandCompositor] Process finished:"
             << command
             << "exitCode=" << exitCode
             << "status=" << (exitStatus == QProcess::NormalExit ? "normal" : "crashed");
    
    emit appClosed(process->processId());
    
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
            errorString = "Failed to start";
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
    
    qDebug() << "[WaylandCompositor] Process error:" << command << "-" << errorString;
}

