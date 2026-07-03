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
#include <QAtomicInt>

class TextInputManagerV3;
class SecurityContextManagerV1;
class FifoManagerV1;
class CommitTimingManagerV1;
class LinuxDmabufManagerV1;

class WaylandCompositor : public QWaylandCompositor {
    Q_OBJECT
    Q_PROPERTY(QQmlListProperty<QObject> surfaces READ surfaces NOTIFY surfacesChanged)
    Q_PROPERTY(QWaylandQuickOutput *output READ output CONSTANT)
    Q_PROPERTY(bool hasIdleInhibitingSurface READ hasIdleInhibitingSurface NOTIFY
                   hasIdleInhibitingSurfaceChanged)
    // MARATHON_DISCARD_FRONT: let the foreground surface item release the
    // client's buffer as soon as it has composited it, instead of holding it
    // until the client's next commit. Shortens the double-buffer dependency
    // chain that starves a scrolling client on etnaviv's implicit fencing.
    Q_PROPERTY(bool discardFrontBuffer READ discardFrontBuffer CONSTANT)

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
    Q_INVOKABLE void     nudgeSurface(int surfaceId);
    Q_INVOKABLE QObject *getSurfaceById(int surfaceId);
    Q_INVOKABLE void     setCompositorActive(bool active);
    Q_INVOKABLE void     setOutputOrientation(const QString &orientation);
    Q_INVOKABLE void     injectKey(int key, int modifiers, bool pressed);
    Q_INVOKABLE bool     checkIdleInhibitors();

    // Emits xdg_toplevel.configure with state_suspended (9) added to or
    // removed from the toplevel's state list. The xdg-shell v6 suspend
    // state lets cooperating clients (Qt, Chromium) pause their render
    // loop voluntarily — paired with the AppLifecycleManager BgIdle/
    // Frozen transitions for graceful suspend before cgroup.freeze.
    Q_INVOKABLE void sendSuspendedState(const QString &appId, bool suspended);

    bool             hasIdleInhibitingSurface() const {
        return m_hasIdleInhibitor;
    }

    bool             discardFrontBuffer() const {
        return m_discardFrontBuffer;
    }

  signals:
    void surfacesChanged();
    void surfaceCreated(QWaylandSurface *surface, int surfaceId, QWaylandXdgSurface *xdgSurface);
    void surfaceDestroyed(QWaylandSurface *surface, int surfaceId);
    void appLaunched(const QString &command, int pid);
    void appClosed(int pid);
    void systemBackTriggered();
    void systemHomeTriggered();
    void userActivity();
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
    void setCompositorRealtimePriority();
    void calculateAndSetPhysicalSize();
    // DPMS-off/on the primary output (opt-in via MARATHON_DOZE_DPMS).
    // Called from setCompositorActive with render already paused/resumed.
    // Drives the CRTC's ACTIVE property directly via a libdrm atomic
    // commit (the wlroots#1889-clean path for the mxsfb DSI panel).
    void setDisplayPowerState(bool on);
    bool initAtomicDisplay();

    // Cached DRM handles for the ACTIVE-property display-off path.
    int                                     m_driFd               = -1;
    uint32_t                                m_crtcId              = 0;
    uint32_t                                m_crtcActivePropId    = 0;
    bool                                    m_atomicDisplayReady  = false;
    bool                                    m_atomicDisplayFailed = false;

    QWaylandXdgShell                       *m_xdgShell                 = nullptr;
    QWaylandWlShell                        *m_wlShell                  = nullptr;
    QWaylandViewporter                     *m_viewporter               = nullptr;
    QWaylandTextInputManager               *m_textInputManager         = nullptr;
    TextInputManagerV3                     *m_textInputManagerV3Custom = nullptr;
    SecurityContextManagerV1               *m_securityContextManager   = nullptr;
    FifoManagerV1                          *m_fifoManager              = nullptr;
    CommitTimingManagerV1                  *m_commitTimingManager      = nullptr;
    LinuxDmabufManagerV1                   *m_linuxDmabufManager       = nullptr;
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

    // Present-pipeline (MARATHON_PRESENT_PIPELINE): removes the ~4-vblank
    // app<->compositor round-trip that throttles client scroll to ~15fps on
    // this in-process compositor (client swap blocks ~67ms, both sides idle).
    // Sends wl_surface.frame at frame START (beforeSynchronizing) so the
    // client renders concurrently, and free-runs the compositor at vsync
    // while a client is actively committing so its buffer lands next vblank.
    bool                                    m_presentPipeline = false;
    // Frames of vsync free-run remaining before the compositor idles back to
    // 0fps. Refreshed on every client commit (QWaylandSurface::redraw),
    // decremented each frameSwapped. Touched from render + GUI threads.
    QAtomicInt                              m_activeFrameCredits{0};

    bool                                    m_discardFrontBuffer = false;

    // MARATHON_PRESENT_STATS: low-volume (one line/sec) present meter --
    // compositor frames swapped and client buffer commits per second, so
    // scroll rate can be measured without the per-frame QSG_RENDER_TIMING
    // flood that backpressures the log pipe and stalls the GUI thread.
    QAtomicInt                              m_frameSwapCount{0};
    QAtomicInt                              m_clientCommitCount{0};
};

#endif
