#pragma once

#include <QObject>
#include <QHash>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QVariantMap>
#include <qqml.h>

class TaskModel;
class AppLaunchService;

class AppLifecycleManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit AppLifecycleManager(TaskModel *taskModel, AppLaunchService *appLaunchService,
                                 QObject *parent = nullptr);

    Q_INVOKABLE void     registerApp(const QString &appId, QObject *appInstance);
    Q_INVOKABLE void     unregisterApp(const QString &appId);
    Q_INVOKABLE QObject *getAppInstance(const QString &appId) const;

    Q_INVOKABLE void     bringToForeground(const QString &appId);
    Q_INVOKABLE void     restoreApp(const QString &appId);
    // Launch with an in-app route + params. The route is plumbed through to
    // the runner via --route on the command line and exposed to QML as the
    // MARATHON_APP_ROUTE context property. Used by the lock-screen Emergency
    // affordance (route="/emergency") and any future deep-linking.
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

  signals:
    void appRegistered(const QString &appId, QObject *appInstance);
    void appUnregistered(const QString &appId);

  private:
    struct AppState {
        bool   isActive     = false;
        bool   isPaused     = false;
        bool   isMinimized  = false;
        qint64 launchTimeMs = 0;
        qint64 lastActiveMs = 0;
    };

    bool                ensureTaskExists(const QString &appId);

    static bool         invokeVoid(QObject *obj, const char *method);
    static bool         invokeBool(QObject *obj, const char *method, bool *out = nullptr);
    static bool         invokeInjectKey(QObject *compositor, int key, int modifiers, bool pressed);

    QVariantMap         appInfoFromInstance(const QString &appId, QObject *instance) const;

    QPointer<TaskModel> m_taskModel;
    QPointer<AppLaunchService>        m_appLaunchService;

    QHash<QString, QPointer<QObject>> m_appRegistry;
    QHash<QString, AppState>          m_appStates;
    QString                           m_foregroundAppId;
    QStringList                       m_pendingForegroundApps;
};
