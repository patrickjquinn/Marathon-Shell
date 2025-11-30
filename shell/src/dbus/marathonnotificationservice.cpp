#include "marathonnotificationservice.h"
#include "notificationdatabase.h"
#include "../notificationmodel.h"
#include <QDBusConnection>
#include <QDateTime>
#include <QDebug>

MarathonNotificationService::MarathonNotificationService(NotificationDatabase *database,
                                                         NotificationModel *model, QObject *parent)
    : QObject(parent)
    , m_database(database)
    , m_model(model) {}

MarathonNotificationService::~MarathonNotificationService() {}

bool MarathonNotificationService::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.marathon.NotificationService")) {
        qWarning() << "[NotificationService] Failed to register service:"
                   << bus.lastError().message();
        return false;
    }

    if (!bus.registerObject("/org/marathon/NotificationService", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qWarning() << "[NotificationService] Failed to register object:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[NotificationService] ✓ Registered on D-Bus";
    return true;
}

uint MarathonNotificationService::Notify(const QString &appId, const QString &title,
                                         const QString &body, const QVariantMap &options) {
    qInfo() << "[NotificationService] Notify:" << appId << title;

    NotificationDatabase::NotificationRecord record;
    record.appId     = appId;
    record.title     = title;
    record.body      = body;
    record.iconPath  = options.value("icon", "").toString();
    record.timestamp = QDateTime::currentDateTime();
    record.read      = false;
    record.dismissed = false;
    record.category  = options.value("category", "general").toString();
    record.priority  = options.value("priority", 0).toInt();
    record.actions   = options.value("actions", QVariantList()).toList();
    record.metadata  = options.value("metadata", QVariantMap()).toMap();

    uint id = m_database->saveNotification(record);

    if (id > 0) {
        if (m_model) {
            m_model->addNotification(appId, title, body, record.iconPath);
        }
        emit NotificationReceived(id, appId, title, body);
    }

    return id;
}

QVariantMap MarathonNotificationService::notificationToVariantMap(
    const NotificationDatabase::NotificationRecord &record) {
    QVariantMap map;
    map["id"]        = record.id;
    map["appId"]     = record.appId;
    map["title"]     = record.title;
    map["body"]      = record.body;
    map["icon"]      = record.iconPath;
    map["timestamp"] = record.timestamp.toSecsSinceEpoch();
    map["read"]      = record.read;
    map["dismissed"] = record.dismissed;
    map["category"]  = record.category;
    map["priority"]  = record.priority;
    map["actions"]   = record.actions;
    map["metadata"]  = record.metadata;
    return map;
}

QVariantList MarathonNotificationService::GetNotifications(const QString &appId) {
    QVariantList                                    result;
    QList<NotificationDatabase::NotificationRecord> records = m_database->getNotifications(appId);

    for (const auto &record : records) {
        result.append(notificationToVariantMap(record));
    }

    return result;
}

QVariantList MarathonNotificationService::GetUnreadNotifications() {
    QVariantList                                    result;
    QList<NotificationDatabase::NotificationRecord> records = m_database->getUnreadNotifications();

    for (const auto &record : records) {
        result.append(notificationToVariantMap(record));
    }

    return result;
}

bool MarathonNotificationService::CloseNotification(uint id) {
    qInfo() << "[NotificationService] CloseNotification:" << id;

    bool success = m_database->dismiss(id);
    if (success) {
        emit NotificationClosed(id);
    }

    return success;
}

bool MarathonNotificationService::CloseAllNotifications() {
    qInfo() << "[NotificationService] CloseAllNotifications";

    bool success = m_database->dismissAll();
    if (success) {
        emit AllNotificationsCleared();
    }

    return success;
}

bool MarathonNotificationService::MarkAsRead(uint id) {
    return m_database->markAsRead(id);
}

int MarathonNotificationService::GetUnreadCount() {
    return m_database->getUnreadCount();
}

void MarathonNotificationService::InvokeAction(uint notificationId, const QString &actionId) {
    qInfo() << "[NotificationService] InvokeAction:" << notificationId << actionId;
    emit ActionInvoked(notificationId, actionId);
}
