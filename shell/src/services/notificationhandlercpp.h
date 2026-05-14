#ifndef NOTIFICATIONHANDLERCPP_H
#define NOTIFICATIONHANDLERCPP_H

#include <QObject>
#include <QPointer>
#include <QVariantMap>

class NotificationServiceCpp;
class NavigationRouterCpp;
class TelephonyService;
class SMSService;

class NotificationHandlerCpp : public QObject {
    Q_OBJECT

  public:
    explicit NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                    NavigationRouterCpp *router, TelephonyService *telephony,
                                    SMSService *sms, QObject *parent = nullptr);

    Q_INVOKABLE void handleNotificationClick(int id);
    Q_INVOKABLE void handleNotificationAction(int id, const QString &action);
    Q_INVOKABLE bool handleNotificationReply(int id, const QString &text);

  signals:
    // Fires for replies the shell can't route locally (e.g. UnifiedPush).
    // Subscribers can forward via org.freedesktop.Notifications.NotificationReplied.
    void replyUnhandled(int id, const QString &appId, const QString &text);

  private:
    QVariantMap                      findNotification(int id) const;
    void                             navigateToNotificationTarget(const QVariantMap &notification);

    QPointer<NotificationServiceCpp> m_notifications;
    QPointer<NavigationRouterCpp>    m_router;
    QPointer<TelephonyService>       m_telephony;
    QPointer<SMSService>             m_sms;
};

#endif
