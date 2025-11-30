#include "notificationdatabase.h"
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>

NotificationDatabase::NotificationDatabase(QObject *parent)
    : QObject(parent) {
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataPath);
    m_dbPath = dataPath + "/notifications.db";
}

NotificationDatabase::~NotificationDatabase() {
    if (m_db.isOpen()) {
        m_db.close();
    }
}

bool NotificationDatabase::initialize() {
    m_db = QSqlDatabase::addDatabase("QSQLITE", "notifications");
    m_db.setDatabaseName(m_dbPath);

    if (!m_db.open()) {
        qWarning() << "[NotificationDB] Failed to open database:" << m_db.lastError().text();
        return false;
    }

    if (!createTables()) {
        qWarning() << "[NotificationDB] Failed to create tables";
        return false;
    }

    qInfo() << "[NotificationDB] ✓ Initialized at" << m_dbPath;
    return true;
}

bool NotificationDatabase::createTables() {
    QSqlQuery query(m_db);

    QString   createTable = R"(
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_id TEXT NOT NULL,
            title TEXT,
            body TEXT,
            icon TEXT,
            timestamp INTEGER,
            read INTEGER DEFAULT 0,
            dismissed INTEGER DEFAULT 0,
            category TEXT,
            priority INTEGER,
            actions TEXT,
            metadata TEXT
        )
    )";

    if (!query.exec(createTable)) {
        qWarning() << "[NotificationDB] Create table error:" << query.lastError().text();
        return false;
    }

    query.exec("CREATE INDEX IF NOT EXISTS idx_app_id ON notifications(app_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_timestamp ON notifications(timestamp DESC)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_dismissed ON notifications(dismissed)");

    return true;
}

uint NotificationDatabase::saveNotification(const NotificationRecord &notif) {
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO notifications (app_id, title, body, icon, timestamp, read, dismissed, category, priority, actions, metadata)
        VALUES (:app_id, :title, :body, :icon, :timestamp, :read, :dismissed, :category, :priority, :actions, :metadata)
    )");

    query.bindValue(":app_id", notif.appId);
    query.bindValue(":title", notif.title);
    query.bindValue(":body", notif.body);
    query.bindValue(":icon", notif.iconPath);
    query.bindValue(":timestamp", notif.timestamp.toSecsSinceEpoch());
    query.bindValue(":read", notif.read ? 1 : 0);
    query.bindValue(":dismissed", notif.dismissed ? 1 : 0);
    query.bindValue(":category", notif.category);
    query.bindValue(":priority", notif.priority);

    QJsonDocument actionsDoc = QJsonDocument::fromVariant(notif.actions);
    query.bindValue(":actions", QString::fromUtf8(actionsDoc.toJson(QJsonDocument::Compact)));

    QJsonDocument metadataDoc = QJsonDocument::fromVariant(notif.metadata);
    query.bindValue(":metadata", QString::fromUtf8(metadataDoc.toJson(QJsonDocument::Compact)));

    if (!query.exec()) {
        qWarning() << "[NotificationDB] Insert error:" << query.lastError().text();
        return 0;
    }

    return query.lastInsertId().toUInt();
}

NotificationDatabase::NotificationRecord NotificationDatabase::recordFromQuery(QSqlQuery &query) {
    NotificationRecord record;
    record.id        = query.value("id").toUInt();
    record.appId     = query.value("app_id").toString();
    record.title     = query.value("title").toString();
    record.body      = query.value("body").toString();
    record.iconPath  = query.value("icon").toString();
    record.timestamp = QDateTime::fromSecsSinceEpoch(query.value("timestamp").toLongLong());
    record.read      = query.value("read").toInt() == 1;
    record.dismissed = query.value("dismissed").toInt() == 1;
    record.category  = query.value("category").toString();
    record.priority  = query.value("priority").toInt();

    QString       actionsJson = query.value("actions").toString();
    QJsonDocument actionsDoc  = QJsonDocument::fromJson(actionsJson.toUtf8());
    record.actions            = actionsDoc.array().toVariantList();

    QString       metadataJson = query.value("metadata").toString();
    QJsonDocument metadataDoc  = QJsonDocument::fromJson(metadataJson.toUtf8());
    record.metadata            = metadataDoc.object().toVariantMap();

    return record;
}

QList<NotificationDatabase::NotificationRecord>
NotificationDatabase::getNotifications(const QString &appId) {
    QList<NotificationRecord> records;
    QSqlQuery                 query(m_db);

    if (appId.isEmpty()) {
        query.prepare("SELECT * FROM notifications WHERE dismissed = 0 ORDER BY timestamp DESC");
    } else {
        query.prepare("SELECT * FROM notifications WHERE app_id = :app_id AND dismissed = 0 ORDER "
                      "BY timestamp DESC");
        query.bindValue(":app_id", appId);
    }

    if (!query.exec()) {
        qWarning() << "[NotificationDB] Query error:" << query.lastError().text();
        return records;
    }

    while (query.next()) {
        records.append(recordFromQuery(query));
    }

    return records;
}

QList<NotificationDatabase::NotificationRecord> NotificationDatabase::getUnreadNotifications() {
    QList<NotificationRecord> records;
    QSqlQuery                 query(m_db);

    query.prepare(
        "SELECT * FROM notifications WHERE read = 0 AND dismissed = 0 ORDER BY timestamp DESC");

    if (!query.exec()) {
        qWarning() << "[NotificationDB] Query error:" << query.lastError().text();
        return records;
    }

    while (query.next()) {
        records.append(recordFromQuery(query));
    }

    return records;
}

bool NotificationDatabase::markAsRead(uint id) {
    QSqlQuery query(m_db);
    query.prepare("UPDATE notifications SET read = 1 WHERE id = :id");
    query.bindValue(":id", id);

    if (!query.exec()) {
        qWarning() << "[NotificationDB] Update error:" << query.lastError().text();
        return false;
    }

    return true;
}

bool NotificationDatabase::dismiss(uint id) {
    QSqlQuery query(m_db);
    query.prepare("UPDATE notifications SET dismissed = 1 WHERE id = :id");
    query.bindValue(":id", id);

    if (!query.exec()) {
        qWarning() << "[NotificationDB] Update error:" << query.lastError().text();
        return false;
    }

    return true;
}

bool NotificationDatabase::dismissAll() {
    QSqlQuery query(m_db);

    if (!query.exec("UPDATE notifications SET dismissed = 1 WHERE dismissed = 0")) {
        qWarning() << "[NotificationDB] Update error:" << query.lastError().text();
        return false;
    }

    return true;
}

bool NotificationDatabase::clearAll() {
    QSqlQuery query(m_db);

    if (!query.exec("DELETE FROM notifications")) {
        qWarning() << "[NotificationDB] Delete error:" << query.lastError().text();
        return false;
    }

    return true;
}

int NotificationDatabase::getUnreadCount() const {
    QSqlQuery query(m_db);
    query.prepare("SELECT COUNT(*) FROM notifications WHERE read = 0 AND dismissed = 0");

    if (!query.exec() || !query.next()) {
        return 0;
    }

    return query.value(0).toInt();
}
