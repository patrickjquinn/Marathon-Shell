#pragma once

#include <QObject>
#include <QHash>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>
#include <qqml.h>

#include "marathon-shell-native/src/cgroup.cxxqt.h"

class TaskModel;
class AppLaunchService;

class AppLifecycleManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    // App lifecycle states. See docs/PERF_LIFECYCLE.md for the full model;
    // briefly: Foreground/BackgroundActive/BackgroundIdle keep the process
    // running; Frozen halts CPU via cgroup.freeze (wired in Phase B); Killed
    // means the runner exited (memory pressure or user-initiated close).
    enum LifecycleState : quint8 {
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

    Q_INVOKABLE void     registerApp(const QString &appId, QObject *appInstance);
    Q_INVOKABLE void     unregisterApp(const QString &appId);
    Q_INVOKABLE QObject *getAppInstance(const QString &appId) const;

    Q_INVOKABLE void     bringToForeground(const QString &appId);
    Q_INVOKABLE void     restoreApp(const QString &appId);
    // Thaws a frozen background app without bringing it forward; it may
    // freeze again after the debounce.
    Q_INVOKABLE void     wakeApp(const QString &appId);
    Q_INVOKABLE void     launchAppWithRoute(const QString &appId, const QString &route,
                                            const QString &paramsJson);

    Q_INVOKABLE bool     handleSystemBack();
    Q_INVOKABLE bool     handleSystemForward();
    Q_INVOKABLE bool     minimizeForegroundApp();

    Q_INVOKABLE void     closeApp(const QString &appId, bool skipNativeClose = false);
    Q_INVOKABLE void     prepareClose(const QString &appId);
    Q_INVOKABLE void     broadcastLowMemory();

    // Memory-pressure kill path: pick the longest-frozen app, SIGTERM with
    // 5 s grace then SIGKILL. Returns the killed PID or -1 if no Frozen
    // app exists. Wired from MemoryPressureMonitor::Critical in main.cpp.
    Q_INVOKABLE int         killOldestFrozenApp();

    // Session stop: thaw and SIGTERM every app (a Keel app's host turns
    // SIGTERM into CloseRequested), SIGKILL what is left after graceMs, then
    // emit allAppsStopped. No app is frozen again afterwards.
    void                    stopAllApps(int graceMs);

    Q_INVOKABLE int         lifecycleState(const QString &appId) const;
    Q_INVOKABLE QStringList activeCapabilities(const QString &appId) const;

    // System-observed signals (MPRIS2, Telephony, future nav) drive these.
    // Apps will also reach them via DBus in Phase B (BeginBackgroundTask).
    Q_INVOKABLE void addCapability(const QString &appId, const QString &capability);
    Q_INVOKABLE void removeCapability(const QString &appId, const QString &capability);

    // Debounce window between BackgroundIdle entry and Frozen transition.
    // Default 10s. Settable for tests + the Doze entry path (which pins
    // it to 0 so background apps freeze immediately when the screen
    // goes off, then restores the saved value on Doze exit).
    Q_INVOKABLE void setIdleFreezeDebounceMs(int ms);
    Q_INVOKABLE int  idleFreezeDebounceMs() const {
        return m_idleFreezeDebounceMs;
    }

    // The app in front, as the compositor sees it; Android apps have no
    // lifecycle state, so only their CPU boost follows it.
    void setFrontApp(const QString &appId);

  signals:
    void appRegistered(const QString &appId, QObject *appInstance);
    void appUnregistered(const QString &appId);
    void stateChanged(const QString &appId, int oldState, int newState);
    void capabilitiesChanged(const QString &appId);
    // Back went to an out-of-process app asynchronously and it declined.
    void systemBackUnhandled();
    void allAppsStopped();

  protected:
    // The unified cgroup path of a process, from /proc/<pid>/cgroup.
    virtual QString cgroupOfPid(qint64 pid) const;

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
        // Bumped when a pending freeze is cancelled, so a PrepareFreeze
        // reply that arrives after it does not freeze the app.
        quint32        freezeSeq       = 0;
    };

    bool        ensureTaskExists(const QString &appId);

    static bool invokeVoid(QObject *obj, const char *method);
    static bool invokeBool(QObject *obj, const char *method, bool *out = nullptr);
    // Back or forward to the foreground native app's window, in the compositor.
    bool        invokeNative(QObject *app, const char *method) const;

    QVariantMap appInfoFromInstance(const QString &appId, QObject *instance) const;

    // State machine internals. transitionTo is the single mutation point;
    // helpers below decide which state to enter on background events.
    void                              transitionTo(const QString &appId, LifecycleState newState);
    void                              onForegroundExit(const QString &appId);
    void                              startIdleFreezeDebounce(const QString &appId, bool grace = false);
    void                              cancelIdleFreezeDebounce(const QString &appId);
    void                              freezeApp(const QString &appId);
    void                              setAppFrozen(const QString &appId, bool frozen);
    void                              writeOomScoreAdj(const QString &appId, LifecycleState state);
    static int                        oomScoreForState(LifecycleState state);

    QPointer<TaskModel>               m_taskModel;
    QPointer<AppLaunchService>        m_appLaunchService;
    rust::Box<marathon::cgroup::AppCgroups> m_cgroups;

    QHash<QString, QPointer<QObject>> m_appRegistry;
    QHash<QString, AppState>          m_appStates;
    QString                           m_foregroundAppId;
    QString                           m_frontAndroidApp;
    QStringList                       m_pendingForegroundApps;
    int                               m_idleFreezeDebounceMs = 10000;
    bool                              m_stopping             = false;
};
