#include "callhistorymanager.h"
#include "contactsmanager.h"
#include <QStandardPaths>
#include <QSqlQuery>
#include <QSqlError>
#include <QDir>
#include <QDebug>
#include <QVariant>

CallHistoryManager::CallHistoryManager(QObject *parent)
    : QObject(parent)
    , m_contactsManager(nullptr) {
    initDatabase();
    loadHistory();
    qDebug() << "[CallHistoryManager] Initialized with" << m_history.size() << "calls";
}

CallHistoryManager::~CallHistoryManager() {
    if (m_database.isOpen()) {
        m_database.close();
    }
}

void CallHistoryManager::setContactsManager(ContactsManager *contactsManager) {
    m_contactsManager = contactsManager;
    // Reload history to resolve contact names
    loadHistory();
}

QVariantList CallHistoryManager::history() const {
    QVariantList list;
    for (const CallRecord &record : m_history) {
        QVariantMap map;
        map["id"]          = record.id;
        map["number"]      = record.number;
        map["contactName"] = record.contactName;
        map["type"]        = record.type;
        map["timestamp"]   = record.timestamp;
        map["duration"]    = record.duration;
        list.append(map);
    }
    return list;
}

int CallHistoryManager::count() const {
    return m_history.size();
}

void CallHistoryManager::addCall(const QString &number, const QString &type, qint64 timestamp,
                                 int duration) {
    if (number.isEmpty()) {
        qWarning() << "[CallHistoryManager] Cannot add call with empty number";
        return;
    }

    CallRecord record;
    record.number      = number;
    record.contactName = resolveContactName(number);
    record.type        = type;
    record.timestamp   = timestamp;
    record.duration    = duration;

    saveCall(record);

    // Reload to get the ID
    loadHistory();

    qDebug() << "[CallHistoryManager] Added call:" << type << number << duration << "seconds";
}

void CallHistoryManager::deleteCall(int id) {
    QSqlQuery query(m_database);
    query.prepare("DELETE FROM call_history WHERE id = ?");
    query.addBindValue(id);

    if (query.exec()) {
        loadHistory();
        qDebug() << "[CallHistoryManager] Deleted call with ID:" << id;
    } else {
        qWarning() << "[CallHistoryManager] Failed to delete call:" << query.lastError().text();
    }
}

void CallHistoryManager::clearHistory() {
    QSqlQuery query(m_database);
    if (query.exec("DELETE FROM call_history")) {
        m_history.clear();
        emit historyChanged();
        qDebug() << "[CallHistoryManager] History cleared";
    } else {
        qWarning() << "[CallHistoryManager] Failed to clear history:" << query.lastError().text();
    }
}

QVariantMap CallHistoryManager::getCallById(int id) {
    for (const CallRecord &record : m_history) {
        if (record.id == id) {
            QVariantMap map;
            map["id"]          = record.id;
            map["number"]      = record.number;
            map["contactName"] = record.contactName;
            map["type"]        = record.type;
            map["timestamp"]   = record.timestamp;
            map["duration"]    = record.duration;
            return map;
        }
    }
    return QVariantMap();
}

QVariantList CallHistoryManager::getCallsByNumber(const QString &number) {
    QVariantList list;
    for (const CallRecord &record : m_history) {
        if (record.number == number) {
            QVariantMap map;
            map["id"]          = record.id;
            map["number"]      = record.number;
            map["contactName"] = record.contactName;
            map["type"]        = record.type;
            map["timestamp"]   = record.timestamp;
            map["duration"]    = record.duration;
            list.append(map);
        }
    }
    return list;
}

void CallHistoryManager::initDatabase() {
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString dbPath  = dataDir + "/marathon";

    QDir    dir;
    if (!dir.exists(dbPath)) {
        dir.mkpath(dbPath);
    }

    m_database = QSqlDatabase::addDatabase("QSQLITE", "callhistory");
    m_database.setDatabaseName(dbPath + "/callhistory.db");

    if (!m_database.open()) {
        qWarning() << "[CallHistoryManager] Failed to open database:"
                   << m_database.lastError().text();
        return;
    }

    // Create table if it doesn't exist
    QSqlQuery query(m_database);
    bool      success = query.exec("CREATE TABLE IF NOT EXISTS call_history ("
                                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                        "number TEXT NOT NULL, "
                                        "contact_name TEXT, "
                                        "type TEXT NOT NULL, "
                                        "timestamp INTEGER NOT NULL, "
                                        "duration INTEGER DEFAULT 0)");

    if (!success) {
        qWarning() << "[CallHistoryManager] Failed to create table:" << query.lastError().text();
    }

    qDebug() << "[CallHistoryManager] Database initialized at" << dbPath;
}

void CallHistoryManager::loadHistory() {
    m_history.clear();

    QSqlQuery query(m_database);
    query.prepare("SELECT id, number, contact_name, type, timestamp, duration FROM call_history "
                  "ORDER BY timestamp DESC LIMIT ?");
    query.addBindValue(MAX_HISTORY_SIZE);

    if (query.exec()) {
        while (query.next()) {
            CallRecord record;
            record.id          = query.value(0).toInt();
            record.number      = query.value(1).toString();
            record.contactName = query.value(2).toString();
            record.type        = query.value(3).toString();
            record.timestamp   = query.value(4).toLongLong();
            record.duration    = query.value(5).toInt();

            m_history.append(record);
        }
    } else {
        qWarning() << "[CallHistoryManager] Failed to load history:" << query.lastError().text();
    }

    emit historyChanged();
}

void CallHistoryManager::saveCall(const CallRecord &record) {
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO call_history (number, contact_name, type, timestamp, duration) "
                  "VALUES (?, ?, ?, ?, ?)");
    query.addBindValue(record.number);
    query.addBindValue(record.contactName);
    query.addBindValue(record.type);
    query.addBindValue(record.timestamp);
    query.addBindValue(record.duration);

    if (!query.exec()) {
        qWarning() << "[CallHistoryManager] Failed to save call:" << query.lastError().text();
    }

    // Clean up old records if exceeding limit
    QSqlQuery countQuery(m_database);
    if (countQuery.exec("SELECT COUNT(*) FROM call_history")) {
        if (countQuery.next() && countQuery.value(0).toInt() > MAX_HISTORY_SIZE) {
            QSqlQuery deleteQuery(m_database);
            deleteQuery.exec(
                QString("DELETE FROM call_history WHERE id NOT IN "
                        "(SELECT id FROM call_history ORDER BY timestamp DESC LIMIT %1)")
                    .arg(MAX_HISTORY_SIZE));
        }
    }
}

QString CallHistoryManager::resolveContactName(const QString &number) {
    if (!m_contactsManager) {
        return "Unknown";
    }

    // Search contacts by phone number
    QVariantList results = m_contactsManager->searchContacts(number);
    if (!results.isEmpty()) {
        QVariantMap contact = results.first().toMap();
        QString     name    = contact.value("name").toString();
        if (!name.isEmpty()) {
            return name;
        }
    }

    return "Unknown";
}
