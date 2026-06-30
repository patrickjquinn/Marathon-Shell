#include "smsservice.h"
#include "contactsmanager.h"
#include "mmsmanager.h"
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QDBusMetaType>
#include <QDebug>
#include <QSqlQuery>
#include <QTimer>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDateTime>

SMSService::SMSService(QObject *parent)
    : QObject(parent)
    , m_modemManager(nullptr)
    , m_pollTimer(new QTimer(this))
    , m_contactsManager(nullptr) {
    qDebug() << "[SMSService] Initializing";

    initDatabase();
    connectToModemManager();

    m_pollTimer->setInterval(5000);
    connect(m_pollTimer, &QTimer::timeout, this, &SMSService::checkForNewMessages);
    m_pollTimer->start();

    loadConversations();

    qInfo() << "[SMSService] Initialized with" << m_conversations.size() << "conversations";
}

SMSService::~SMSService() {
    if (m_database.isOpen()) {
        m_database.close();
    }
    // m_modemManager is parented to this; Qt will delete it
}

void SMSService::setContactsManager(ContactsManager *contactsManager) {
    m_contactsManager = contactsManager;
}

void SMSService::setMmsManager(MmsManager *mmsManager) {
    if (m_mmsManager == mmsManager)
        return;
    m_mmsManager = mmsManager;
    if (!m_mmsManager)
        return;
    // Surface incoming MMS through the same `messageReceived` signal apps
    // already listen to; the conversation thread merges SMS + MMS.
    connect(
        m_mmsManager, &MmsManager::messageReceived, this,
        [this](const QString &sender, const QString &text, qint64 timestamp, const QVariantList &) {
            Message msg;
            msg.conversationId = generateConversationId(sender);
            msg.sender         = sender;
            msg.recipient      = QStringLiteral("me");
            msg.text           = text;
            msg.timestamp      = timestamp;
            msg.isRead         = false;
            msg.isOutgoing     = false;
            storeMessage(msg);
            loadConversations();
            emit messageReceived(sender, text, timestamp);
        });
    connect(m_mmsManager, &MmsManager::sendFailed, this,
            [this](const QString &reason) { emit sendFailed(QString(), reason); });
}

QVariantList SMSService::conversations() const {
    QVariantList result;
    for (const Conversation &conv : m_conversations) {
        QVariantMap map;
        map["id"]            = conv.id;
        map["contactNumber"] = conv.contactNumber;
        map["contactName"]   = resolveContactName(conv.contactNumber);
        map["lastMessage"]   = conv.lastMessage;
        map["lastTimestamp"] = conv.lastTimestamp;
        map["unreadCount"]   = conv.unreadCount;
        result.append(map);
    }
    return result;
}

void SMSService::sendMultiRecipient(const QStringList &recipients, const QString &text,
                                    const QVariantList &attachments) {
    // Routing: single recipient + no attachments + plain text fitting SMS budget
    // -> normal SMS via ModemManager.Messaging. Otherwise -> MMS via mmsd-tng.
    // (Mirrors Chatty's routing in chatty-mm-chat.c.)
    const bool needsMms = recipients.size() > 1 || !attachments.isEmpty() || text.size() > 1530;
    if (!needsMms && !recipients.isEmpty()) {
        sendMessage(recipients.first(), text);
        return;
    }
    if (!m_mmsManager || !m_mmsManager->available()) {
        qWarning() << "[SMSService] MMS required but mmsd-tng unavailable; "
                      "falling back to per-recipient SMS";
        for (const QString &r : recipients)
            sendMessage(r, text);
        return;
    }
    if (!m_mmsManager->sendMms(recipients, text, attachments)) {
        // sendMms emits sendFailed itself; nothing else to do.
        return;
    }
    Message msg;
    msg.conversationId = generateConversationId(recipients.join(","));
    msg.sender         = QStringLiteral("me");
    msg.recipient      = recipients.join(",");
    msg.text           = text;
    msg.timestamp      = QDateTime::currentMSecsSinceEpoch();
    msg.isRead         = true;
    msg.isOutgoing     = true;
    storeMessage(msg);
    loadConversations();
    emit messageSent(recipients.join(","), msg.timestamp);
}

void SMSService::sendMessage(const QString &recipient, const QString &text) {
    if (recipient.isEmpty() || text.isEmpty()) {
        qWarning() << "[SMSService] Cannot send empty message";
        emit sendFailed(recipient, "Message text or recipient is empty");
        return;
    }

    qInfo() << "[SMSService] Sending SMS to:" << recipient;

    if (!m_modemManager || !m_modemManager->isValid()) {
        qWarning() << "[SMSService] ModemManager not available";

        Message msg;
        msg.conversationId = generateConversationId(recipient);
        msg.sender         = "me";
        msg.recipient      = recipient;
        msg.text           = text;
        msg.timestamp      = QDateTime::currentMSecsSinceEpoch();
        msg.isRead         = true;
        msg.isOutgoing     = true;

        storeMessage(msg);
        loadConversations();

        emit sendFailed(recipient, "No modem available");
        return;
    }

    QDBusReply<QVariantMap> reply = m_modemManager->call("GetManagedObjects");
    if (!reply.isValid()) {
        qWarning() << "[SMSService] Failed to get modems:" << reply.error().message();
        emit sendFailed(recipient, "Failed to access modem");
        return;
    }

    QVariantMap objects = reply.value();
    QString     modemPath;

    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        const QString &path       = it.key();
        QVariantMap    interfaces = qdbus_cast<QVariantMap>(it.value());

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem.Messaging")) {
            modemPath = path;
            break;
        }
    }

    if (modemPath.isEmpty()) {
        qWarning() << "[SMSService] No modem with Messaging capability found";
        emit sendFailed(recipient, "No SMS-capable modem available");
        return;
    }

    QVariantMap properties;
    properties["number"] = recipient;
    properties["text"]   = text;

    QDBusInterface messagingInterface("org.freedesktop.ModemManager1", modemPath,
                                      "org.freedesktop.ModemManager1.Modem.Messaging",
                                      QDBusConnection::systemBus());

    if (!messagingInterface.isValid()) {
        qWarning() << "[SMSService] Messaging interface not available:"
                   << messagingInterface.lastError().message();
        emit sendFailed(recipient, "Messaging interface not available");
        return;
    }

    QDBusReply<QDBusObjectPath> createReply =
        messagingInterface.call("Create", QVariant::fromValue(properties));
    if (!createReply.isValid()) {
        qWarning() << "[SMSService] Failed to create SMS:" << createReply.error().message();
        emit sendFailed(recipient, "Failed to create SMS: " + createReply.error().message());
        return;
    }

    QString smsPath = createReply.value().path();
    qDebug() << "[SMSService] SMS created:" << smsPath;

    QDBusInterface smsInterface("org.freedesktop.ModemManager1", smsPath,
                                "org.freedesktop.ModemManager1.Sms", QDBusConnection::systemBus());

    if (!smsInterface.isValid()) {
        qWarning() << "[SMSService] SMS interface not available";
        emit sendFailed(recipient, "SMS interface not available");
        return;
    }

    QDBusReply<void> sendReply = smsInterface.call("Send");
    if (!sendReply.isValid()) {
        qWarning() << "[SMSService] Failed to send SMS:" << sendReply.error().message();
        emit sendFailed(recipient, "Failed to send SMS: " + sendReply.error().message());
        return;
    }

    Message msg;
    msg.conversationId = generateConversationId(recipient);
    msg.sender         = "me";
    msg.recipient      = recipient;
    msg.text           = text;
    msg.timestamp      = QDateTime::currentMSecsSinceEpoch();
    msg.isRead         = true;
    msg.isOutgoing     = true;

    storeMessage(msg);
    loadConversations();

    emit messageSent(recipient, msg.timestamp);

    qInfo() << "[SMSService]SMS sent to:" << recipient;
}

QVariantList SMSService::getMessages(const QString &conversationId) {
    QVariantList result;

    QSqlQuery    query(m_database);
    query.prepare("SELECT * FROM messages WHERE conversationId = ? ORDER BY timestamp ASC");
    query.addBindValue(conversationId);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to get messages:" << query.lastError().text();
        return result;
    }

    while (query.next()) {
        QVariantMap msg;
        msg["id"]             = query.value("id").toInt();
        msg["conversationId"] = query.value("conversationId").toString();
        msg["sender"]         = query.value("sender").toString();
        msg["recipient"]      = query.value("recipient").toString();
        msg["text"]           = query.value("text").toString();
        msg["timestamp"]      = query.value("timestamp").toLongLong();
        msg["isRead"]         = query.value("isRead").toBool();
        msg["isOutgoing"]     = query.value("isOutgoing").toBool();
        result.append(msg);
    }

    return result;
}

void SMSService::deleteConversation(const QString &conversationId) {
    QSqlQuery query(m_database);
    query.prepare("DELETE FROM messages WHERE conversationId = ?");
    query.addBindValue(conversationId);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to delete conversation:" << query.lastError().text();
        return;
    }

    loadConversations();
    qInfo() << "[SMSService] Conversation deleted:" << conversationId;
}

void SMSService::markAsRead(const QString &conversationId) {
    QSqlQuery query(m_database);
    query.prepare("UPDATE messages SET isRead = 1 WHERE conversationId = ?");
    query.addBindValue(conversationId);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to mark as read:" << query.lastError().text();
        return;
    }

    loadConversations();
    qDebug() << "[SMSService] Marked as read:" << conversationId;
}

QString SMSService::generateConversationId(const QString &number) {

    QString normalized = number;
    normalized.remove(QRegularExpression("[^0-9+]"));
    return normalized;
}

void SMSService::simulateIncomingSMS(const QString &sender, const QString &text) {
    qInfo() << "[SMSService] [SIMULATION] Simulating incoming SMS from:" << sender
            << "text:" << text;

    qint64  timestamp = QDateTime::currentMSecsSinceEpoch();

    Message msg;
    msg.conversationId = generateConversationId(sender);
    msg.sender         = sender;
    msg.recipient      = "me";
    msg.text           = text;
    msg.timestamp      = timestamp;
    msg.isRead         = false;
    msg.isOutgoing     = false;

    storeMessage(msg);
    loadConversations();

    emit messageReceived(sender, text, timestamp);

    qInfo() << "[SMSService] [SIMULATION]Incoming SMS simulated and stored";
}

void SMSService::initDatabase() {
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataPath);

    m_database = QSqlDatabase::addDatabase("QSQLITE", "sms_db");
    m_database.setDatabaseName(dataPath + "/messages.db");

    if (!m_database.open()) {
        qWarning() << "[SMSService] Failed to open database:" << m_database.lastError().text();
        return;
    }

    QSqlQuery query(m_database);
    query.exec("CREATE TABLE IF NOT EXISTS messages ("
               "id INTEGER PRIMARY KEY AUTOINCREMENT, "
               "conversationId TEXT NOT NULL, "
               "sender TEXT NOT NULL, "
               "recipient TEXT NOT NULL, "
               "text TEXT NOT NULL, "
               "timestamp INTEGER NOT NULL, "
               "isRead INTEGER DEFAULT 0, "
               "isOutgoing INTEGER DEFAULT 0"
               ")");

    query.exec("CREATE INDEX IF NOT EXISTS idx_conversation ON messages(conversationId)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp)");

    qInfo() << "[SMSService] Database initialized";
}

void SMSService::loadConversations() {
    m_conversations.clear();

    QSqlQuery query(m_database);
    query.exec("SELECT conversationId, "
               "MAX(timestamp) as lastTimestamp, "
               "COUNT(CASE WHEN isRead = 0 AND isOutgoing = 0 THEN 1 END) as unreadCount "
               "FROM messages "
               "GROUP BY conversationId "
               "ORDER BY lastTimestamp DESC");

    while (query.next()) {
        QString   convId        = query.value("conversationId").toString();
        qint64    lastTimestamp = query.value("lastTimestamp").toLongLong();
        int       unreadCount   = query.value("unreadCount").toInt();

        QSqlQuery msgQuery(m_database);
        msgQuery.prepare(
            "SELECT text, recipient FROM messages WHERE conversationId = ? AND timestamp = ?");
        msgQuery.addBindValue(convId);
        msgQuery.addBindValue(lastTimestamp);

        QString lastMessage;
        QString contactNumber;

        if (msgQuery.exec() && msgQuery.next()) {
            lastMessage   = msgQuery.value("text").toString();
            contactNumber = msgQuery.value("recipient").toString();

            if (contactNumber == "me") {
                contactNumber = convId;
            }
        }

        Conversation conv;
        conv.id            = convId;
        conv.contactNumber = contactNumber.isEmpty() ? convId : contactNumber;
        conv.lastMessage   = lastMessage;
        conv.lastTimestamp = lastTimestamp;
        conv.unreadCount   = unreadCount;

        m_conversations.append(conv);
    }

    emit conversationsChanged();
}

void SMSService::storeMessage(const Message &msg) {
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO messages (conversationId, sender, recipient, text, timestamp, "
                  "isRead, isOutgoing) "
                  "VALUES (?, ?, ?, ?, ?, ?, ?)");
    query.addBindValue(msg.conversationId);
    query.addBindValue(msg.sender);
    query.addBindValue(msg.recipient);
    query.addBindValue(msg.text);
    query.addBindValue(msg.timestamp);
    query.addBindValue(msg.isRead ? 1 : 0);
    query.addBindValue(msg.isOutgoing ? 1 : 0);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to store message:" << query.lastError().text();
        return;
    }

    qDebug() << "[SMSService] Message stored in database";
}

void SMSService::connectToModemManager() {
    qDebug() << "[SMSService] Connecting to ModemManager";

    m_modemManager = new QDBusInterface(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", QDBusConnection::systemBus(), this);

    if (!m_modemManager->isValid()) {
        qDebug() << "[SMSService] ModemManager not available:"
                 << m_modemManager->lastError().message();
        return;
    }

    qWarning() << "[SMSService] Connected to ModemManager";

    QDBusConnection::systemBus().connect("org.freedesktop.ModemManager1", "",
                                         "org.freedesktop.ModemManager1.Modem.Messaging", "Added",
                                         this, SLOT(checkForNewMessages()));

    // Pick up any SMS that landed in modem storage BEFORE we subscribed
    // (incoming-while-shell-was-down OR shell-started-after-MM). The
    // Messaging.Added signal only fires for fresh arrivals, so without
    // this initial scan a text received before the shell finishes
    // booting sits in /org/freedesktop/ModemManager1/SMS/N forever and
    // the Messages app stays empty.
    QTimer::singleShot(0, this, &SMSService::checkForNewMessages);
}

void SMSService::checkForNewMessages() {
    if (!m_modemManager || !m_modemManager->isValid()) {
        return;
    }

    // GetManagedObjects returns a{oa{sa{sv}}} — a map of object paths
    // to interface-keyed property maps. QDBusReply<QVariantMap> can't
    // deserialize that; use the raw QDBusMessage path and unpack the
    // QDBusArgument by hand. The old QVariantMap reply silently
    // returned !isValid() and we never noticed because every log line
    // below qWarning was filtered out.
    QDBusMessage call = QDBusMessage::createMethodCall(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "GetManagedObjects");
    QDBusMessage reply = QDBusConnection::systemBus().call(call);
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        qWarning() << "[SMSService] GetManagedObjects failed:" << reply.errorMessage();
        return;
    }

    typedef QMap<QString, QVariantMap>           InterfaceList;
    typedef QMap<QDBusObjectPath, InterfaceList> ManagedObjectList;
    const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();
    ManagedObjectList   objects;
    arg >> objects;

    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        const QString        path       = it.key().path();
        const InterfaceList &interfaces = it.value();

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem.Messaging")) {
            QDBusInterface messagingInterface("org.freedesktop.ModemManager1", path,
                                              "org.freedesktop.ModemManager1.Modem.Messaging",
                                              QDBusConnection::systemBus());

            if (!messagingInterface.isValid()) {
                continue;
            }

            QDBusReply<QList<QDBusObjectPath>> listReply = messagingInterface.call("List");
            if (!listReply.isValid()) {
                continue;
            }

            QList<QDBusObjectPath> smsList = listReply.value();
            // Only log when there ARE messages to process. The poll runs
            // every ~5 s; emitting a WARNING per poll when no SMS is
            // present floods the journal with ~12 lines/min and buried
            // real shell warnings during triage.
            if (!smsList.isEmpty())
                qInfo() << "[SMSService] checkForNewMessages found" << smsList.size()
                        << "messages on" << path;

            for (const QDBusObjectPath &smsPath : smsList) {
                processIncomingSMS(path, smsPath.path());
            }
        }
    }
}

void SMSService::processIncomingSMS(const QString &modemPath, const QString &smsPath) {
    QDBusInterface smsInterface("org.freedesktop.ModemManager1", smsPath,
                                "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());

    if (!smsInterface.isValid()) {
        return;
    }

    QDBusReply<QVariant> numberReply =
        smsInterface.call("Get", "org.freedesktop.ModemManager1.Sms", "Number");
    QDBusReply<QVariant> textReply =
        smsInterface.call("Get", "org.freedesktop.ModemManager1.Sms", "Text");
    QDBusReply<QVariant> timestampReply =
        smsInterface.call("Get", "org.freedesktop.ModemManager1.Sms", "Timestamp");

    if (!numberReply.isValid() || !textReply.isValid()) {
        return;
    }

    QString sender    = numberReply.value().toString();
    QString text      = textReply.value().toString();
    qint64  timestamp = QDateTime::currentMSecsSinceEpoch();

    if (timestampReply.isValid()) {
        QString   timestampStr = timestampReply.value().toString();
        QDateTime dt           = QDateTime::fromString(timestampStr, Qt::ISODate);
        if (dt.isValid()) {
            timestamp = dt.toMSecsSinceEpoch();
        }
    }

    QSqlQuery checkQuery(m_database);
    checkQuery.prepare(
        "SELECT COUNT(*) FROM messages WHERE sender = ? AND timestamp = ? AND text = ?");
    checkQuery.addBindValue(sender);
    checkQuery.addBindValue(timestamp);
    checkQuery.addBindValue(text);

    bool isDuplicate = false;
    if (checkQuery.exec() && checkQuery.next())
        isDuplicate = checkQuery.value(0).toInt() > 0;

    if (!isDuplicate) {
        Message msg;
        msg.conversationId = generateConversationId(sender);
        msg.sender         = sender;
        msg.recipient      = "me";
        msg.text           = text;
        msg.timestamp      = timestamp;
        msg.isRead         = false;
        msg.isOutgoing     = false;

        storeMessage(msg);
        loadConversations();
        emit messageReceived(sender, text, timestamp);
        qInfo() << "[SMSService] New SMS received from:" << sender;
    }

    // Always drain the SMS from modem storage, even on dedup. The earlier code
    // returned early on duplicate detection, so re-discovered messages sat in
    // modem RAM forever -- checkForNewMessages re-read + de-duped + skipped the
    // same SMS on every 5 s poll, burning CPU and keeping the modem queue full
    // so no fresh SMS could land.
    //
    // ModemManager's system D-Bus policy does not expose Sms.Delete on the SMS
    // object path -- only Modem.Messaging.Delete(sms_path) on the modem is
    // accepted. Calling Sms.Delete here returned
    //   "security policy denied :1.N to send method call ... Sms.Delete"
    // which was silently swallowed before this fix.
    QDBusInterface messagingDelete("org.freedesktop.ModemManager1", modemPath,
                                   "org.freedesktop.ModemManager1.Modem.Messaging",
                                   QDBusConnection::systemBus());
    if (messagingDelete.isValid()) {
        QDBusReply<void> r =
            messagingDelete.call("Delete", QVariant::fromValue(QDBusObjectPath(smsPath)));
        if (!r.isValid())
            qWarning() << "[SMSService] Messaging.Delete(" << smsPath
                       << ") failed:" << r.error().message();
        else
            qWarning() << "[SMSService] drained" << smsPath << "(dup=" << isDuplicate << ")";
    }
}

QString SMSService::resolveContactName(const QString &number) const {
    if (m_contactsManager) {

        return number;
    }
    return number;
}
