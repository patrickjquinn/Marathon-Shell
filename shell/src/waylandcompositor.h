#ifndef WAYLANDCOMPOSITOR_H
#define WAYLANDCOMPOSITOR_H

#include <QObject>
#include <QWaylandCompositor>
#include <QWaylandSurface>
#include <QWaylandQuickSurface>
#include <QWaylandXdgShell>
#include <QWaylandWlShell>
#include <QWaylandQuickOutput>
#include <QWaylandViewporter>
#include <QWaylandClient>
#include <QWaylandSeat>
#include <QQuickWindow>
#include <QMap>
#include <QProcess>

// Forward declaration
class SettingsManager;

class WaylandCompositor : public QWaylandCompositor {
    Q_OBJECT
    Q_PROPERTY(QQmlListProperty<QObject> surfaces READ surfaces NOTIFY surfacesChanged)
    Q_PROPERTY(QWaylandQuickOutput *output READ output CONSTANT)

  public:
    explicit WaylandCompositor(QQuickWindow *window, SettingsManager *settingsManager);
    ~WaylandCompositor() override;

    QQmlListProperty<QObject> surfaces();
    QWaylandQuickOutput      *output() const {
        return m_output;
    }
    Q_INVOKABLE void     launchApp(const QString &command);
    Q_INVOKABLE void     closeWindow(int surfaceId);
    Q_INVOKABLE QObject *getSurfaceById(int surfaceId);
    Q_INVOKABLE void     setCompositorActive(bool active);
    Q_INVOKABLE void     setOutputOrientation(const QString &orientation);

  signals:
    void surfacesChanged();
    void surfaceCreated(QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface);
    void surfaceDestroyed(QWaylandSurface *surface, int surfaceId);
    void popupCreated(QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface,
                      QWaylandSurface *parentSurface);
    void appLaunched(const QString &command, int pid);
    void appClosed(int pid);
    void systemBackTriggered();
    void systemHomeTriggered();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private slots:
    void handleSurfaceCreated(QWaylandSurface *surface);
    void handleXdgToplevelCreated(QWaylandXdgToplevel *toplevel, QWaylandXdgSurface *xdgSurface);
    void handleXdgPopupCreated(QWaylandXdgPopup *popup, QWaylandXdgSurface *xdgSurface);
    void handleWlShellSurfaceCreated(QWaylandWlShellSurface *wlShellSurface);
    void handleSurfaceDestroyed();
    void handleProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleProcessError(QProcess::ProcessError error);

  private:
    void                            setCompositorRealtimePriority();
    void                            calculateAndSetPhysicalSize();

    QWaylandXdgShell               *m_xdgShell;
    QWaylandWlShell                *m_wlShell;
    QWaylandViewporter             *m_viewporter;
    QWaylandQuickOutput            *m_output;
    QQuickWindow                   *m_window;
    SettingsManager                *m_settingsManager;

    QList<QObject *>                m_surfaces;
    QMap<int, QWaylandSurface *>    m_surfaceMap;    // surfaceId -> surface
    QMap<int, QWaylandXdgSurface *> m_xdgSurfaceMap; // surfaceId -> xdgSurface (for graceful close)
    QMap<QProcess *, QString>       m_processes;     // process -> command
    QMap<qint64, int>               m_pidToSurfaceId; // PID -> surfaceId
    QMap<int, qint64>               m_surfaceIdToPid; // surfaceId -> PID

    int                             m_nextSurfaceId;
};

#endif // WAYLANDCOMPOSITOR_H
