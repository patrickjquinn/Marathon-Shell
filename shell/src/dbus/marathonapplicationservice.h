#ifndef MARATHONAPPLICATIONSERVICE_H
#define MARATHONAPPLICATIONSERVICE_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QVariantMap>
#include <QVariantList>
#include <QStringList>

class MarathonAppRegistry;
class MarathonAppLoader;
class TaskModel;

class MarathonApplicationService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathon.ApplicationService")

  public:
    explicit MarathonApplicationService(MarathonAppRegistry *registry, MarathonAppLoader *loader,
                                        TaskModel *taskModel, QObject *parent = nullptr);
    ~MarathonApplicationService();

    bool registerService();

  public slots:
    QString      LaunchApp(const QString &appId, const QVariantMap &params);
    QVariantList ListApps(const QVariantMap &filter);
    QVariantMap  GetAppInfo(const QString &appId);
    bool         CloseApp(const QString &appId);
    bool         FocusApp(const QString &appId);
    QStringList  RunningApps();
    bool         PreloadApp(const QString &appId);

  signals:
    void AppLaunched(const QString &appId);
    void AppClosed(const QString &appId);
    void AppFocused(const QString &appId);
    void Error(const QString &appId, const QString &message);

  private:
    MarathonAppRegistry *m_registry;
    MarathonAppLoader   *m_loader;
    TaskModel           *m_taskModel;
};

#endif // MARATHONAPPLICATIONSERVICE_H
