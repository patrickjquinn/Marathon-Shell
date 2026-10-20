#include "notificationhandlercpp.h"

#include "marathonappregistry.h"
#include "navigationroutercpp.h"
#include "notificationservicecpp.h"
#include "notificationtarget.h"
#include "marathon-shell-native/src/modem.cxxqt.h"

#include <algorithm>
#include <QDebug>

NotificationHandlerCpp::NotificationHandlerCpp(NotificationServiceCpp *notifications,
                                               NavigationRouterCpp    *router,
                                               Modem       *telephony,
                                               MarathonAppRegistry *registry, QObject *parent)
    : QObject(parent)
    , m_notifications(notifications)
    , m_router(router)
    , m_telephony(telephony)
    , m_registry(registry) {}

void NotificationHandlerCpp::handleNotificationClick(int id) {
    const QVariantMap notification = findNotification(id);
    if (notification.isEmpty())
        return;

    navigateToNotificationTarget(notification);
    if (m_notifications && !notification.value("ongoing").toBool())
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
        if (action == "inline-reply") {
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
    const QString appId  = notification.value("appId").toString();
    const QString idText = notification.value("id").toString();
    if (m_router && appId == "phone") {
        m_router->navigateToDeepLink(appId, "history", {});
        return;
    }

    if (m_router && appId == "messages") {
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

    // Rows stored before the server resolved apps still carry app_name.
    const QString installed = NotificationTarget::resolve({appId}, m_registry);
    if (!installed.isEmpty() && m_router) {
        m_router->navigateToDeepLink(installed, "", {});
        return;
    }
    // An Android app, or a desktop app, the registry does not hold.
    const auto actions     = notification.value("actions").toList();
    const bool opensItself = std::any_of(actions.cbegin(), actions.cend(), [](const QVariant &a) {
        return a.toMap().value("key").toString() == QLatin1String("default");
    });
    if (!m_showApp || !m_showApp(appId, opensItself))
        qWarning() << "[NotificationHandler] No app to show for notification from" << appId;
}
