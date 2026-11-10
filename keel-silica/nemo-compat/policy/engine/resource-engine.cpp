// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The resource policy manager's D-Bus protocol, as Sailfish's policy daemon
// (ohmd's resource plugin) speaks it on the system bus; written from the
// protocol, not from libresource's code (PROVENANCE.md):
//   client -> org.maemo.resource.manager, /org/maemo/resource/manager,
//     interface org.maemo.resource.manager, methods register, unregister,
//     update, acquire, release, audio, video. Every message starts with
//     (int32 type, uint32 set id, uint32 request number); register and
//     update add (uint32 all, uint32 optional, uint32 share, uint32 mask,
//     string application id, string class, uint32 mode), audio adds
//     (string group, string application id, string property, int32 match
//     method, string pattern), video adds (uint32 pid). The reply is a
//     status: (int32 9, uint32 id, uint32 request number, int32 error code,
//     string error message).
//   manager -> client, /org/maemo/resource/client<id>, interface
//     org.maemo.resource.client: grant and advice (type, id, request
//     number, uint32 resources), release and unregister (type, id, request
//     number).

#include "resource-engine.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVirtualObject>
#include <QFile>
#include <QMetaObject>

Q_LOGGING_CATEGORY(lcResourceQt, "resourceQt", QtWarningMsg)

namespace {

const QString ManagerService = QStringLiteral("org.maemo.resource.manager");
const QString ManagerPath = QStringLiteral("/org/maemo/resource/manager");
const QString ManagerInterface = QStringLiteral("org.maemo.resource.manager");
const QString ClientInterface = QStringLiteral("org.maemo.resource.client");

// Mode bits of register and update.
constexpr quint32 ModeAutoRelease = 1u << 0;
constexpr quint32 ModeAlwaysReply = 1u << 1;

QString clientPath(quint32 id)
{
    return QStringLiteral("/org/maemo/resource/client%1").arg(id);
}

// The application id the manager uses to tie a set to its process: the
// process start time (field 22 of /proc/<pid>/stat) in hexadecimal.
QString applicationId()
{
    QFile stat(QStringLiteral("/proc/%1/stat").arg(QCoreApplication::applicationPid()));
    if (!stat.open(QIODevice::ReadOnly))
        return QString();
    const QByteArray line = stat.readAll();
    // Field 2 (the command) is in parentheses and may contain spaces.
    const int close = line.lastIndexOf(')');
    if (close < 0)
        return QString();
    const QList<QByteArray> fields = line.mid(close + 2).split(' ');
    // fields[0] is field 3.
    bool ok = false;
    const qulonglong start = fields.value(22 - 3).toULongLong(&ok);
    return ok ? QString::number(start, 16) : QString();
}

QDBusConnection bus()
{
    return QDBusConnection::systemBus();
}

class ClientObject : public QDBusVirtualObject
{
public:
    explicit ClientObject(ResourcePolicy::ResourceEngine *engine)
        : QDBusVirtualObject(engine)
        , m_engine(engine)
    {
    }

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &) override
    {
        if (message.interface() != ClientInterface)
            return false;
        m_engine->handleManagerRequest(message);
        return true;
    }

private:
    ResourcePolicy::ResourceEngine *m_engine;
};

} // namespace

namespace ResourcePolicy {

quint32 resourceTypeToLibresourceType(ResourceType type)
{
    // The manager's resource bits; bit 7 is unused.
    switch (type) {
    case AudioPlaybackType:
        return 1u << 0;
    case VideoPlaybackType:
        return 1u << 1;
    case AudioRecorderType:
        return 1u << 2;
    case VideoRecorderType:
        return 1u << 3;
    case VibraType:
        return 1u << 4;
    case LedsType:
        return 1u << 5;
    case BacklightType:
        return 1u << 6;
    case SystemButtonType:
        return 1u << 8;
    case LockButtonType:
        return 1u << 9;
    case ScaleButtonType:
        return 1u << 10;
    case SnapButtonType:
        return 1u << 11;
    case LensCoverType:
        return 1u << 12;
    case HeadsetButtonsType:
        return 1u << 13;
    case RearFlashlightType:
        return 1u << 14;
    case NumberOfTypes:
        break;
    }
    return 0;
}

ResourceEngine::ResourceEngine(ResourceSet *resourceSet)
    : m_set(resourceSet)
    , m_id(resourceSet->id())
    // Always ask for a reply, as upstream's engine does; libresourceqt's
    // ResourceSet decides what to tell the app.
    , m_mode(ModeAlwaysReply | (resourceSet->willAutoRelease() ? ModeAutoRelease : 0))
{
}

ResourceEngine::~ResourceEngine()
{
    bus().unregisterObject(clientPath(m_id));
}

bool ResourceEngine::initialize()
{
    QDBusConnection connection = bus();
    if (connection.isConnected()) {
        if (!connection.registerVirtualObject(clientPath(m_id), new ClientObject(this)))
            qCWarning(lcResourceQt) << "cannot register" << clientPath(m_id);
        auto *watcher = new QDBusServiceWatcher(ManagerService, connection,
                                                QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, &ResourceEngine::managerAppeared);
        connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, &ResourceEngine::managerVanished);
    }
    return true;
}

quint32 ResourceEngine::allResources() const
{
    quint32 bits = 0;
    if (m_set) {
        const QList<Resource *> resources = m_set->resources();
        for (Resource *resource : resources)
            bits |= resourceTypeToLibresourceType(resource->type());
    }
    return bits;
}

quint32 ResourceEngine::optionalResources() const
{
    quint32 bits = 0;
    if (m_set) {
        const QList<Resource *> resources = m_set->resources();
        for (Resource *resource : resources) {
            if (resource->isOptional())
                bits |= resourceTypeToLibresourceType(resource->type());
        }
    }
    return bits;
}

bool ResourceEngine::connectToManager()
{
    if (m_connecting)
        return true;
    if (!m_set)
        return false;
    m_connecting = true;
    QDBusConnection connection = bus();
    m_local = !connection.isConnected() || !connection.interface()
        || !connection.interface()->isServiceRegistered(ManagerService).value();
    if (m_local)
        qCInfo(lcResourceQt) << "no resource policy manager; granting resources locally";
    return send(Register,
                { allResources(), optionalResources(), static_cast<quint32>(0), static_cast<quint32>(0), applicationId(),
                  m_set->applicationClass(), m_mode });
}

bool ResourceEngine::disconnectFromManager()
{
    m_aboutToBeDeleted = true;
    m_set = nullptr;
    if (m_registered && !m_local) {
        QDBusMessage message = QDBusMessage::createMethodCall(ManagerService, ManagerPath, ManagerInterface,
                                                              QStringLiteral("unregister"));
        message.setArguments({ static_cast<qint32>(Unregister), m_id, ++m_requestNo });
        message.setAutoStartService(false);
        bus().send(message);
    }
    m_connected = false;
    m_registered = false;
    deleteLater();
    return true;
}

bool ResourceEngine::isConnectedToManager() const
{
    return m_connected;
}

bool ResourceEngine::isConnectingToManager() const
{
    return m_connecting;
}

bool ResourceEngine::acquireResources()
{
    return send(Acquire, {});
}

bool ResourceEngine::releaseResources()
{
    return send(Release, {});
}

bool ResourceEngine::updateResources()
{
    if (!m_set)
        return false;
    return send(Update,
                { allResources(), optionalResources(), static_cast<quint32>(0), static_cast<quint32>(0), QString(),
                  m_set->applicationClass(), m_mode });
}

bool ResourceEngine::registerAudioProperties(const QString &audioGroup, quint32 pid, const QString &name,
                                             const QString &value)
{
    // The stream property is matched with "equals" (method 0).
    const bool tagged = !name.isEmpty() && !value.isEmpty();
    return send(Audio,
                { audioGroup, pid ? applicationId() : QString(), tagged ? name : QString(), static_cast<qint32>(0),
                  tagged ? value : QString() });
}

bool ResourceEngine::registerVideoProperties(quint32 pid)
{
    if (pid == 0)
        return false;
    return send(Video, { pid });
}

quint32 ResourceEngine::id() const
{
    return m_id;
}

bool ResourceEngine::toBeDeleted() const
{
    return m_aboutToBeDeleted;
}

bool ResourceEngine::send(MessageType type, const QVariantList &payload)
{
    static const char *const methods[] = { "register", "unregister", "update", "acquire",
                                           "release",  "grant",      "advice", "audio",
                                           "video" };
    const quint32 requestNo = ++m_requestNo;
    m_pending.insert(requestNo, type);
    if (m_local) {
        // Answered from the event loop, as the manager's replies are.
        QMetaObject::invokeMethod(this, [this, type, requestNo] { deliverLocally(type, requestNo); },
                                  Qt::QueuedConnection);
        return true;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(ManagerService, ManagerPath, ManagerInterface,
                                                          QLatin1String(methods[type]));
    message.setArguments(QVariantList { static_cast<qint32>(type), m_id, requestNo } + payload);
    message.setAutoStartService(false);
    auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, requestNo](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusMessage reply = call->reply();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            handleStatus(requestNo, -1, reply.errorName());
            return;
        }
        const QVariantList args = reply.arguments();
        if (args.size() < 4 || args.at(0).toInt() != Status || args.at(1).toUInt() != m_id
            || args.at(2).toUInt() != requestNo) {
            handleStatus(requestNo, -1, QStringLiteral("<peer error>"));
            return;
        }
        handleStatus(requestNo, args.at(3).toInt(), args.value(4).toString());
    });
    return true;
}

void ResourceEngine::deliverLocally(MessageType type, quint32 requestNo)
{
    if (m_aboutToBeDeleted)
        return;
    handleStatus(requestNo, 0, QString());
    switch (type) {
    case Acquire:
        handleGrant(requestNo, allResources());
        break;
    case Release:
        handleGrant(requestNo, 0);
        break;
    case Update:
        if (m_set && m_set->hasResourcesGranted())
            handleGrant(requestNo, allResources());
        break;
    default:
        break;
    }
}

void ResourceEngine::handleStatus(quint32 requestNo, qint32 code, const QString &message)
{
    if (m_aboutToBeDeleted)
        return;
    const MessageType type = m_pending.value(requestNo, Status);
    if (code != 0) {
        m_pending.remove(requestNo);
        if (type == Register)
            m_connecting = false;
        qCWarning(lcResourceQt) << "resource policy request" << requestNo << "failed:" << code << message;
        m_errorMessage = message.toUtf8();
        emit errorCallback(static_cast<quint32>(code), m_errorMessage.constData());
        return;
    }
    switch (type) {
    case Register:
        m_pending.remove(requestNo);
        m_connected = true;
        m_registered = true;
        m_connecting = false;
        emit connectedToManager();
        break;
    case Update:
        emit updateOK(false);
        break;
    case Acquire:
    case Release:
        // The grant that follows completes these.
        break;
    default:
        m_pending.remove(requestNo);
        break;
    }
}

void ResourceEngine::handleGrant(quint32 requestNo, quint32 resources)
{
    if (m_aboutToBeDeleted || !m_set)
        return;
    if (resources != 0) {
        m_pending.remove(requestNo);
        emit resourcesGranted(resources);
        return;
    }
    // Nothing granted: what that means depends on the request it answers.
    const auto it = m_pending.constFind(requestNo);
    if (it == m_pending.constEnd()) {
        // Not ours: the manager took the resources away.
        emit resourcesLost(allResources());
        return;
    }
    const MessageType original = it.value();
    m_pending.erase(it);
    switch (original) {
    case Update:
        if (m_set->hasResourcesGranted())
            emit resourcesLost(allResources());
        else
            emit updateOK(m_set->alwaysGetReply());
        break;
    case Acquire:
        if (m_set->alwaysGetReply())
            emit resourcesDenied();
        break;
    case Release:
        emit resourcesReleased();
        break;
    default:
        break;
    }
}

void ResourceEngine::handleManagerRequest(const QDBusMessage &message)
{
    const QVariantList args = message.arguments();
    const qint32 type = args.value(0).toInt();
    const quint32 id = args.value(1).toUInt();
    const quint32 requestNo = args.value(2).toUInt();
    if (message.isReplyRequired()) {
        bus().send(message.createReply(QVariantList { static_cast<qint32>(Status), id, requestNo, static_cast<qint32>(0), QString() }));
    }
    if (id != m_id || m_aboutToBeDeleted)
        return;
    const QString member = message.member();
    if (member == QLatin1String("grant") && type == Grant) {
        handleGrant(requestNo, args.value(3).toUInt());
    } else if (member == QLatin1String("advice") && type == Advice) {
        emit resourcesBecameAvailable(args.value(3).toUInt());
    } else if (member == QLatin1String("release") && type == Release) {
        emit resourcesReleasedByManager();
    } else if (member == QLatin1String("unregister") && type == Unregister) {
        m_connected = false;
        m_registered = false;
        emit disconnectedFromManager();
    }
}

void ResourceEngine::managerAppeared()
{
    // A manager that starts (or restarts) after the set registered: register
    // again with it. ResourceSet's connected handler does that, re-acquiring
    // what was granted, when the engine reports a connection it does not have.
    if (m_aboutToBeDeleted || (!m_registered && !m_connecting))
        return;
    m_connected = false;
    m_registered = false;
    m_connecting = false;
    m_local = false;
    emit connectedToManager();
}

void ResourceEngine::managerVanished()
{
    if (m_local || m_aboutToBeDeleted)
        return;
    m_connected = false;
    m_registered = false;
    m_connecting = false;
}

} // namespace ResourcePolicy
