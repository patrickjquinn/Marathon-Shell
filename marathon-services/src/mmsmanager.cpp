#include "mmsmanager.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryFile>

namespace {
    // NOLINTBEGIN(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString kBus     = QStringLiteral("org.ofono.mms");
    const QString kManager = QStringLiteral("/org/ofono/mms");
    const QString kService = QStringLiteral("org.ofono.mms.Service");
    const QString kMessage = QStringLiteral("org.ofono.mms.Message");
    // NOLINTEND(bugprone-throwing-static-initialization)

    // A stored part: (id, content type, file, offset, length).
    struct StoredPart {
        QString id;
        QString contentType;
        QString file;
        quint64 offset = 0;
        quint64 length = 0;
    };
    // A part to send: (id, content type, file).
    struct SendPart {
        QString id;
        QString contentType;
        QString file;
    };
    using ServiceEntry = QPair<QDBusObjectPath, QVariantMap>;
    using ServiceList  = QList<ServiceEntry>;
} // namespace

Q_DECLARE_METATYPE(StoredPart)
Q_DECLARE_METATYPE(SendPart)
Q_DECLARE_METATYPE(ServiceEntry)
Q_DECLARE_METATYPE(ServiceList)

namespace {
    QDBusArgument &operator<<(QDBusArgument &arg, const StoredPart &part) {
        arg.beginStructure();
        arg << part.id << part.contentType << part.file << part.offset << part.length;
        arg.endStructure();
        return arg;
    }
    const QDBusArgument &operator>>(const QDBusArgument &arg, StoredPart &part) {
        arg.beginStructure();
        arg >> part.id >> part.contentType >> part.file >> part.offset >> part.length;
        arg.endStructure();
        return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
    }
    QDBusArgument &operator<<(QDBusArgument &arg, const SendPart &part) {
        arg.beginStructure();
        arg << part.id << part.contentType << part.file;
        arg.endStructure();
        return arg;
    }
    const QDBusArgument &operator>>(const QDBusArgument &arg, SendPart &part) {
        arg.beginStructure();
        arg >> part.id >> part.contentType >> part.file;
        arg.endStructure();
        return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
    }

    QList<StoredPart> storedParts(const QVariant &value) {
        if (value.canConvert<QDBusArgument>())
            return qdbus_cast<QList<StoredPart>>(value.value<QDBusArgument>());
        return value.value<QList<StoredPart>>();
    }

    QString outbox() {
        return QStandardPaths::writableLocation(QStandardPaths::TempLocation) +
            QStringLiteral("/marathon/mms-out");
    }
} // namespace

MmsManager::MmsManager(QObject *parent)
    : QObject(parent) {
    qDBusRegisterMetaType<StoredPart>();
    qDBusRegisterMetaType<QList<StoredPart>>();
    qDBusRegisterMetaType<SendPart>();
    qDBusRegisterMetaType<QList<SendPart>>();
    qDBusRegisterMetaType<ServiceEntry>();
    qDBusRegisterMetaType<ServiceList>();

    QDBusConnection bus = QDBusConnection::sessionBus();
    m_watcher = new QDBusServiceWatcher(kBus, bus,
                                        QDBusServiceWatcher::WatchForRegistration |
                                            QDBusServiceWatcher::WatchForUnregistration,
                                        this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &MmsManager::discover);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &MmsManager::forget);
    bus.connect(kBus, QString(), kMessage, QStringLiteral("PropertyChanged"), this,
                SLOT(onMessagePropertyChanged(QString, QDBusVariant, QDBusMessage)));
    // Activates mmsd-tng where it is installed.
    discover();
}

void MmsManager::discover() {
    QDBusConnection bus  = QDBusConnection::sessionBus();
    auto           *call = new QDBusPendingCallWatcher(
        bus.asyncCall(QDBusMessage::createMethodCall(kBus, kManager, QStringLiteral("org.ofono.mms.Manager"),
                                                     QStringLiteral("GetServices"))),
        this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<ServiceList> reply    = *w;
        const ServiceList                    services = reply.isError() ? ServiceList() : reply.value();
        if (services.isEmpty()) {
            qDebug() << "[MmsManager] no mmsd-tng service" << reply.error().message();
            return;
        }
        const QString path = services.constFirst().first.path();
        if (path == m_servicePath)
            return;
        forget();
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.connect(kBus, path, kService, QStringLiteral("MessageAdded"), this,
                    SLOT(onMessageAdded(QDBusObjectPath, QVariantMap)));
        bus.connect(kBus, path, kService, QStringLiteral("MessageSendError"), this,
                    SLOT(onMessageSendError(QVariantMap)));
        m_servicePath = path;
        auto *props   = new QDBusPendingCallWatcher(
            bus.asyncCall(QDBusMessage::createMethodCall(kBus, path, kService,
                                                         QStringLiteral("GetProperties"))),
            this);
        connect(props, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *p) {
            p->deleteLater();
            const QDBusPendingReply<QVariantMap> values = *p;
            if (values.isError())
                return;
            m_maxAttachmentSize = values.value().value(QStringLiteral("TotalMaxAttachmentSize")).toLongLong();
            m_maxAttachments    = values.value().value(QStringLiteral("MaxAttachments")).toInt();
        });
        qInfo() << "[MmsManager] mmsd-tng service" << path;
        emit availableChanged();
    });
}

void MmsManager::forget() {
    if (m_servicePath.isEmpty())
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.disconnect(kBus, m_servicePath, kService, QStringLiteral("MessageAdded"), this,
                   SLOT(onMessageAdded(QDBusObjectPath, QVariantMap)));
    bus.disconnect(kBus, m_servicePath, kService, QStringLiteral("MessageSendError"), this,
                   SLOT(onMessageSendError(QVariantMap)));
    m_servicePath.clear();
    emit availableChanged();
}

void MmsManager::send(int token, const QStringList &recipients, const QString &text,
                      const QList<Part> &parts) {
    if (m_servicePath.isEmpty()) {
        emit failed(token, tr("MMS isn't available"));
        return;
    }
    if (recipients.isEmpty()) {
        emit failed(token, tr("No recipient"));
        return;
    }
    QList<SendPart> sendParts;
    auto           *body = new QTemporaryFile(outbox() + QStringLiteral("/text-XXXXXX.txt"), this);
    if (!text.isEmpty()) {
        QDir().mkpath(outbox());
        if (!body->open() || body->write(text.toUtf8()) < 0 || !body->flush()) {
            delete body;
            emit failed(token, tr("The message could not be prepared"));
            return;
        }
        sendParts << SendPart{QStringLiteral("text.txt"), QStringLiteral("text/plain;charset=utf-8"),
                              body->fileName()};
    }
    for (const Part &part : parts)
        sendParts << SendPart{part.name, part.contentType, part.filePath};

    QDBusMessage call = QDBusMessage::createMethodCall(kBus, m_servicePath, kService,
                                                       QStringLiteral("SendMessage"));
    // An empty SMIL: mmsd-tng writes one (AutoCreateSMIL).
    call << recipients << QVariant::fromValue(QDBusVariant(QString())) << QVariant::fromValue(sendParts);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, token, body](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                body->deleteLater();
                const QDBusPendingReply<QDBusObjectPath> reply = *w;
                if (reply.isError())
                    emit failed(token, reply.error().message());
                else
                    emit queued(token, reply.value().path());
            });
}

void MmsManager::onMessageAdded(const QDBusObjectPath &path, const QVariantMap &props) {
    const QString status = props.value(QStringLiteral("Status")).toString();
    if (status == QLatin1String("sent") || status == QLatin1String("sending_failed")) {
        emit statusChanged(path.path(), status == QLatin1String("sent") ? QStringLiteral("sent")
                                                                        : QStringLiteral("failed"));
        return;
    }
    if (status != QLatin1String("received") && status != QLatin1String("read"))
        return;

    QString      text;
    QVariantList attachments;
    const QList<StoredPart> parts = storedParts(props.value(QStringLiteral("Attachments")));
    for (const StoredPart &part : parts) {
        QFile file(part.file);
        if (!file.open(QIODevice::ReadOnly) || !file.seek(qint64(part.offset)))
            continue;
        const QByteArray data = file.read(qint64(part.length));
        if (part.contentType.startsWith(QLatin1String("application/smil")))
            continue;
        if (part.contentType.startsWith(QLatin1String("text/plain"))) {
            text += (text.isEmpty() ? QString() : QStringLiteral("\n")) + QString::fromUtf8(data);
            continue;
        }
        attachments << QVariantMap{{QStringLiteral("name"), part.id},
                                   {QStringLiteral("contentType"), part.contentType},
                                   {QStringLiteral("data"), data}};
    }
    const QString date = props.value(QStringLiteral("Date")).toString();
    QDateTime     when = QDateTime::fromString(date, Qt::ISODate);
    if (!when.isValid())
        when = QDateTime::currentDateTime();
    emit received(path.path(), props.value(QStringLiteral("Sender")).toString(),
                  props.value(QStringLiteral("Recipients")).toStringList(), text,
                  when.toMSecsSinceEpoch(), attachments);
}

void MmsManager::onMessageSendError(const QVariantMap &errorInfo) {
    const QString path = errorInfo.value(QStringLiteral("MessagePath")).toString();
    if (!path.isEmpty())
        emit statusChanged(path, QStringLiteral("failed"));
}

void MmsManager::onMessagePropertyChanged(const QString &name, const QDBusVariant &value,
                                          const QDBusMessage &message) {
    if (name != QLatin1String("Status"))
        return;
    const QString status = value.variant().toString();
    if (status == QLatin1String("sent"))
        emit statusChanged(message.path(), QStringLiteral("sent"));
    else if (status == QLatin1String("sending_failed"))
        emit statusChanged(message.path(), QStringLiteral("failed"));
}
