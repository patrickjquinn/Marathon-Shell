#ifndef NOTIFICATIONHANDLERCPP_H
#define NOTIFICATIONHANDLERCPP_H

#include <QObject>

#include <functional>
#include <QPointer>
#include <QVariantMap>

class MarathonAppRegistry;
class NotificationServiceCpp;
class NavigationRouterCpp;
class TelephonyService;

class NotificationHandlerCpp : public QObject {
    Q_OBJECT

  public:
    explicit NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                    NavigationRouterCpp *router, TelephonyService *telephony,
                                    MarathonAppRegistry *registry, QObject *parent = nullptr);

    // Shows an app the registry cannot open (an Android app, a desktop app):
    // true if it could.
    void             setShowApp(std::function<bool(const QString &)> showApp) {
        m_showApp = std::move(showApp);
    }

    Q_INVOKABLE void handleNotificationClick(int id);
    Q_INVOKABLE void handleNotificationAction(int id, const QString &action);

  private:
    QVariantMap                      findNotification(int id) const;
    void                             navigateToNotificationTarget(const QVariantMap &notification);

    QPointer<NotificationServiceCpp> m_notifications;
    QPointer<NavigationRouterCpp>    m_router;
    QPointer<TelephonyService>       m_telephony;
    QPointer<MarathonAppRegistry>    m_registry;
    std::function<bool(const QString &)> m_showApp;
};

#endif
