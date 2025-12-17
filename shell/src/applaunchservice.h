#pragma once

#include <QObject>
#include <QSet>
#include <QVariantMap>
#include <QPointer>

class AppModel;
class TaskModel;

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

    Q_PROPERTY(QVariantMap pendingNativeApp READ pendingNativeApp NOTIFY pendingNativeAppChanged)

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
    void        setAppLifecycleManager(QObject *obj);

    QVariantMap pendingNativeApp() const {
        return m_pendingNativeApp;
    }

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
    void pendingNativeAppChanged();

    void appLaunchStarted(const QString &appId, const QString &appName);
    void appLaunchCompleted(const QString &appId, const QString &appName);
    void appLaunchFailed(const QString &appId, const QString &appName, const QString &error);
    void appLaunchProgress(const QString &appId, int percent);

  private:
    QVariantMap resolveAppObject(const QVariant &app) const;
    bool launchNativeApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);
    bool launchMarathonApp(const QVariantMap &app, QObject *compositorRef, QObject *appWindowRef);

    static bool         invokeVoid(QObject *obj, const char *method, const QVariantList &args);
    static bool         invokeBool(QObject *obj, const char *method, const QVariantList &args,
                                   bool *out = nullptr);

    QPointer<AppModel>  m_appModel;
    QPointer<TaskModel> m_taskModel;

    QPointer<QObject>   m_compositor;
    QPointer<QObject>   m_appWindow;
    QPointer<QObject>   m_uiStore;
    QPointer<QObject>   m_appLifecycleManager;

    QVariantMap         m_pendingNativeApp;
    QSet<QString>       m_launchingApps;
};
