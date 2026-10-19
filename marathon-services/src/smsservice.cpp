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
#include <QBuffer>
#include <QDir>
#include <QImage>
#include <QImageReader>
#include <cmath>
#include <QFile>
#include <QFileInfo>
#include <unistd.h>
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
    // An MMS joins the sender's thread, with its pictures in the store.
    connect(m_mmsManager, &MmsManager::received, this,
            [this](const QString &path, const QString &sender, const QStringList &,
                   const QString &text, qint64 timestamp, const QVariantList &attachments) {
                Message msg;
                msg.conversationId = generateConversationId(sender);
                msg.sender         = sender;
                msg.recipient      = QStringLiteral("me");
                msg.text           = text;
                msg.timestamp      = timestamp;
                msg.isRead         = false;
                msg.isOutgoing     = false;
                msg.mmsPath        = path;
                const int id       = storeMessage(msg);
                for (const QVariant &value : attachments) {
                    const QVariantMap attachment = value.toMap();
                    addAttachment(id, attachment.value(QStringLiteral("contentType")).toString(),
                                  attachment.value(QStringLiteral("name")).toString(),
                                  attachment.value(QStringLiteral("data")).toByteArray());
                }
                loadConversations();
                emit messageReceived(sender, text, timestamp);
            });
    connect(m_mmsManager, &MmsManager::availableChanged, this,
            [this]() { emit mmsAvailableChanged(mmsAvailable()); });
    connect(m_mmsManager, &MmsManager::queued, this, [this](int id, const QString &path) {
        QSqlQuery query(m_database);
        query.prepare(QStringLiteral("UPDATE messages SET mmsPath = ? WHERE id = ?"));
        query.addBindValue(path);
        query.addBindValue(id);
        query.exec();
    });
    connect(m_mmsManager, &MmsManager::failed, this, [this](int id, const QString &reason) {
        setStatus(id, QStringLiteral("failed"));
        emit sendFailed(QString(), reason);
    });
    connect(m_mmsManager, &MmsManager::statusChanged, this,
            [this](const QString &path, const QString &status) {
                QSqlQuery query(m_database);
                query.prepare(QStringLiteral("SELECT id FROM messages WHERE mmsPath = ? AND isOutgoing = 1"));
                query.addBindValue(path);
                if (query.exec() && query.next())
                    setStatus(query.value(0).toInt(), status);
            });
}

bool SMSService::mmsAvailable() const {
    return m_mmsManager && m_mmsManager->available();
}

void SMSService::setStatus(int id, const QString &status) {
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("UPDATE messages SET status = ? WHERE id = ?"));
    query.addBindValue(status);
    query.addBindValue(id);
    if (query.exec() && query.numRowsAffected() > 0)
        emit messageStatusChanged(id, status);
}

int SMSService::sendMms(const QStringList &recipients, const QString &text,
                        const QList<MmsPart> &parts) {
    if (recipients.isEmpty() || (text.isEmpty() && parts.isEmpty())) {
        emit sendFailed(recipients.join(QLatin1Char(',')), tr("Nothing to send"));
        return -1;
    }
    Message msg;
    msg.conversationId = generateConversationId(recipients.join(QLatin1Char(',')));
    msg.sender         = QStringLiteral("me");
    msg.recipient      = recipients.join(QLatin1Char(','));
    msg.text           = text;
    msg.timestamp      = QDateTime::currentMSecsSinceEpoch();
    msg.isRead         = true;
    msg.isOutgoing     = true;
    msg.status         = QStringLiteral("sending");
    const int id       = storeMessage(msg);
    if (id < 0)
        return -1;

    QList<int> stored;
    for (const MmsPart &part : parts) {
        const int attachment = addAttachment(id, part.contentType, part.name, part.fd);
        if (attachment < 0) {
            setStatus(id, QStringLiteral("failed"));
            loadConversations();
            emit sendFailed(msg.recipient, tr("An attachment could not be read"));
            return id;
        }
        stored << attachment;
    }
    loadConversations();

    if (!m_mmsManager || !m_mmsManager->available()) {
        setStatus(id, QStringLiteral("failed"));
        emit sendFailed(msg.recipient, tr("MMS isn't available"));
        return id;
    }

    constexpr qint64 kDefaultLimit = qint64{300} * 1024;
    const qint64     limit =
        m_mmsManager->maxAttachmentSize() > 0 ? m_mmsManager->maxAttachmentSize() : kDefaultLimit;
    const qint64 budget = stored.isEmpty() ? limit :
                                             (limit - text.toUtf8().size() - 2048) / stored.size();
    QList<MmsManager::Part> mmsParts;
    for (const int attachment : std::as_const(stored)) {
        if (!fitToLimit(attachment, budget)) {
            setStatus(id, QStringLiteral("failed"));
            emit sendFailed(msg.recipient, tr("Too big to send as MMS"));
            return id;
        }
        QSqlQuery query(m_database);
        query.prepare(QStringLiteral("SELECT contentType, name, path FROM attachments WHERE id = ?"));
        query.addBindValue(attachment);
        if (query.exec() && query.next())
            mmsParts << MmsManager::Part{query.value(0).toString(), query.value(1).toString(),
                                         query.value(2).toString()};
    }
    m_mmsManager->send(id, recipients, text, mmsParts);
    return id;
}

// A picture over budget is re-encoded as a smaller JPEG; anything else
// over budget cannot be sent.
bool SMSService::fitToLimit(int attachmentId, qint64 budget) {
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT contentType, name, size, path FROM attachments WHERE id = ?"));
    query.addBindValue(attachmentId);
    if (!query.exec() || !query.next())
        return false;
    const QString type = query.value(0).toString();
    const QString name = query.value(1).toString();
    const qint64  size = query.value(2).toLongLong();
    const QString path = query.value(3).toString();
    if (size <= budget)
        return true;
    if (!type.startsWith(QLatin1String("image/")) || budget <= 0)
        return false;

    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull())
        return false;
    QByteArray jpeg;
    for (int quality = 85; image.width() >= 160; quality = qMax(60, quality - 10)) {
        jpeg.clear();
        QBuffer buffer(&jpeg);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "JPEG", quality);
        if (jpeg.size() <= budget)
            break;
        const double factor = qMin(0.9, std::sqrt(double(budget) / double(jpeg.size())));
        image = image.scaled(qRound(image.width() * factor), qRound(image.height() * factor),
                             Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (jpeg.isEmpty() || jpeg.size() > budget)
        return false;
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) || file.write(jpeg) != jpeg.size())
        return false;
    QSqlQuery update(m_database);
    update.prepare(QStringLiteral("UPDATE attachments SET contentType = 'image/jpeg', name = ?, size = ? "
                                  "WHERE id = ?"));
    update.addBindValue(QFileInfo(name).completeBaseName() + QStringLiteral(".jpg"));
    update.addBindValue(qint64(jpeg.size()));
    update.addBindValue(attachmentId);
    return update.exec();
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
        msg.status         = QStringLiteral("failed");

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
        msg["status"]         = query.value("status").toString();
        msg["attachments"]    = attachmentsOf(msg["id"].toInt());
        result.append(msg);
    }

    return result;
}

void SMSService::deleteConversation(const QString &conversationId) {
    removeAttachments(QStringLiteral("conversationId"), conversationId);
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

bool SMSService::deleteMessage(int id) {
    removeAttachments(QStringLiteral("id"), id);
    QSqlQuery query(m_database);
    query.prepare("DELETE FROM messages WHERE id = ?");
    query.addBindValue(id);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to delete message:" << query.lastError().text();
        return false;
    }
    if (query.numRowsAffected() < 1)
        return false;

    loadConversations();
    return true;
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

    static const QRegularExpression nonDialable("[^0-9+]");
    QString                         normalized = number;
    normalized.remove(nonDialable);
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
    migrateDatabase();

    qInfo() << "[SMSService] Database initialized";
}

// MMS added a status, participants and mmsd-tng's path to each message, and
// attachments; a database from before gets them in place.
void SMSService::migrateDatabase() {
    QSqlQuery   query(m_database);
    QStringList columns;
    query.exec(QStringLiteral("PRAGMA table_info(messages)"));
    while (query.next())
        columns << query.value(1).toString();
    for (const char *column : {"status", "participants", "mmsPath"}) {
        if (!columns.contains(QLatin1String(column)))
            query.exec(QStringLiteral("ALTER TABLE messages ADD COLUMN %1 TEXT NOT NULL DEFAULT ''")
                           .arg(QLatin1String(column)));
    }
    query.exec(QStringLiteral("UPDATE messages SET status = CASE WHEN isOutgoing = 1 THEN 'sent' "
                              "ELSE 'received' END WHERE status = ''"));
    query.exec(QStringLiteral("CREATE TABLE IF NOT EXISTS attachments ("
                              "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                              "messageId INTEGER NOT NULL, "
                              "contentType TEXT NOT NULL, "
                              "name TEXT NOT NULL, "
                              "size INTEGER NOT NULL, "
                              "path TEXT NOT NULL)"));
    query.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS idx_attachment_message ON attachments(messageId)"));
}

QString SMSService::attachmentDir(int messageId) {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) +
        QStringLiteral("/marathon/mms/%1").arg(messageId);
}

int SMSService::addAttachment(int messageId, const QString &contentType, const QString &name,
                              int fd) {
    QFile source;
    if (fd < 0 || !source.open(::dup(fd), QIODevice::ReadOnly, QFileDevice::AutoCloseHandle))
        return -1;
    return addAttachment(messageId, contentType, name, source.readAll());
}

int SMSService::addAttachment(int messageId, const QString &contentType, const QString &name,
                              const QByteArray &data) {
    QString file = QFileInfo(name).fileName();
    if (file.isEmpty() || file == QLatin1String(".") || file == QLatin1String(".."))
        file = QStringLiteral("attachment");
    const QString dir = attachmentDir(messageId);
    if (messageId < 0 || !QDir().mkpath(dir))
        return -1;
    QString path = dir + QLatin1Char('/') + file;
    for (int n = 2; QFile::exists(path); ++n)
        path = dir + QStringLiteral("/%1-%2").arg(n).arg(file);
    QFile target(path);
    if (!target.open(QIODevice::WriteOnly) || target.write(data) != data.size()) {
        target.remove();
        return -1;
    }
    target.close();

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO attachments (messageId, contentType, name, size, path) "
                                 "VALUES (?, ?, ?, ?, ?)"));
    query.addBindValue(messageId);
    query.addBindValue(contentType);
    query.addBindValue(file);
    query.addBindValue(qint64(data.size()));
    query.addBindValue(path);
    if (!query.exec()) {
        QFile::remove(path);
        return -1;
    }
    return query.lastInsertId().toInt();
}

QString SMSService::attachmentPath(int attachmentId) const {
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT path FROM attachments WHERE id = ?"));
    query.addBindValue(attachmentId);
    return query.exec() && query.next() ? query.value(0).toString() : QString();
}

QVariantList SMSService::attachmentsOf(int messageId) const {
    QVariantList out;
    QSqlQuery    query(m_database);
    query.prepare(QStringLiteral(
        "SELECT id, contentType, name, size FROM attachments WHERE messageId = ? ORDER BY id"));
    query.addBindValue(messageId);
    if (!query.exec())
        return out;
    while (query.next())
        out << QVariantMap{{QStringLiteral("id"), query.value(0).toInt()},
                           {QStringLiteral("contentType"), query.value(1).toString()},
                           {QStringLiteral("name"), query.value(2).toString()},
                           {QStringLiteral("size"), query.value(3).toLongLong()}};
    return out;
}

// Removes the attachments of the messages `where` selects (a column of
// messages, compared with value).
void SMSService::removeAttachments(const QString &where, const QVariant &value) {
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT id FROM messages WHERE %1 = ?").arg(where));
    query.addBindValue(value);
    if (!query.exec())
        return;
    QList<int> ids;
    while (query.next())
        ids << query.value(0).toInt();
    for (const int id : std::as_const(ids)) {
        QDir(attachmentDir(id)).removeRecursively();
        QSqlQuery remove(m_database);
        remove.prepare(QStringLiteral("DELETE FROM attachments WHERE messageId = ?"));
        remove.addBindValue(id);
        remove.exec();
    }
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

int SMSService::storeMessage(const Message &msg) {
    QSqlQuery query(m_database);
    query.prepare("INSERT INTO messages (conversationId, sender, recipient, text, timestamp, "
                  "isRead, isOutgoing, status, mmsPath) "
                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
    query.addBindValue(msg.conversationId);
    query.addBindValue(msg.sender);
    query.addBindValue(msg.recipient);
    query.addBindValue(msg.text.isNull() ? QString(QLatin1String("")) : msg.text);
    query.addBindValue(msg.timestamp);
    query.addBindValue(msg.isRead ? 1 : 0);
    query.addBindValue(msg.isOutgoing ? 1 : 0);
    query.addBindValue(!msg.status.isEmpty() ? msg.status :
                       msg.isOutgoing        ? QStringLiteral("sent") :
                                               QStringLiteral("received"));
    query.addBindValue(msg.mmsPath.isNull() ? QString(QLatin1String("")) : msg.mmsPath);

    if (!query.exec()) {
        qWarning() << "[SMSService] Failed to store message:" << query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
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

            for (const QDBusObjectPath &smsPath : std::as_const(smsList)) {
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
