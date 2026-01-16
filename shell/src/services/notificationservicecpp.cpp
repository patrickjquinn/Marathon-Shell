#include "notificationservicecpp.h"
#include "notificationmodel.h"
#include "settingsmanager.h"
#include "audiopolicycontroller.h"
#include "hapticmanager.h"

#include <QModelIndex>

NotificationServiceCpp::NotificationServiceCpp(NotificationModel *model, SettingsManager *settings,
                                               AudioPolicyController *audioPolicy,
                                               HapticManager *haptics, QObject *parent)
    : QObject(parent)
    , m_model(model)
    , m_settings(settings)
    , m_audioPolicy(audioPolicy)
    , m_haptics(haptics) {
    if (m_model) {
        const int count = m_model->rowCount();
        m_notifications.reserve(count);
        for (int row = 0; row < count; ++row) {
            const QModelIndex index = m_model->index(row, 0);
            QVariantMap       map;
            map.insert("id", m_model->data(index, NotificationModel::IdRole));
            map.insert("appId", m_model->data(index, NotificationModel::AppIdRole));
            map.insert("title", m_model->data(index, NotificationModel::TitleRole));
            map.insert("body", m_model->data(index, NotificationModel::BodyRole));
            map.insert("icon", m_model->data(index, NotificationModel::IconRole));
            map.insert("timestamp", m_model->data(index, NotificationModel::TimestampRole));
            map.insert("read", m_model->data(index, NotificationModel::IsReadRole));
            map.insert("category", "message");
            map.insert("priority", "normal");
            map.insert("actions", QVariantList());
            map.insert("persistent", false);
            m_notifications.append(map);
        }
        if (!m_notifications.isEmpty())
            emit notificationsChanged();
        connect(m_model, &NotificationModel::notificationAdded, this,
                &NotificationServiceCpp::onNotificationAdded);
        connect(m_model, &NotificationModel::notificationDismissed, this,
                &NotificationServiceCpp::onNotificationDismissed);
        connect(m_model, &NotificationModel::unreadCountChanged, this,
                &NotificationServiceCpp::onUnreadCountChanged);
    }
    if (m_settings) {
        connect(m_settings, &SettingsManager::dndEnabledChanged, this,
                &NotificationServiceCpp::onDndChanged);
    }
}

int NotificationServiceCpp::unreadCount() const {
    return m_model ? m_model->unreadCount() : 0;
}

bool NotificationServiceCpp::isDndEnabled() const {
    return m_settings ? m_settings->dndEnabled() : false;
}

int NotificationServiceCpp::sendNotification(const QString &appId, const QString &title,
                                             const QString &body, const QVariantMap &options) {
    if (!m_notificationsEnabled || !m_model)
        return -1;

    const QString resolvedAppId = appId.isEmpty() ? QStringLiteral("system") : appId;
    const QString icon          = options.value("icon").toString();
    const int     id            = m_model->addNotification(resolvedAppId, title, body, icon);

    QVariantMap   meta;
    meta.insert("icon", icon);
    meta.insert("category", options.value("category", "message"));
    meta.insert("priority", options.value("priority", "normal"));
    meta.insert("actions", options.value("actions", QVariantList()));
    meta.insert("persistent", options.value("persistent", false));
    m_notificationMeta.insert(id, meta);

    return id;
}

void NotificationServiceCpp::dismissNotification(int id) {
    if (!m_model)
        return;

    m_model->dismissNotification(id);
}

void NotificationServiceCpp::dismissAllNotifications() {
    if (!m_model)
        return;

    m_model->dismissAllNotifications();
    m_notifications.clear();
    m_notificationMeta.clear();
    emit notificationsChanged();
    emit unreadCountChanged();
}

void NotificationServiceCpp::markAsRead(int id) {
    if (!m_model)
        return;

    m_model->markAsRead(id);
    for (int i = 0; i < m_notifications.size(); ++i) {
        QVariantMap map = m_notifications[i].toMap();
        if (map.value("id").toInt() == id) {
            map["read"]        = true;
            m_notifications[i] = map;
            emit notificationsChanged();
            break;
        }
    }
}

void NotificationServiceCpp::markAllAsRead() {
    if (!m_model)
        return;

    for (const QVariant &item : m_notifications) {
        const QVariantMap map = item.toMap();
        if (!map.value("read").toBool())
            m_model->markAsRead(map.value("id").toInt());
    }

    for (int i = 0; i < m_notifications.size(); ++i) {
        QVariantMap map    = m_notifications[i].toMap();
        map["read"]        = true;
        m_notifications[i] = map;
    }
    emit notificationsChanged();
    emit unreadCountChanged();
}

void NotificationServiceCpp::clearAll() {
    QList<int> ids;
    ids.reserve(m_notifications.size());
    for (const QVariant &item : m_notifications)
        ids.append(item.toMap().value("id").toInt());

    for (int id : ids)
        dismissNotification(id);
}

void NotificationServiceCpp::clickNotification(int id) {
    markAsRead(id);
    emit notificationClicked(id);
}

void NotificationServiceCpp::triggerAction(int id, const QString &action) {
    emit notificationActionTriggered(id, action);
}

QVariantMap NotificationServiceCpp::getNotification(int id) const {
    for (const QVariant &item : m_notifications) {
        const QVariantMap map = item.toMap();
        if (map.value("id").toInt() == id)
            return map;
    }
    return {};
}

QVariantList NotificationServiceCpp::getNotificationsByApp(const QString &appId) const {
    QVariantList out;
    for (const QVariant &item : m_notifications) {
        const QVariantMap map = item.toMap();
        if (map.value("appId").toString() == appId)
            out.append(map);
    }
    return out;
}

QVariantList NotificationServiceCpp::getUnreadNotifications() const {
    QVariantList out;
    for (const QVariant &item : m_notifications) {
        const QVariantMap map = item.toMap();
        if (!map.value("read").toBool())
            out.append(map);
    }
    return out;
}

int NotificationServiceCpp::getNotificationCountForApp(const QString &appId) const {
    int count = 0;
    for (const QVariant &item : m_notifications) {
        const QVariantMap map = item.toMap();
        if (map.value("appId").toString() == appId && !map.value("read").toBool())
            count++;
    }
    return count;
}

void NotificationServiceCpp::setNotificationsEnabled(bool enabled) {
    if (m_notificationsEnabled == enabled)
        return;
    m_notificationsEnabled = enabled;
    emit notificationsEnabledChanged();
}

void NotificationServiceCpp::setSoundEnabled(bool enabled) {
    if (m_soundEnabled == enabled)
        return;
    m_soundEnabled = enabled;
    emit soundEnabledChanged();
}

void NotificationServiceCpp::setVibrationEnabled(bool enabled) {
    if (m_vibrationEnabled == enabled)
        return;
    m_vibrationEnabled = enabled;
    emit vibrationEnabledChanged();
}

void NotificationServiceCpp::setLedEnabled(bool enabled) {
    if (m_ledEnabled == enabled)
        return;
    m_ledEnabled = enabled;
    emit ledEnabledChanged();
}

void NotificationServiceCpp::onNotificationAdded(int id) {
    if (!m_model)
        return;

    Notification *notif = m_model->getNotification(id);
    if (!notif)
        return;

    QVariantMap map = buildNotificationMapFromModel(notif);
    m_notifications.append(map);
    emit notificationsChanged();
    emit notificationReceived(map);
    playFeedbackIfNeeded();
}

void NotificationServiceCpp::onNotificationDismissed(int id) {
    removeNotificationById(id);
    emit notificationDismissed(id);
}

void NotificationServiceCpp::onUnreadCountChanged() {
    emit unreadCountChanged();
}

void NotificationServiceCpp::onDndChanged() {
    emit isDndEnabledChanged();
}

QVariantMap
NotificationServiceCpp::buildNotificationMapFromModel(Notification *notification) const {
    QVariantMap map;
    map.insert("id", notification->id());
    map.insert("appId", notification->appId());
    map.insert("title", notification->title());
    map.insert("body", notification->body());
    map.insert("icon", notification->icon());
    map.insert("timestamp", notification->timestamp());
    map.insert("read", notification->isRead());

    const QVariantMap meta = m_notificationMeta.value(notification->id());
    if (!meta.isEmpty()) {
        map.insert("category", meta.value("category"));
        map.insert("priority", meta.value("priority"));
        map.insert("actions", meta.value("actions"));
        map.insert("persistent", meta.value("persistent"));
    } else {
        map.insert("category", "message");
        map.insert("priority", "normal");
        map.insert("actions", QVariantList());
        map.insert("persistent", false);
    }
    return map;
}

void NotificationServiceCpp::playFeedbackIfNeeded() {
    if (isDndEnabled())
        return;

    if (m_soundEnabled && m_audioPolicy)
        m_audioPolicy->playNotificationSound();

    if (m_vibrationEnabled && m_haptics)
        m_haptics->pattern({50, 100, 50});
}

void NotificationServiceCpp::removeNotificationById(int id) {
    for (int i = 0; i < m_notifications.size(); ++i) {
        const QVariantMap map = m_notifications[i].toMap();
        if (map.value("id").toInt() == id) {
            m_notifications.removeAt(i);
            emit notificationsChanged();
            break;
        }
    }
    m_notificationMeta.remove(id);
}
