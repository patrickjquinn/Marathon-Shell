#pragma once

#include <QObject>
#include <QSet>
#include <QVariantMap>
#include <QPointer>
#include <QHash>

class AppModel;
class TaskModel;

#if defined(HAVE_WAYLAND)
class QWaylandSurface;
class QWaylandXdgSurface;
#endif

/**
 * C++ replacement for `shell/qml/services/AppLaunchService.qml`.
 *
 * Keeps launch state and app lookup in C++ (perf/maintainability), while still
 * interoperating with QML singletons for UI state via QObject pointers set from QML:
 * - uiStore: UIStore singleton (openApp/restoreApp)
 * - appLifecycleManager: AppLifecycleManager singleton (isAppRunning/bringToForeground)
 *
 * QML sets these from `MarathonShell.qml` after startup.
 */
class AppLaunchService : public QObject {
    Q_OBJECT

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
    Q_INVOKABLE void closeNativeApp(int surfaceId);

    Q_INVOKABLE bool isAppLaunching(const QString &appId) const;
    Q_INVOKABLE bool cancelLaunch(const QString &appId);

  signals:
    void compositorChanged();
    void appWindowChanged();
    void uiStoreChanged();
    void appLifecycleManagerChanged();

    void appLaunchStarted(const QString &appId, const QString &appName);
    void appLaunchCompleted(const QString &appId, const QString &appName);
    void appLaunchFailed(const QString &appId, const QString &appName, const QString &error);
    void appLaunchProgress(const QString &appId, int percent);

  private:
    struct PendingLaunch {
        QString appId;
        QString name;
        QString icon;
        QString command; // the exact string passed into WaylandCompositor.launchApp()
        qint64  pid = -1;
    };

    QVariantMap resolveAppObject(const QVariant &app) const;
    bool launchNativeApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);
    bool launchMarathonApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);

    static bool invokeVoid(QObject *obj, const char *method, const QVariantList &args);
    static bool invokeBool(QObject *obj, const char *method, const QVariantList &args,
                           bool *out = nullptr);

    void        onCompositorAppLaunched(const QString &command, qint64 pid);
    void        onCompositorAppClosed(qint64 pid);
#if defined(HAVE_WAYLAND)
    void onCompositorSurfaceCreated(QWaylandSurface *surface, int surfaceId,
                                    QWaylandXdgSurface *xdgSurface);
#endif

    QPointer<AppModel>  m_appModel;
    QPointer<TaskModel> m_taskModel;

    QPointer<QObject>   m_compositor;
    QPointer<QObject>   m_appWindow;
    QPointer<QObject>   m_uiStore;
    QPointer<QObject>   m_appLifecycleManager;

    QSet<QString>       m_launchingApps;

    // Pending launches keyed by the command string passed to launchApp().
    QHash<QString, PendingLaunch> m_pendingByCommand;
    // Active launches keyed by pid (for surface correlation + cleanup).
    QHash<qint64, PendingLaunch> m_activeByPid;

  public:
    // Used by IPC layer to enforce strict isolation: DBus sender PID → appId.
    Q_INVOKABLE QString appIdForPid(qint64 pid) const;
    // Fallback for strict IPC: used when an app calls DBus before we observed its pid via compositor
    // signals. Only the shell may register mappings.
    void registerPidForAppId(qint64 pid, const QString &appId);

    // Used by lifecycle routing: determine if an appId is a Marathon app (vs native desktop app).
    Q_INVOKABLE bool isMarathonAppId(const QString &appId) const;

    // Used by shell UI gestures: send lifecycle navigation events to the isolated app runner.
    Q_INVOKABLE bool sendBackToRunner(const QString &appId);
    Q_INVOKABLE bool sendForwardToRunner(const QString &appId);

  private:
    QHash<qint64, QString> m_pidToAppId;
    QHash<QString, qint64> m_appIdToPid;
};
