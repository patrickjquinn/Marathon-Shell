#include "notificationmodel.h"
#include "dbus/notificationdatabase.h"
#include <QDebug>

NotificationModel::NotificationModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_nextId(1)
    , m_unreadCount(0) {
    qDebug() << "[NotificationModel] Initialized";
}

NotificationModel::~NotificationModel() {
    qDeleteAll(m_notifications);
}

int NotificationModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid())
        return 0;
    return m_notifications.count();
}

QVariant NotificationModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_notifications.count())
        return QVariant();

    Notification *notification = m_notifications.at(index.row());

    switch (role) {
        case IdRole: return notification->id();
        case AppIdRole: return notification->appId();
        case TitleRole: return notification->title();
        case BodyRole: return notification->body();
        case IconRole: return notification->icon();
        case TimestampRole: return notification->timestamp();
        case IsReadRole: return notification->isRead();
        default: return QVariant();
    }
}

QHash<int, QByteArray> NotificationModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole]        = "id";
    roles[AppIdRole]     = "appId";
    roles[TitleRole]     = "title";
    roles[BodyRole]      = "body";
    roles[IconRole]      = "icon";
    roles[TimestampRole] = "timestamp";
    roles[IsReadRole]    = "isRead";
    return roles;
}

int NotificationModel::addNotification(const QString &appId, const QString &title,
                                       const QString &body, const QString &icon) {
    int id = m_nextId++;

    beginInsertRows(QModelIndex(), 0, 0); // Insert at top
    Notification *notification = new Notification(id, appId, title, body, icon, this);
    m_notifications.prepend(notification);
    m_notificationIndex[id] = notification;
    endInsertRows();

    updateUnreadCount();
    emit countChanged();
    emit notificationAdded(id);

    qDebug() << "[NotificationModel] Added notification:" << title << "from" << appId;
    return id;
}

void NotificationModel::dismissNotification(int id) {
    Notification *notification = m_notificationIndex.value(id, nullptr);
    if (!notification) {
        qDebug() << "[NotificationModel] Notification not found:" << id;
        return;
    }

    int index = m_notifications.indexOf(notification);
    if (index >= 0) {
        beginRemoveRows(QModelIndex(), index, index);
        m_notifications.remove(index);
        m_notificationIndex.remove(id);
        endRemoveRows();

        updateUnreadCount();
        emit countChanged();
        emit notificationDismissed(id);

        qDebug() << "[NotificationModel] Dismissed notification:" << id;
        delete notification;
    }
}

void NotificationModel::markAsRead(int id) {
    Notification *notification = m_notificationIndex.value(id, nullptr);
    if (!notification) {
        qDebug() << "[NotificationModel] Notification not found:" << id;
        return;
    }

    if (!notification->isRead()) {
        notification->setIsRead(true);
        int index = m_notifications.indexOf(notification);
        if (index >= 0) {
            QModelIndex modelIndex = createIndex(index, 0);
            emit        dataChanged(modelIndex, modelIndex, {IsReadRole});
        }
        updateUnreadCount();
        qDebug() << "[NotificationModel] Marked as read:" << id;
    }
}

void NotificationModel::dismissAllNotifications() {
    if (m_notifications.isEmpty())
        return;

    beginResetModel();
    qDeleteAll(m_notifications);
    m_notifications.clear();
    m_notificationIndex.clear();
    endResetModel();

    updateUnreadCount();
    emit countChanged();
    qDebug() << "[NotificationModel] Dismissed all notifications";
}

Notification *NotificationModel::getNotification(int id) {
    return m_notificationIndex.value(id, nullptr);
}

void NotificationModel::updateUnreadCount() {
    int count = 0;
    for (Notification *notification : m_notifications) {
        if (!notification->isRead()) {
            count++;
        }
    }

    if (m_unreadCount != count) {
        m_unreadCount = count;
        emit unreadCountChanged();
    }
}

void NotificationModel::loadFromDatabase(NotificationDatabase *database) {
    if (!database) {
        qWarning() << "[NotificationModel] Cannot load from null database";
        return;
    }

    qDebug() << "[NotificationModel] Loading notifications from database...";

    QList<NotificationDatabase::NotificationRecord> records = database->getNotifications();

    if (records.isEmpty()) {
        qDebug() << "[NotificationModel] No notifications in database";
        return;
    }

    beginResetModel();

    qDeleteAll(m_notifications);
    m_notifications.clear();
    m_notificationIndex.clear();

    for (const auto &record : records) {
        Notification *notification = new Notification(record.id, record.appId, record.title,
                                                      record.body, record.iconPath, this);
        notification->setIsRead(record.read);

        m_notifications.append(notification);
        m_notificationIndex[record.id] = notification;

        if (record.id >= m_nextId) {
            m_nextId = record.id + 1;
        }
    }

    endResetModel();

    updateUnreadCount();
    emit countChanged();

    qInfo() << "[NotificationModel] Loaded" << m_notifications.count()
            << "notifications from database";
}
