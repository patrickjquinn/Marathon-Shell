#ifndef NOTIFICATIONHANDLERCPP_H
#define NOTIFICATIONHANDLERCPP_H

#include <QObject>

#include <functional>
#include <QPointer>
#include <QVariantMap>

class Apps;
class NotificationServiceCpp;
class NavigationRouterCpp;
class Modem;

class NotificationHandlerCpp : public QObject {
    Q_OBJECT

  public:
    explicit NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                    NavigationRouterCpp *router, Modem *telephony,
                                    Apps *registry, QObject *parent = nullptr);

    // Shows an app the registry cannot open (an Android app, a desktop app):
    // true if it could. opensItself: the tap ran the app's default action.
    void             setShowApp(std::function<bool(const QString &, bool)> showApp) {
        m_showApp = std::move(showApp);
    }

    Q_INVOKABLE void handleNotificationClick(int id);
    Q_INVOKABLE void handleNotificationAction(int id, const QString &action);

  private:
    QVariantMap                      findNotification(int id) const;
    void                             navigateToNotificationTarget(const QVariantMap &notification);

    QPointer<NotificationServiceCpp> m_notifications;
    QPointer<NavigationRouterCpp>    m_router;
    QPointer<Modem>       m_telephony;
    QPointer<Apps>                   m_registry;
    std::function<bool(const QString &, bool)> m_showApp;
};

#endif
