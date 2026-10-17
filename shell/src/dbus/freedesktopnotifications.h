#ifndef FREEDESKTOPNOTIFICATIONS_H
#define FREEDESKTOPNOTIFICATIONS_H

#include <QObject>
#include <QPointer>
#include <QDBusContext>
#include <QDBusConnection>
#include <QStringList>
#include <QVariantMap>
#include "notificationdatabase.h"

class MarathonAppRegistry;
class NotificationModel;
class PowerManagerCpp;

class FreedesktopNotifications : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

  public:
    explicit FreedesktopNotifications(NotificationDatabase *database, NotificationModel *model,
                                      PowerManagerCpp *powerManager, QObject *parent = nullptr);
    ~FreedesktopNotifications() override;

    bool registerService();

    // Lets notifications name the installed app they came from.
    void setAppRegistry(MarathonAppRegistry *registry);

    // A tap ("default") or an action button: tells the client, and makes the
    // D-Bus call a Nemo.Notifications client attached to that action.
    void activate(uint id, const QString &action);

  public slots:
    uint        Notify(const QString &app_name, uint replaces_id, const QString &app_icon,
                       const QString &summary, const QString &body, const QStringList &actions,
                       const QVariantMap &hints, int expire_timeout);

    void        CloseNotification(uint id);

    QStringList GetCapabilities();

    void        GetServerInformation(QString &name, QString &vendor, QString &version,
                                     QString &spec_version);

  signals:
    void NotificationClosed(uint id, uint reason);

    void ActionInvoked(uint id, const QString &action_key);

    void NotificationReplied(uint id, const QString &text);

  public slots:
    void InvokeReply(uint id, const QString &text);

  private:
    NotificationDatabase *m_database;
    NotificationModel    *m_model;
    PowerManagerCpp      *m_powerManager;
    QPointer<MarathonAppRegistry> m_registry;

    QString               extractAppName(const QString &provided, const QVariantMap &hints);

    int                   mapUrgencyToPriority(const QVariantMap &hints);
};

#endif
