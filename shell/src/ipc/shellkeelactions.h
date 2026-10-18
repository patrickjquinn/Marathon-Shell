#pragma once

#include <QDBusContext>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QVariantMap>

class AppModel;
class TaskModel;
class AppLaunchService;
class AppLifecycleManager;
class UIStore;
class SessionStore;
class DisplayPolicyController;

// The shell's Keel Actions (org.shipwright.Keel.Actions on org.marathonos.shell,
// manifest shell/dbus/keel-actions.json): navigation an app cannot offer, for
// keel-mcp. Processes the shell started (its apps) may only Describe.
class ShellKeelActions : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Keel.Actions")

  public:
    ShellKeelActions(AppModel *apps, TaskModel *tasks, AppLaunchService *launchService,
                     AppLifecycleManager *lifecycle, UIStore *uiStore, SessionStore *session,
                     DisplayPolicyController *display, QObject *parent = nullptr);

    bool registerOnSessionBus();

  public slots:
    QString Describe();
    QString Invoke(const QString &action, const QString &arguments, const QVariantMap &options);
    QString GetEntity(const QString &type, const QString &id);
    QString FindEntities(const QString &type, const QString &query, uint limit);
    QString GetContext();

  private:
    bool                        fromApp() const;
    QString                     fail(const QString &code, const QString &message);
    QString                     run(const QString &action, const QJsonObject &args);

    AppModel                   *m_apps;
    TaskModel                  *m_tasks;
    AppLaunchService           *m_launchService;
    AppLifecycleManager        *m_lifecycle;
    UIStore                    *m_uiStore;
    SessionStore               *m_session;
    DisplayPolicyController    *m_display;
    QByteArray                  m_manifest;
    QHash<QString, QJsonObject> m_tools;
};
