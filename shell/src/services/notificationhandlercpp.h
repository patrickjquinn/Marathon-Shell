#ifndef NOTIFICATIONHANDLERCPP_H
#define NOTIFICATIONHANDLERCPP_H

#include <QObject>
#include <QPointer>
#include <QVariantMap>

class NotificationServiceCpp;
class NavigationRouterCpp;
class TelephonyService;

class NotificationHandlerCpp : public QObject {
    Q_OBJECT

  public:
    explicit NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                    NavigationRouterCpp *router, TelephonyService *telephony,
                                    QObject *parent = nullptr);

    Q_INVOKABLE void handleNotificationClick(int id);
    Q_INVOKABLE void handleNotificationAction(int id, const QString &action);

  private:
    QVariantMap                      findNotification(int id) const;
    void                             navigateToNotificationTarget(const QVariantMap &notification);

    QPointer<NotificationServiceCpp> m_notifications;
    QPointer<NavigationRouterCpp>    m_router;
    QPointer<TelephonyService>       m_telephony;
};

#endif
