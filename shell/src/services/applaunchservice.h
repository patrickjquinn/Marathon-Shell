#pragma once

#include <QObject>
#include <QSet>
#include <QVariantMap>
#include <QPointer>
#include <QHash>
#include <qqml.h>

#include <functional>

class AppModel;
class TaskModel;
class QProcess;

#if defined(HAVE_WAYLAND)
class QWaylandSurface;
class QWaylandXdgSurface;
#endif

class AppLaunchService : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QObject *compositor READ compositor WRITE setCompositor NOTIFY compositorChanged)
    Q_PROPERTY(QObject *appWindow READ appWindow WRITE setAppWindow NOTIFY appWindowChanged)
    Q_PROPERTY(QObject *uiStore READ uiStore WRITE setUiStore NOTIFY uiStoreChanged)
    Q_PROPERTY(QObject *appLifecycleManager READ appLifecycleManager WRITE setAppLifecycleManager
                   NOTIFY appLifecycleManagerChanged)

  public:
    explicit AppLaunchService(AppModel *appModel, TaskModel *taskModel, QObject *parent = nullptr);

    QObject *compositor() const {
        return m_compositor.data();
    }
    void     setCompositor(QObject *obj);

    QObject *appWindow() const {
        return m_appWindow.data();
    }
    void     setAppWindow(QObject *obj);

    QObject *uiStore() const {
        return m_uiStore.data();
    }
    void     setUiStore(QObject *obj);

    QObject *appLifecycleManager() const {
        return m_appLifecycleManager.data();
    }
    void             setAppLifecycleManager(QObject *obj);

    Q_INVOKABLE bool launchApp(const QVariant &app, QObject *compositorRef = nullptr,
                               QObject *appWindowRef = nullptr);
    // Variant that injects a route/params into the runner via --route /
    // MARATHON_APP_ROUTE. The runner exposes this to QML as a context
    // property so the app can show a route-specific entry point (e.g.
    // phone /emergency for the lock-screen emergency dialer).
    Q_INVOKABLE bool launchAppWithRoute(const QVariant &app, const QString &route,
                                        const QString &paramsJson, QObject *compositorRef = nullptr,
                                        QObject *appWindowRef = nullptr);
    // Starts the app without bringing it on screen: its window becomes a
    // task, the app in front stays. A running app is left where it is,
    // thawed if it was frozen.
    Q_INVOKABLE bool startAppInBackground(const QVariant &app);
    bool             isBackgroundLaunch(const QString &appId) const {
        return m_backgroundLaunches.contains(appId);
    }
    Q_INVOKABLE void closeNativeApp(int surfaceId);

    Q_INVOKABLE bool isAppLaunching(const QString &appId) const;

    // Request the shell's Quick Settings shade to open/close/toggle.
    // Called from the D-Bus NavigationObject (marathon CLI `qs` verb) so a
    // dev host can drive the shade over IPC — top-edge touch injection does
    // not reach the shell's statusBarDragArea. mode: 0 hide, 1 show, 2 toggle.
    // Emits quickSettingsRequested; MarathonShell.qml applies the lock guard
    // and calls UIStore. Kept as a signal (not a direct UIStore call) so the
    // shade's own !isLocked gate lives in one place, in QML.
    void requestQuickSettings(int mode) { emit quickSettingsRequested(mode); }

  signals:
    void compositorChanged();
    void appWindowChanged();
    void uiStoreChanged();
    void appLifecycleManagerChanged();

    void appLaunchStarted(const QString &appId, const QString &appName);
    void appLaunchCompleted(const QString &appId, const QString &appName);
    void appLaunchFailed(const QString &appId, const QString &appName, const QString &error);
    // A route for an app that was already running, so it must handle it live.
    void routeForRunningApp(const QString &appId, const QString &route,
                            const QString &paramsJson);
    void appLaunchProgress(const QString &appId, int percent);
    // Tracked app-runner exited. Subscribers receive the appId directly
    // so they don't have to translate PID → appId on their own.
    void appExited(const QString &appId);

    // Quick Settings shade requested over IPC. mode: 0 hide, 1 show, 2 toggle.
    void quickSettingsRequested(int mode);
    // A window the app shows above the app on screen (KeelDialog).
    void dialogSurfaceCreated(const QString &appId, QObject *xdgSurface, int surfaceId);

  private:
    struct PendingLaunch {
        QString appId;
        QString name;
        QString icon;
        QString type;
        QString command;
        QString sandboxInstance;
        qint64  pid = -1;
    };

    QVariantMap resolveAppObject(const QVariant &app) const;
    bool launchNativeApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);
    void  activateRunningApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);
    QSize initialAppSize() const;
    bool launchMarathonApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);

    // Per-launch route+params (set by launchAppWithRoute, consumed and
    // cleared by launchMarathonApp). Avoids changing the launchMarathonApp
    // signature for what is genuinely transient state.
    QString m_pendingRoute;
    QString m_pendingRouteParamsJson;

    // Warm runner pool: one spare marathon-app-runner kept pre-initialised
    // (libs loaded, Qt + Wayland connect done) inside a neutral sandbox,
    // waiting on stdin for its app id. Adoption skips the exec+ld+Qt-init
    // bucket that dominates cold-launch time.
    void        spawnSpareRunner();
    bool        adoptSpareRunner(const PendingLaunch &p);
    QString     runnerExecutablePath() const;
    QStringList spareSandboxArgs(const QString &waylandSocket) const;
    QString     openSandboxSocket(const QString &appId, const QString &instanceId) const;
    void        closeSandboxSocket(const QString &instanceId) const;
    QProcess   *m_spareProcess   = nullptr;
    qint64      m_sparePid       = -1;
    bool        m_spareAdoptable = false;
    int         m_spareFailures  = 0;
    int         m_spareHealthyDeaths = 0;

    static bool invokeVoid(QObject *obj, const char *method, const QVariantList &args);
    static bool invokeBool(QObject *obj, const char *method, const QVariantList &args,
                           bool *out = nullptr);

    void        onCompositorAppLaunched(const QString &command, qint64 pid);
    void        onCompositorAppClosed(qint64 pid);
#if defined(HAVE_WAYLAND)
    void onCompositorSurfaceCreated(QWaylandSurface *surface, int surfaceId,
                                    QWaylandXdgSurface *xdgSurface);
#endif

    QPointer<AppModel>            m_appModel;
    QPointer<TaskModel>           m_taskModel;

    QPointer<QObject>             m_compositor;
    QPointer<QObject>             m_appWindow;
    QPointer<QObject>             m_uiStore;
    QPointer<QObject>             m_appLifecycleManager;

    QSet<QString>                 m_launchingApps;
    // Started by startAppInBackground, until their window maps.
    QSet<QString>                 m_backgroundLaunches;
    bool                          m_startingInBackground = false;

    QHash<QString, PendingLaunch> m_pendingByCommand;

    QHash<qint64, PendingLaunch>  m_activeByPid;

  public:
    Q_INVOKABLE QString appIdForPid(qint64 pid) const;
    Q_INVOKABLE qint64  pidForAppId(const QString &appId) const;

    void                registerPidForAppId(qint64 pid, const QString &appId);

  signals:
    void pidRegistered(qint64 pid, const QString &appId);
    void pidUnregistered(qint64 pid, const QString &appId);
    // The runner answered Back with "not handled", or could not be reached.
    void runnerBackUnhandled(const QString &appId);
    // A native window showed no change after back (WaylandCompositor).
    void nativeBackUnhandled(int surfaceId);

  public:
    Q_INVOKABLE bool isMarathonAppId(const QString &appId) const;

    // Fire-and-forget: the outcome of Back arrives as runnerBackUnhandled.
    void sendBackToRunner(const QString &appId);
    void sendForwardToRunner(const QString &appId);
    // Tells a Keel app whether its cover is on screen (Cover.Active).
    Q_INVOKABLE void setCoverVisible(const QString &appId, bool visible);

    // A Keel app run under marathon-keel-host (SailfishLaunch).
    Q_INVOKABLE bool isKeelHostApp(const QString &appId) const;
    // Tells a hosted Keel app whether it is the foreground app (Active);
    // the runner takes it from its window instead.
    void setAppActive(const QString &appId, bool active);
    // The process to SIGTERM to stop an app: a hosted app's host, which
    // turns SIGTERM into CloseRequested.
    qint64 terminationPidForAppId(const QString &appId) const;

    // The app ships a Keel Actions manifest, so its runner owns
    // org.marathonos.<appId> for Keel.Actions.
    bool servesKeelActions(const QString &appId) const;
    // Asks the runner to give up that name before the app is frozen; done
    // runs on the reply, an error, or after a second without one.
    void prepareRunnerFreeze(const QString &appId, QObject *context,
                             const std::function<void()> &done);
    // The app was thawed: its runner takes the name back.
    void notifyRunnerThawed(const QString &appId);

  private:
    qint64                 hostPidForAppId(const QString &appId) const;

    QHash<qint64, QString> m_pidToAppId;
    QHash<QString, qint64> m_appIdToPid;
};
