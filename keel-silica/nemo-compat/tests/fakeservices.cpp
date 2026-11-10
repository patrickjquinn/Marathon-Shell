// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "fakeservices.h"

#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QSemaphore>

namespace {

struct FakeNote
{
    QString appName;
    quint32 id = 0;
    QString appIcon;
    QString summary;
    QString body;
    QStringList actions;
    QVariantMap hints;
    qint32 expireTimeout = -1;
};

} // namespace

Q_DECLARE_METATYPE(FakeNote)
Q_DECLARE_METATYPE(QList<FakeNote>)

namespace {

QDBusArgument &operator<<(QDBusArgument &a, const FakeNote &n)
{
    a.beginStructure();
    a << n.appName << n.id << n.appIcon << n.summary << n.body << n.actions << n.hints << n.expireTimeout;
    a.endStructure();
    return a;
}

// The signature QDBusArgument streaming requires (returns its argument).
// NOLINTBEGIN(bugprone-return-const-ref-from-parameter)
const QDBusArgument &operator>>(const QDBusArgument &a, FakeNote &n)
{
    a.beginStructure();
    a >> n.appName >> n.id >> n.appIcon >> n.summary >> n.body >> n.actions >> n.hints >> n.expireTimeout;
    a.endStructure();
    return a;
}
// NOLINTEND(bugprone-return-const-ref-from-parameter)

class FakeObject : public QDBusVirtualObject
{
public:
    FakeObject(FakeServices *owner, QString xml)
        : m_owner(owner)
        , m_xml(std::move(xml))
    {
    }

    QString introspect(const QString &) const override { return m_xml; }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        m_owner->record(message);
        // QtDBus answers Introspect itself from introspect() when we decline.
        if (message.interface() == QLatin1String("org.freedesktop.DBus.Introspectable"))
            return false;
        QDBusMessage reply = respond(message);
        if (message.isReplyRequired() || reply.type() == QDBusMessage::ErrorMessage)
            connection.send(reply);
        return true;
    }

protected:
    virtual QDBusMessage respond(const QDBusMessage &m) = 0;
    FakeServices *m_owner;

private:
    QString m_xml;
};

class FakeNotifications : public FakeObject
{
public:
    using FakeObject::FakeObject;

protected:
    QDBusMessage respond(const QDBusMessage &m) override
    {
        const QString member = m.member();
        if (member == QLatin1String("Notify")) {
            const QVariantList a = m.arguments();
            FakeNote n;
            n.appName = a.value(0).toString();
            n.id = a.value(1).toUInt() ? a.value(1).toUInt() : ++m_nextId;
            n.appIcon = a.value(2).toString();
            n.summary = a.value(3).toString();
            n.body = a.value(4).toString();
            n.actions = a.value(5).toStringList();
            n.hints = qdbus_cast<QVariantMap>(a.value(6));
            n.expireTimeout = a.value(7).toInt();
            m_notes.insert(n.id, n);
            return m.createReply(QVariant::fromValue(n.id));
        }
        if (member == QLatin1String("CloseNotification")) {
            m_notes.remove(m.arguments().value(0).toUInt());
            return m.createReply();
        }
        if (member == QLatin1String("GetCapabilities"))
            return m.createReply(QStringList { QStringLiteral("body"), QStringLiteral("actions") });
        if (member == QLatin1String("GetServerInformation"))
            return m.createReply(QVariantList { QStringLiteral("fake-notifyd"), QStringLiteral("Shipwright"),
                                                QStringLiteral("1.0"), QStringLiteral("1.2") });
        if (member == QLatin1String("GetNotifications")) {
            QList<FakeNote> out;
            for (const FakeNote &n : std::as_const(m_notes))
                if (n.appName == m.arguments().value(0).toString())
                    out.append(n);
            return m.createReply(QVariant::fromValue(out));
        }
        return m.createErrorReply(QDBusError::UnknownMethod, member);
    }

private:
    quint32 m_nextId = 100;
    QMap<quint32, FakeNote> m_notes;
};

class FakeMceRequest : public FakeObject
{
public:
    using FakeObject::FakeObject;

protected:
    QDBusMessage respond(const QDBusMessage &m) override
    {
        const QString member = m.member();
        if (member == QLatin1String("get_display_blanking_pause_allowed"))
            return m.createReply(true);
        if (member == QLatin1String("get_display_status"))
            return m.createReply(m_owner->displayStatus);
        if (member == QLatin1String("req_cpu_keepalive_period"))
            return m.createReply(60);
        if (member == QLatin1String("req_cpu_keepalive_start") || member == QLatin1String("req_cpu_keepalive_stop"))
            return m.createReply(true);
        return m.createReply();
    }
};

class FakeEcho : public FakeObject
{
public:
    using FakeObject::FakeObject;

protected:
    QDBusMessage respond(const QDBusMessage &m) override
    {
        const QString member = m.member();
        const QVariantList a = m.arguments();
        if (m.interface() == QLatin1String("org.freedesktop.DBus.Properties")) {
            if (member == QLatin1String("Get") && a.value(1).toString() == QLatin1String("Name"))
                return m.createReply(QVariant::fromValue(QDBusVariant(m_name)));
            if (member == QLatin1String("Set") && a.value(1).toString() == QLatin1String("Name")) {
                m_name = qvariant_cast<QDBusVariant>(a.value(2)).variant().toString();
                return m.createReply();
            }
            if (member == QLatin1String("GetAll")) {
                QVariantMap all { { QStringLiteral("Name"), m_name } };
                return m.createReply(all);
            }
            return m.createErrorReply(QDBusError::UnknownProperty, a.value(1).toString());
        }
        if (member == QLatin1String("Echo"))
            return m.createReply(a.value(0));
        if (member == QLatin1String("Add"))
            return m.createReply(a.value(0).toInt() + a.value(1).toInt());
        if (member == QLatin1String("Fail"))
            return m.createErrorReply(QStringLiteral("org.shipwright.test.Error.Failed"), QStringLiteral("as asked"));
        return m.createErrorReply(QDBusError::UnknownMethod, member);
    }

private:
    QString m_name = QStringLiteral("fake");
};

// ngfd's backend interface as libngf-qt calls it (ngf/client/clientprivate.cpp):
// Play(s event, a{sv} properties) -> u id, Pause(u id, b pause), Stop(u id),
// and the Status(u id, u state) signal, which the test emits itself.
class FakeNgfd : public FakeObject
{
public:
    using FakeObject::FakeObject;

protected:
    QDBusMessage respond(const QDBusMessage &m) override
    {
        const QString member = m.member();
        if (member == QLatin1String("Play")) {
            if (m.arguments().value(0).toString() == QLatin1String("unknown_event"))
                return m.createErrorReply(QStringLiteral("com.nokia.NonGraphicFeedback1.Error.Failed"),
                                          QStringLiteral("no such event"));
            return m.createReply(QVariant::fromValue(++m_nextId));
        }
        if (member == QLatin1String("Pause") || member == QLatin1String("Stop"))
            return m.createReply(true);
        return m.createErrorReply(QDBusError::UnknownMethod, member);
    }

private:
    quint32 m_nextId = 41;
};

const char kNgfdXml[] = R"XML(<interface name="com.nokia.NonGraphicFeedback1">
 <method name="Play"><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="u" direction="out"/></method>
 <method name="Pause"><arg type="u" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
 <method name="Stop"><arg type="u" direction="in"/><arg type="b" direction="out"/></method>
 <signal name="Status"><arg type="u"/><arg type="u"/></signal>
</interface>
)XML";

const char kNotificationsXml[] = R"XML(<interface name="org.freedesktop.Notifications">
 <method name="GetCapabilities"><arg type="as" direction="out"/></method>
 <method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/></method>
 <method name="CloseNotification"><arg type="u" direction="in"/></method>
 <method name="GetServerInformation"><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/></method>
 <method name="GetNotifications"><arg type="s" direction="in"/><arg type="a(sussasa{sv}i)" direction="out"/></method>
 <signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
 <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
</interface>
)XML";

const char kEchoXml[] = R"XML(<interface name="org.shipwright.test.Echo">
 <method name="Echo"><arg name="value" type="s" direction="in"/><arg type="s" direction="out"/></method>
 <method name="Add"><arg name="a" type="i" direction="in"/><arg name="b" type="i" direction="in"/><arg type="i" direction="out"/></method>
 <method name="Fail"/>
 <property name="Name" type="s" access="readwrite"/>
 <signal name="Pinged"><arg name="text" type="s"/></signal>
</interface>
)XML";

} // namespace

FakeServices::FakeServices(const QString &busAddress)
    : m_context(new QObject)
{
    qDBusRegisterMetaType<FakeNote>();
    qDBusRegisterMetaType<QList<FakeNote>>();
    m_thread.setObjectName(QStringLiteral("fake-services"));
    m_thread.start();
    m_context->moveToThread(&m_thread);
    QSemaphore done;
    QMetaObject::invokeMethod(
        m_context,
        [this, busAddress, &done]() {
            m_connectionName = QStringLiteral("keel-fake-services");
            QDBusConnection c = QDBusConnection::connectToBus(busAddress, m_connectionName);
            auto *notif = new FakeNotifications(this, QLatin1String(kNotificationsXml));
            auto *mce = new FakeMceRequest(this, QString());
            auto *echo = new FakeEcho(this, QLatin1String(kEchoXml));
            auto *ngfd = new FakeNgfd(this, QLatin1String(kNgfdXml));
            m_objects = { notif, mce, echo, ngfd };
            bool ok = c.isConnected();
            ok = ok && c.registerVirtualObject(QStringLiteral("/org/freedesktop/Notifications"), notif);
            ok = ok && c.registerVirtualObject(QStringLiteral("/com/nokia/mce/request"), mce);
            ok = ok && c.registerVirtualObject(QStringLiteral("/org/shipwright/test"), echo);
            ok = ok && c.registerService(QStringLiteral("org.freedesktop.Notifications"));
            ok = ok && c.registerService(QStringLiteral("com.nokia.mce"));
            ok = ok && c.registerService(QStringLiteral("org.shipwright.test"));
            // ngfd lives on the system bus, which the tests point here too.
            ok = ok && c.registerVirtualObject(QStringLiteral("/com/nokia/NonGraphicFeedback1"), ngfd);
            ok = ok && c.registerService(QStringLiteral("com.nokia.NonGraphicFeedback1.Backend"));
            // Watch signals from the QML DBusAdaptor under test.
            ok = ok && c.connect(QString(), QString(), QStringLiteral("org.shipwright.test.Adaptor"), QString(), this,
                                 SLOT(onObservedSignal(QDBusMessage)));
            m_ready = ok;
            done.release();
        },
        Qt::QueuedConnection);
    done.acquire();
}

FakeServices::~FakeServices()
{
    QMetaObject::invokeMethod(
        m_context,
        [this]() {
            QDBusConnection::disconnectFromBus(m_connectionName);
            qDeleteAll(m_objects);
        },
        Qt::BlockingQueuedConnection);
    m_thread.quit();
    m_thread.wait();
    delete m_context;
}

QDBusConnection FakeServices::connection() const
{
    return QDBusConnection(m_connectionName);
}

void FakeServices::record(const QDBusMessage &message)
{
    QMutexLocker l(&m_mutex);
    m_calls.append({ message.path(), message.interface(), message.member(), message.arguments() });
}

QList<RecordedCall> FakeServices::calls(const QString &member) const
{
    QMutexLocker l(&m_mutex);
    if (member.isEmpty())
        return m_calls;
    QList<RecordedCall> out;
    for (const RecordedCall &c : m_calls)
        if (c.member == member)
            out.append(c);
    return out;
}

void FakeServices::clearCalls()
{
    QMutexLocker l(&m_mutex);
    m_calls.clear();
    m_signals.clear();
}

void FakeServices::emitSignal(const QString &path, const QString &interface, const QString &name,
                              const QVariantList &arguments) const
{
    QDBusMessage s = QDBusMessage::createSignal(path, interface, name);
    s.setArguments(arguments);
    connection().send(s);
}

void FakeServices::onObservedSignal(const QDBusMessage &message)
{
    QMutexLocker l(&m_mutex);
    m_signals.append({ message.path(), message.interface(), message.member(), message.arguments() });
}

QList<RecordedCall> FakeServices::observedSignals() const
{
    QMutexLocker l(&m_mutex);
    return m_signals;
}

QDBusPendingCall FakeServices::asyncCall(const QString &service, const QString &path, const QString &interface,
                                         const QString &method, const QVariantList &arguments) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, interface, method);
    m.setArguments(arguments);
    return connection().asyncCall(m);
}
