#pragma once

#include <QObject>
#include <QSet>
#include <QVariantMap>
#include <QPointer>
#include <QHash>
#include <qqml.h>

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
    Q_INVOKABLE void closeNativeApp(int surfaceId);

    Q_INVOKABLE bool isAppLaunching(const QString &appId) const;
    Q_INVOKABLE bool cancelLaunch(const QString &appId);

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
    void appLaunchProgress(const QString &appId, int percent);
    // Tracked app-runner exited. Subscribers receive the appId directly
    // so they don't have to translate PID → appId on their own.
    void appExited(const QString &appId);

    // Quick Settings shade requested over IPC. mode: 0 hide, 1 show, 2 toggle.
    void quickSettingsRequested(int mode);

  private:
    struct PendingLaunch {
        QString appId;
        QString name;
        QString icon;
        QString type;
        QString command;
        qint64  pid = -1;
    };

    QVariantMap resolveAppObject(const QVariant &app) const;
    bool launchNativeApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);
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
    QStringList spareSandboxArgs() const;
    QProcess   *m_spareProcess   = nullptr;
    qint64      m_sparePid       = -1;
    bool        m_spareAdoptable = false;
    int         m_spareFailures  = 0;

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

    QHash<QString, PendingLaunch> m_pendingByCommand;

    QHash<qint64, PendingLaunch>  m_activeByPid;

  public:
    Q_INVOKABLE QString appIdForPid(qint64 pid) const;
    Q_INVOKABLE qint64  pidForAppId(const QString &appId) const;

    void                registerPidForAppId(qint64 pid, const QString &appId);

  signals:
    void pidRegistered(qint64 pid, const QString &appId);
    void pidUnregistered(qint64 pid, const QString &appId);

  public:
    Q_INVOKABLE bool isMarathonAppId(const QString &appId) const;

    Q_INVOKABLE bool sendBackToRunner(const QString &appId);
    Q_INVOKABLE bool sendForwardToRunner(const QString &appId);

  private:
    QHash<qint64, QString> m_pidToAppId;
    QHash<QString, qint64> m_appIdToPid;
};
