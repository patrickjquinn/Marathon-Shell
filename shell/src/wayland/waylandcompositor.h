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
#include <QWaylandTextInputManager>
#include <QWaylandIdleInhibitManagerV1>
#include <QWaylandClient>
#include <QWaylandSeat>
#include <QQuickWindow>
#include <QMap>
#include <QProcess>
#include <QPointer>

class TextInputManagerV3;

class WaylandCompositor : public QWaylandCompositor {
    Q_OBJECT
    Q_PROPERTY(QQmlListProperty<QObject> surfaces READ surfaces NOTIFY surfacesChanged)
    Q_PROPERTY(QWaylandQuickOutput *output READ output CONSTANT)
    Q_PROPERTY(bool hasIdleInhibitingSurface READ hasIdleInhibitingSurface NOTIFY
                   hasIdleInhibitingSurfaceChanged)

  public:
    explicit WaylandCompositor(QQuickWindow *window);
    ~WaylandCompositor() override;

    QQmlListProperty<QObject> surfaces();
    QWaylandQuickOutput      *output() const {
        return m_output;
    }

    Q_INVOKABLE void     launchApp(const QString &command, const QVariantMap &env = {});
    Q_INVOKABLE void     closeWindow(int surfaceId);
    Q_INVOKABLE void     activateSurface(int surfaceId);
    Q_INVOKABLE QObject *getSurfaceById(int surfaceId);
    Q_INVOKABLE void     setCompositorActive(bool active);
    Q_INVOKABLE void     setOutputOrientation(const QString &orientation);
    Q_INVOKABLE void     injectKey(int key, int modifiers, bool pressed);
    Q_INVOKABLE bool     checkIdleInhibitors();

    bool                 hasIdleInhibitingSurface() const {
        return m_hasIdleInhibitor;
    }

  signals:
    void surfacesChanged();
    void surfaceCreated(QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface);
    void surfaceDestroyed(QWaylandSurface *surface, int surfaceId);
    void appLaunched(const QString &command, int pid);
    void appClosed(int pid);
    void systemBackTriggered();
    void systemHomeTriggered();
    void nativeTextInputPanelRequested(bool show);
    void hasIdleInhibitingSurfaceChanged();

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
    void handleTextInputEnabled(bool enabled);

  private:
    void                                    setCompositorRealtimePriority();
    void                                    calculateAndSetPhysicalSize();

    QWaylandXdgShell                       *m_xdgShell                 = nullptr;
    QWaylandWlShell                        *m_wlShell                  = nullptr;
    QWaylandViewporter                     *m_viewporter               = nullptr;
    QWaylandTextInputManager               *m_textInputManager         = nullptr;
    TextInputManagerV3                     *m_textInputManagerV3Custom = nullptr;
    QWaylandIdleInhibitManagerV1           *m_idleInhibitManager       = nullptr;
    QWaylandQuickOutput                    *m_output                   = nullptr;
    QQuickWindow                           *m_window                   = nullptr;

    QList<QObject *>                        m_surfaces;
    QMap<int, QPointer<QWaylandSurface>>    m_surfaceMap;
    QMap<int, QPointer<QWaylandXdgSurface>> m_xdgSurfaceMap;
    QMap<QProcess *, QString>               m_processes;
    QMap<qint64, int>                       m_pidToSurfaceId;
    QMap<int, qint64>                       m_surfaceIdToPid;

    int                                     m_nextSurfaceId;
    bool                                    m_hasIdleInhibitor;
};

#endif
