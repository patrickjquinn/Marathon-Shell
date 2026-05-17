#pragma once

#include <QObject>
#include <QHash>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>
#include <qqml.h>

class TaskModel;
class AppLaunchService;
class CgroupManager;
class ForeignToplevelClient;

class AppLifecycleManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    // App lifecycle states. See docs/PERF_LIFECYCLE.md for the full model;
    // briefly: Foreground/BackgroundActive/BackgroundIdle keep the process
    // running; Frozen halts CPU via cgroup.freeze (wired in Phase B); Killed
    // means the runner exited (memory pressure or user-initiated close).
    enum LifecycleState {
        Unregistered     = 0,
        Foreground       = 1,
        BackgroundActive = 2,
        BackgroundIdle   = 3,
        Frozen           = 4,
        Killed           = 5,
    };
    Q_ENUM(LifecycleState)

    explicit AppLifecycleManager(TaskModel *taskModel, AppLaunchService *appLaunchService,
                                 QObject *parent = nullptr);

    // When wired, bringToForeground/closeApp route activate/close via
    // wlr_foreign_toplevel_handle_v1 in addition to the QML lifecycle
    // path. Optional: if unset or the client is inactive, only the QML
    // path runs (which still works for the in-shell compositor build).
    void                    setForeignToplevelClient(ForeignToplevelClient *client);

    Q_INVOKABLE void        registerApp(const QString &appId, QObject *appInstance);
    Q_INVOKABLE void        unregisterApp(const QString &appId);
    Q_INVOKABLE QObject    *getAppInstance(const QString &appId) const;

    Q_INVOKABLE void        bringToForeground(const QString &appId);
    Q_INVOKABLE void        restoreApp(const QString &appId);
    Q_INVOKABLE void        launchAppWithRoute(const QString &appId, const QString &route,
                                               const QString &paramsJson);

    Q_INVOKABLE bool        handleSystemBack();
    Q_INVOKABLE bool        handleSystemForward();
    Q_INVOKABLE bool        minimizeForegroundApp();

    Q_INVOKABLE void        closeApp(const QString &appId, bool skipNativeClose = false);
    Q_INVOKABLE void        broadcastLowMemory();

    Q_INVOKABLE QVariantMap getAppState(const QString &appId) const;
    Q_INVOKABLE bool        isAppRunning(const QString &appId) const;
    Q_INVOKABLE QString     getForegroundAppId() const;

    Q_INVOKABLE int         lifecycleState(const QString &appId) const;
    Q_INVOKABLE QStringList activeCapabilities(const QString &appId) const;

    // System-observed signals (MPRIS2, Telephony, future nav) drive these.
    // Apps will also reach them via DBus in Phase B (BeginBackgroundTask).
    Q_INVOKABLE void addCapability(const QString &appId, const QString &capability);
    Q_INVOKABLE void removeCapability(const QString &appId, const QString &capability);

    // Debounce window between BackgroundIdle entry and Frozen transition.
    // Default 10s. Settable for tests.
    Q_INVOKABLE void setIdleFreezeDebounceMs(int ms);

  signals:
    void appRegistered(const QString &appId, QObject *appInstance);
    void appUnregistered(const QString &appId);
    void stateChanged(const QString &appId, int oldState, int newState);
    void capabilitiesChanged(const QString &appId);

  private:
    struct AppState {
        LifecycleState state          = Unregistered;
        bool           isActive       = false;
        bool           isPaused       = false;
        bool           isMinimized    = false;
        qint64         launchTimeMs   = 0;
        qint64         lastActiveMs   = 0;
        qint64         stateEnteredMs = 0;
        QSet<QString>  capabilities;
        QTimer        *idleFreezeTimer = nullptr;
    };

    bool        ensureTaskExists(const QString &appId);

    static bool invokeVoid(QObject *obj, const char *method);
    static bool invokeBool(QObject *obj, const char *method, bool *out = nullptr);
    static bool invokeInjectKey(QObject *compositor, int key, int modifiers, bool pressed);

    QVariantMap appInfoFromInstance(const QString &appId, QObject *instance) const;

    // State machine internals. transitionTo is the single mutation point;
    // helpers below decide which state to enter on background events.
    void                              transitionTo(const QString &appId, LifecycleState newState);
    void                              onForegroundExit(const QString &appId);
    void                              startIdleFreezeDebounce(const QString &appId);
    void                              cancelIdleFreezeDebounce(const QString &appId);
    void                              writeOomScoreAdj(const QString &appId, LifecycleState state);
    static int                        oomScoreForState(LifecycleState state);

    QPointer<TaskModel>               m_taskModel;
    QPointer<AppLaunchService>        m_appLaunchService;
    CgroupManager                    *m_cgroup = nullptr;
    QPointer<ForeignToplevelClient>   m_foreignToplevelClient;

    QHash<QString, QPointer<QObject>> m_appRegistry;
    QHash<QString, AppState>          m_appStates;
    QString                           m_foregroundAppId;
    QStringList                       m_pendingForegroundApps;
    int                               m_idleFreezeDebounceMs = 10000;
};
