#include "smsservice.h"
#include <QStandardPaths>
#include <QSqlQuery>
#include <QSqlError>
#include <QDir>
#include <QDebug>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusReply>

SMSService::SMSService(QObject *parent)
    : QObject(parent)
    , m_modemManager(nullptr)
    , m_pollTimer(new QTimer(this))
{
    initDatabase();
    loadConversations();
    
#ifdef Q_OS_MACOS
    m_stubMode = true;
    qDebug() << "[SMSService] Running in STUB mode (macOS)";
#else
    connectToModemManager();
    
    // Poll for new messages every 10 seconds
    m_pollTimer->setInterval(10000);
    connect(m_pollTimer, &QTimer::timeout, this, &SMSService::checkForNewMessages);
    m_pollTimer->start();
#endif
    
    qDebug() << "[SMSService] Initialized with" << m_conversations.size() << "conversations";
}

SMSService::~SMSService()
{
    if (m_database.isOpen()) {
        m_database.close();
    }
    if (m_modemManager) {
        delete m_modemManager;
    }
}

QVariantList SMSService::conversations() const
{
    QVariantList list;
    for (const Conversation& conv : m_conversations) {
        QVariantMap map;
        map["id"] = conv.id;
        map["contactName"] = conv.contactNumber; // TODO: Resolve contact name
        map["lastMessage"] = conv.lastMessage;
        map["timestamp"] = conv.lastTimestamp;
        map["unread"] = conv.unreadCount;
        list.append(map);
    }
    return list;
}

void SMSService::sendMessage(const QString& recipient, const QString& text)
{
    if (recipient.isEmpty() || text.isEmpty()) {
        qWarning() << "[SMSService] Cannot send empty message";
        return;
    }
    
    qDebug() << "[SMSService] Sending message to" << recipient;
    
#ifdef Q_OS_MACOS
    handleStubSend(recipient, text);
#else
    if (!m_modemManager || !m_modemManager->isValid()) {
        emit sendFailed(recipient, "ModemManager not available");
        return;
    }
    
    // Send SMS via ModemManager D-Bus
    QDBusReply<QDBusObjectPath> reply = m_modemManager->call("Create", QVariantMap{
        {"number", recipient},
        {"text", text}
    });
    
    if (reply.isValid()) {
        QString messagePath = reply.value().path();
        
        // Send the message
        QDBusInterface msgInterface(
            "org.freedesktop.ModemManager1",
            messagePath,
            "org.freedesktop.ModemManager1.Sms",
            QDBusConnection::systemBus()
        );
        
        QDBusReply<void> sendReply = msgInterface.call("Send");
        if (sendReply.isValid()) {
            // Store in database
            Message msg;
            msg.conversationId = generateConversationId(recipient);
            msg.sender = "";
            msg.recipient = recipient;
            msg.text = text;
            msg.timestamp = QDateTime::currentMSecsSinceEpoch();
            msg.isRead = true;
            msg.isOutgoing = true;
            
            storeMessage(msg);
            loadConversations();
            
            emit messageSent(recipient, msg.timestamp);
        } else {
            emit sendFailed(recipient, sendReply.error().message());
        }
    } else {
        emit sendFailed(recipient, reply.error().message());
    }
#endif
}

QVariantList SMSService::getMessages(const QString& conversationId)
{
    QVariantList list;
    
    QSqlQuery query(m_database);
    query.prepare("SELECT id, sender, recipient, text, timestamp, is_read, is_outgoing FROM messages WHERE conversation_id = ? ORDER BY timestamp ASC");
    query.addBindValue(conversationId);
    
    if (query.exec()) {
        while (query.next()) {
            QVariantMap map;
            map["id"] = query.value(0).toInt();
            map["sender"] = query.value(1).toString();
            map["recipient"] = query.value(2).toString();
            map["text"] = query.value(3).toString();
            map["timestamp"] = query.value(4).toLongLong();
            map["isRead"] = query.value(5).toBool();
            map["isOutgoing"] = query.value(6).toBool();
            list.append(map);
        }
    }
    
    return list;
}

void SMSService::deleteConversation(const QString& conversationId)
{
    QSqlQuery query(m_database);
    query.prepare("DELETE FROM messages WHERE conversation_id = ?");
    query.addBindValue(conversationId);
    
    if (query.exec()) {
        loadConversations();
        qDebug() << "[SMSService] Deleted conversation:" << conversationId;
    }
}

void SMSService::markAsRead(const QString& conversationId)
{
    QSqlQuery query(m_database);
    query.prepare("UPDATE messages SET is_read = 1 WHERE conversation_id = ?");
    query.addBindValue(conversationId);
    
    if (query.exec()) {
        loadConversations();
    }
}

void SMSService::initDatabase()
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString dbPath = dataDir + "/marathon";
    
    QDir dir;
    if (!dir.exists(dbPath)) {
        dir.mkpath(dbPath);
    }
    
    m_database = QSqlDatabase::addDatabase("QSQLITE", "messages");
    m_database.setDatabaseName(dbPath + "/messages.db");
    
    if (!m_database.open()) {
        qWarning() << "[SMSService] Failed to open database:" << m_database.lastError().text();
        return;
    }
    
    QSqlQuery query(m_database);
    bool success = query.exec(
        "CREATE TABLE IF NOT EXISTS messages ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "conversation_id TEXT NOT NULL, "
        "sender TEXT, "
        "recipient TEXT, "
        "text TEXT NOT NULL, "
        "timestamp INTEGER NOT NULL, "
        "is_read INTEGER DEFAULT 0, "
        "is_outgoing INTEGER DEFAULT 0)"
    );
    
    if (!success) {
        qWarning() << "[SMSService] Failed to create table:" << query.lastError().text();
    }
}

void SMSService::loadConversations()
{
    m_conversations.clear();
    
    QSqlQuery query(m_database);
    query.exec(
        "SELECT conversation_id, "
        "MAX(CASE WHEN is_outgoing = 1 THEN recipient ELSE sender END) as contact_number, "
        "text as last_message, "
        "MAX(timestamp) as last_timestamp, "
        "SUM(CASE WHEN is_read = 0 AND is_outgoing = 0 THEN 1 ELSE 0 END) as unread_count "
        "FROM messages "
        "GROUP BY conversation_id "
        "ORDER BY last_timestamp DESC"
    );
    
    while (query.next()) {
        Conversation conv;
        conv.id = query.value(0).toString();
        conv.contactNumber = query.value(1).toString();
        conv.lastMessage = query.value(2).toString();
        conv.lastTimestamp = query.value(3).toLongLong();
        conv.unreadCount = query.value(4).toInt();
        
        m_conversations.append(conv);
    }
    
    emit conversationsChanged();
}

void SMSService::storeMessage(const Message& msg)
{
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO messages (conversation_id, sender, recipient, text, timestamp, is_read, is_outgoing) VALUES (?, ?, ?, ?, ?, ?, ?)");
    query.addBindValue(msg.conversationId);
    query.addBindValue(msg.sender);
    query.addBindValue(msg.recipient);
    query.addBindValue(msg.text);
    query.addBindValue(msg.timestamp);
    query.addBindValue(msg.isRead ? 1 : 0);
    query.addBindValue(msg.isOutgoing ? 1 : 0);
    
    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to store message:" << query.lastError().text();
    }
}

void SMSService::connectToModemManager()
{
#ifndef Q_OS_MACOS
    m_modemManager = new QDBusInterface(
        "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1/Modem/0",
        "org.freedesktop.ModemManager1.Modem.Messaging",
        QDBusConnection::systemBus(),
        this
    );
    
    if (!m_modemManager->isValid()) {
        qWarning() << "[SMSService] ModemManager messaging not available";
    }
#endif
}

void SMSService::checkForNewMessages()
{
#ifndef Q_OS_MACOS
    // Poll ModemManager for new messages
    // This is a simplified implementation
#endif
}

QString SMSService::generateConversationId(const QString& number)
{
    // Simple conversation ID based on phone number
    QString sanitized = number;
    sanitized.replace("+", "").replace(" ", "").replace("-", "");
    return "conv_" + sanitized;
}

#ifdef Q_OS_MACOS
void SMSService::handleStubSend(const QString& recipient, const QString& text)
{
    qDebug() << "[SMSService] STUB: Would send to" << recipient << ":" << text;
    
    Message msg;
    msg.conversationId = generateConversationId(recipient);
    msg.sender = "";
    msg.recipient = recipient;
    msg.text = text;
    msg.timestamp = QDateTime::currentMSecsSinceEpoch();
    msg.isRead = true;
    msg.isOutgoing = true;
    
    storeMessage(msg);
    loadConversations();
    
    emit messageSent(recipient, msg.timestamp);
}
#endif

