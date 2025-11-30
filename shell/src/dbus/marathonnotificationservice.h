#ifndef MARATHONNOTIFICATIONSERVICE_H
#define MARATHONNOTIFICATIONSERVICE_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QVariantMap>
#include <QVariantList>
#include "notificationdatabase.h"

class NotificationModel;

class MarathonNotificationService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathon.NotificationService")

  public:
    explicit MarathonNotificationService(NotificationDatabase *database, NotificationModel *model,
                                         QObject *parent = nullptr);
    ~MarathonNotificationService();

    bool registerService();

  public slots:
    uint         Notify(const QString &appId, const QString &title, const QString &body,
                        const QVariantMap &options);
    QVariantList GetNotifications(const QString &appId);
    QVariantList GetUnreadNotifications();
    bool         CloseNotification(uint id);
    bool         CloseAllNotifications();
    bool         MarkAsRead(uint id);
    int          GetUnreadCount();
    void         InvokeAction(uint notificationId, const QString &actionId);

  signals:
    void NotificationReceived(uint id, const QString &appId, const QString &title,
                              const QString &body);
    void NotificationClosed(uint id);
    void ActionInvoked(uint notificationId, const QString &actionId);
    void AllNotificationsCleared();

  private:
    NotificationDatabase *m_database;
    NotificationModel    *m_model;

    QVariantMap notificationToVariantMap(const NotificationDatabase::NotificationRecord &record);
};

#endif // MARATHONNOTIFICATIONSERVICE_H
