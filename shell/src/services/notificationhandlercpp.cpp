#include "notificationhandlercpp.h"

#include "navigationroutercpp.h"
#include "notificationservicecpp.h"
#include "telephonyservice.h"

NotificationHandlerCpp::NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                               NavigationRouterCpp    *router,
                                               TelephonyService *telephony, QObject *parent)
    : QObject(parent)
    , m_notifications(notifications)
    , m_router(router)
    , m_telephony(telephony) {}

void NotificationHandlerCpp::handleNotificationClick(int id) {
    const QVariantMap notification = findNotification(id);
    if (notification.isEmpty())
        return;

    navigateToNotificationTarget(notification);
    if (m_notifications)
        m_notifications->dismissNotification(id);
}

void NotificationHandlerCpp::handleNotificationAction(int id, const QString &action) {
    const QVariantMap notification = findNotification(id);
    if (notification.isEmpty())
        return;

    const QString appId = notification.value("appId").toString();
    if (appId == "phone") {
        if (action == "call_back") {
            const QString number = notification.value("body").toString().replace("From: ", "");
            if (m_telephony)
                m_telephony->dial(number);
            if (m_router)
                m_router->navigateToDeepLink("phone", "", {});
        } else if (action == "message") {
            const QString number = notification.value("body").toString().replace("From: ", "");
            if (m_router)
                m_router->navigateToDeepLink("messages", "conversation",
                                             QVariantMap{{"number", number}});
        }
        return;
    }

    if (appId == "messages") {
        if (action == "reply") {
            if (m_router)
                m_router->navigateToDeepLink("messages", "", {});
        } else if (action == "mark_read") {
            if (m_notifications)
                m_notifications->dismissNotification(id);
        }
    }
}

QVariantMap NotificationHandlerCpp::findNotification(int id) const {
    if (!m_notifications)
        return {};

    return m_notifications->getNotification(id);
}

void NotificationHandlerCpp::navigateToNotificationTarget(const QVariantMap &notification) {
    if (!m_router)
        return;

    const QString appId  = notification.value("appId").toString();
    const QString idText = notification.value("id").toString();
    if (appId == "phone") {
        m_router->navigateToDeepLink(appId, "history", {});
        return;
    }

    if (appId == "messages") {
        if (idText.startsWith("sms_")) {
            const QStringList parts = idText.split("_");
            if (parts.size() >= 2) {
                m_router->navigateToDeepLink(appId, "conversation",
                                             QVariantMap{{"number", parts.at(1)}});
                return;
            }
        }
        m_router->navigateToDeepLink(appId, "", {});
        return;
    }

    m_router->navigateToDeepLink(appId, "", {});
}
