#include "mmsmanager.h"

#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUuid>

namespace {
    // (object_path, properties) pair returned by Manager.GetServices()
    using OAPair = QPair<QDBusObjectPath, QVariantMap>;
    using OAList = QList<OAPair>;
} // namespace

Q_DECLARE_METATYPE(OAPair)
Q_DECLARE_METATYPE(OAList)

static const QString kBus     = QStringLiteral("org.ofono.mms");
static const QString kManager = QStringLiteral("/org/ofono/mms");

MmsManager::MmsManager(QObject *parent)
    : QObject(parent)
    , m_manager(nullptr)
    , m_service(nullptr)
    , m_available(false) {
    qDBusRegisterMetaType<OAPair>();
    qDBusRegisterMetaType<OAList>();

    m_manager = new QDBusInterface(kBus, kManager, "org.ofono.mms.Manager",
                                   QDBusConnection::sessionBus(), this);

    if (!m_manager->isValid()) {
        // mmsd-tng is bus-activated, so first method call triggers spawn.
        // If the daemon isn't installed (e.g. desktop dev box), this stays
        // invalid and `available` reports false. Don't crash; just degrade.
        qDebug() << "[MmsManager] org.ofono.mms not reachable —"
                 << "MMS will be unavailable until mmsd-tng is installed";
        return;
    }

    discoverService();
}

void MmsManager::discoverService() {
    if (!m_manager || !m_manager->isValid())
        return;

    QDBusReply<OAList> reply = m_manager->call("GetServices");
    if (!reply.isValid()) {
        qDebug() << "[MmsManager] GetServices failed:" << reply.error().message();
        return;
    }

    const OAList services = reply.value();
    if (services.isEmpty()) {
        qDebug() << "[MmsManager] mmsd reports no services (modem missing?)";
        return;
    }

    m_servicePath = services.first().first.path();
    if (m_service)
        delete m_service;
    m_service = new QDBusInterface(kBus, m_servicePath, "org.ofono.mms.Service",
                                   QDBusConnection::sessionBus(), this);
    if (!m_service->isValid()) {
        qWarning() << "[MmsManager] service interface invalid:" << m_service->lastError().message();
        return;
    }

    // Subscribe to incoming events on this service path.
    QDBusConnection::sessionBus().connect(kBus, m_servicePath, "org.ofono.mms.Service",
                                          "MessageAdded", this,
                                          SLOT(onMessageAdded(QDBusObjectPath, QVariantMap)));
    QDBusConnection::sessionBus().connect(kBus, m_servicePath, "org.ofono.mms.Service",
                                          "MessageRemoved", this,
                                          SLOT(onMessageRemoved(QDBusObjectPath)));
    QDBusConnection::sessionBus().connect(kBus, m_servicePath, "org.ofono.mms.Service",
                                          "MessageSendError", this,
                                          SLOT(onMessageSendError(QVariantMap)));
    QDBusConnection::sessionBus().connect(kBus, m_servicePath, "org.ofono.mms.Service",
                                          "MessageReceiveError", this,
                                          SLOT(onMessageReceiveError(QVariantMap)));

    m_available = true;
    emit availableChanged();
    emit servicePathChanged();
    qInfo() << "[MmsManager] connected to mmsd-tng service:" << m_servicePath;
}

bool MmsManager::stageAttachmentsToTmp(const QVariantList &incoming, QList<MmsAttachment> &out,
                                       QStringList &stagedPaths) {
    const QString stageRoot =
        QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/marathon/mms-out";
    QDir().mkpath(stageRoot);

    int idx = 0;
    for (const QVariant &v : incoming) {
        const QVariantMap att         = v.toMap();
        const QString     contentType = att.value("contentType").toString();
        const QString     sourcePath  = att.value("filePath").toString();
        if (contentType.isEmpty() || sourcePath.isEmpty()) {
            qWarning() << "[MmsManager] attachment missing contentType/filePath; skipping";
            continue;
        }
        if (!QFile::exists(sourcePath)) {
            qWarning() << "[MmsManager] attachment file missing:" << sourcePath;
            return false;
        }
        const QString stagedName = QString("att-%1-%2.bin")
                                       .arg(QUuid::createUuid().toString(QUuid::WithoutBraces))
                                       .arg(idx);
        const QString staged = stageRoot + "/" + stagedName;
        if (!QFile::copy(sourcePath, staged)) {
            qWarning() << "[MmsManager] failed to stage attachment:" << sourcePath << "->"
                       << staged;
            return false;
        }
        MmsAttachment a;
        a.contentId   = QString("cid-%1").arg(idx);
        a.contentType = contentType;
        a.filePath    = staged;
        out.append(a);
        stagedPaths.append(staged);
        ++idx;
    }
    return true;
}

bool MmsManager::sendMms(const QStringList &recipients, const QString &text,
                         const QVariantList &attachments) {
    if (!m_available || !m_service || !m_service->isValid()) {
        qWarning() << "[MmsManager] not available; cannot send MMS";
        emit sendFailed("MMS daemon unavailable");
        return false;
    }
    if (recipients.isEmpty()) {
        emit sendFailed("No recipients");
        return false;
    }

    QList<MmsAttachment> staged;
    QStringList          stagedPaths;
    QVariantList         allAttachments = attachments;
    if (!text.isEmpty()) {
        // Inline the text body as a text/plain part. mmsd will weave it
        // into the SMIL automatically when AutoCreateSMIL=true (default).
        const QString textPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation) +
            "/marathon/mms-out/" +
            QString("text-%1.txt").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
        QDir().mkpath(QFileInfo(textPath).absolutePath());
        QFile f(textPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            emit sendFailed("Failed to stage MMS text body");
            return false;
        }
        f.write(text.toUtf8());
        f.close();
        QVariantMap textAtt;
        textAtt["contentType"] = "text/plain;charset=utf-8";
        textAtt["filePath"]    = textPath;
        allAttachments.prepend(textAtt);
    }
    if (!stageAttachmentsToTmp(allAttachments, staged, stagedPaths)) {
        emit sendFailed("Failed to stage MMS attachments");
        return false;
    }

    // Build the a(sss) attachment array. QtDBus needs an ArgumentList variant.
    QDBusArgument argAtts;
    argAtts.beginArray(qMetaTypeId<QString>());
    argAtts.endArray();

    // For SMIL we pass an empty string variant — mmsd auto-generates with
    // AutoCreateSMIL=true (default in mmsd-tng).
    QVariant emptySmil = QVariant::fromValue(QString());

    // The a(sss) marshalling needs to be done via QDBusArgument. Build a
    // QList of (id, type, path) and let Qt convert with a registered type.
    // The simplest reliable approach is to use the QDBusMessage low-level
    // path — register a tuple type and pass via QVariant::fromValue.
    using AttTuple = std::tuple<QString, QString, QString>;
    QList<AttTuple> tuples;
    tuples.reserve(staged.size());
    for (const auto &a : staged)
        tuples.emplace_back(a.contentId, a.contentType, a.filePath);

    // Build message manually so we can construct a(sss) precisely.
    QDBusMessage msg =
        QDBusMessage::createMethodCall(kBus, m_servicePath, "org.ofono.mms.Service", "SendMessage");
    QVariantList args;
    args << QVariant::fromValue(recipients);
    args << QVariant::fromValue(QDBusVariant(QString()));
    QDBusArgument tupleArg;
    tupleArg.beginArray(qMetaTypeId<QString>());
    // Manually marshal via low-level: D-Bus signature a(sss)
    tupleArg.endArray();
    // Let Qt's auto-marshalling handle it via a registered struct.
    args << QVariant::fromValue(tuples);
    msg.setArguments(args);

    QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[MmsManager] SendMessage failed:" << reply.errorMessage();
        emit sendFailed(reply.errorMessage());
        return false;
    }
    qInfo() << "[MmsManager] MMS submitted to" << recipients.size() << "recipients";
    return true;
}

void MmsManager::onMessageAdded(const QDBusObjectPath &path, const QVariantMap &props) {
    const QString status = props.value("Status").toString();
    if (status == QLatin1String("draft") || status == QLatin1String("sending")) {
        return; // outgoing draft — nothing to surface
    }
    if (status == QLatin1String("sent")) {
        emit messageSent(path.path());
        return;
    }

    // Received — assemble and emit.
    const QString      sender    = props.value("Sender").toString();
    const QString      date      = props.value("Date").toString();
    const qint64       timestamp = QDateTime::fromString(date, Qt::ISODate).toMSecsSinceEpoch();

    QString            text;
    QVariantList       atts;
    const QVariantList rawAtts = props.value("Attachments").toList();
    for (const QVariant &v : rawAtts) {
        const QVariantList parts = v.toList();
        if (parts.size() < 5)
            continue;
        const QString id          = parts[0].toString();
        const QString contentType = parts[1].toString();
        const QString filePath    = parts[2].toString();
        const qint64  offset      = parts[3].toLongLong();
        const qint64  length      = parts[4].toLongLong();

        if (contentType.startsWith(QLatin1String("text/"))) {
            QFile f(filePath);
            if (f.open(QIODevice::ReadOnly)) {
                f.seek(offset);
                text += QString::fromUtf8(f.read(length));
                f.close();
            }
        } else {
            QVariantMap a;
            a["contentId"]   = id;
            a["contentType"] = contentType;
            a["filePath"]    = filePath;
            a["offset"]      = offset;
            a["length"]      = length;
            atts.append(a);
        }
    }

    qInfo() << "[MmsManager] MessageAdded received from" << sender << "with" << atts.size()
            << "non-text attachments";
    emit messageReceived(sender, text, timestamp, atts);
}

void MmsManager::onMessageRemoved(const QDBusObjectPath &path) {
    qDebug() << "[MmsManager] MessageRemoved:" << path.path();
}

void MmsManager::onMessageSendError(const QVariantMap &errorInfo) {
    const uint    type = errorInfo.value("ErrorType").toUInt();
    const QString host = errorInfo.value("Host").toString();
    const QString msg  = QString("Send error type=%1 host=%2").arg(type).arg(host);
    qWarning() << "[MmsManager]" << msg;
    emit sendFailed(msg);
}

void MmsManager::onMessageReceiveError(const QVariantMap &errorInfo) {
    qWarning() << "[MmsManager] receive error:" << errorInfo;
}
