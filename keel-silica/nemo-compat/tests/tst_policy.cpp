// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Nemo.Policy against a fake resource policy manager on a private bus (the
// "system bus" here): the QML Permissions of a camera page register their
// set (class, resources, optional ones, mode, application id), acquire, are
// granted what the manager grants, lose it when the manager takes it away,
// acquire again on its advice, release, and unregister when destroyed. A
// denied set stays unacquired. Without a manager the engine grants locally;
// a manager that starts later gets the set registered and acquired again.

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTest>
#include <memory>

namespace {

const QString ManagerService = QStringLiteral("org.maemo.resource.manager");

// Resource bits of the protocol.
constexpr quint32 VideoRecorderBit = 1u << 3;
constexpr quint32 ScaleButtonBit = 1u << 10;

struct Call
{
    QString member;
    QVariantList args;
};

class FakeManager : public QDBusVirtualObject
{
public:
    FakeManager()
        : m_bus(QDBusConnection::connectToBus(QDBusConnection::SystemBus, QStringLiteral("manager")))
    {
    }
    ~FakeManager() override { stop(); }

    bool start()
    {
        return m_bus.registerVirtualObject(QStringLiteral("/org/maemo/resource/manager"), this)
            && m_bus.registerService(ManagerService);
    }
    void stop()
    {
        m_bus.unregisterService(ManagerService);
        m_bus.unregisterObject(QStringLiteral("/org/maemo/resource/manager"));
    }

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &) override
    {
        const QVariantList args = message.arguments();
        calls.append({ message.member(), args });
        const quint32 id = args.value(1).toUInt();
        const quint32 reqno = args.value(2).toUInt();
        m_client = message.service();
        m_bus.send(message.createReply(QVariantList { static_cast<qint32>(9), id, reqno, static_cast<qint32>(0), QString() }));
        if (message.member() == QLatin1String("register"))
            m_all = args.value(3).toUInt();
        if (message.member() == QLatin1String("acquire"))
            notify(id, QStringLiteral("grant"), 5, reqno, deny ? 0 : (m_all & ~withhold));
        if (message.member() == QLatin1String("release"))
            notify(id, QStringLiteral("grant"), 5, reqno, 0);
        return true;
    }

    // The manager's own calls to a client set (no reply wanted).
    void notify(quint32 id, const QString &member, qint32 type, quint32 reqno, quint32 resources)
    {
        QDBusMessage call = QDBusMessage::createMethodCall(m_client, QStringLiteral("/org/maemo/resource/client%1").arg(id),
                                                           QStringLiteral("org.maemo.resource.client"), member);
        call.setArguments({ type, id, reqno, resources });
        call.setAutoStartService(false);
        m_bus.send(call);
    }

    QList<Call> callsTo(const QString &member) const
    {
        QList<Call> result;
        for (const Call &c : calls) {
            if (c.member == member)
                result.append(c);
        }
        return result;
    }

    QList<Call> calls;
    bool deny = false;
    quint32 withhold = 0;

private:
    QDBusConnection m_bus;
    QString m_client;
    quint32 m_all = 0;
};

const char CameraPage[] = R"QML(import QtQuick 2.0
import Nemo.Policy 1.0
Permissions {
    property int grants
    property int releases
    property int losses
    property alias camera: camera
    property alias zoom: zoom
    applicationClass: "camera"
    enabled: false
    onGranted: grants++
    onReleased: releases++
    onLost: losses++
    Resource { id: camera; type: Resource.VideoRecorder; optional: false }
    Resource { id: zoom; type: Resource.ScaleButton; optional: true }
})QML";

} // namespace

class tst_Policy : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void withoutManager();
    void withManager();
    void denied();
    void managerStartsLater();

private:
    std::unique_ptr<QObject> create();
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Policy::initTestCase()
{
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

std::unique_ptr<QObject> tst_Policy::create()
{
    QQmlComponent c(m_engine.get());
    c.setData(CameraPage, QUrl(QStringLiteral("camera.qml")));
    std::unique_ptr<QObject> o(c.create());
    if (!o)
        qWarning() << c.errorString();
    return o;
}

void tst_Policy::withoutManager()
{
    std::unique_ptr<QObject> o = create();
    QVERIFY(o);
    o->setProperty("enabled", true);
    QTRY_VERIFY(o->property("acquired").toBool());
    QVERIFY(o->property("camera").value<QObject *>()->property("acquired").toBool());
    QVERIFY(o->property("zoom").value<QObject *>()->property("acquired").toBool());
    QCOMPARE(o->property("grants").toInt(), 1);
    o->setProperty("enabled", false);
    QTRY_VERIFY(!o->property("acquired").toBool());
    QCOMPARE(o->property("releases").toInt(), 1);
}

void tst_Policy::withManager()
{
    FakeManager manager;
    QVERIFY(manager.start());
    manager.withhold = ScaleButtonBit; // the optional resource is not granted
    std::unique_ptr<QObject> o = create();
    QVERIFY(o);
    auto *camera = o->property("camera").value<QObject *>();
    auto *zoom = o->property("zoom").value<QObject *>();

    o->setProperty("enabled", true);
    QTRY_VERIFY(o->property("acquired").toBool());
    QCOMPARE(o->property("grants").toInt(), 1);
    QVERIFY(camera->property("acquired").toBool());
    QVERIFY(!zoom->property("acquired").toBool());

    // register: (type, id, reqno, all, optional, share, mask, app id, class, mode)
    const QList<Call> registers = manager.callsTo(QStringLiteral("register"));
    QCOMPARE(registers.size(), 1);
    const QVariantList r = registers.first().args;
    QCOMPARE(r.size(), 10);
    QCOMPARE(r.at(0).toInt(), 0);
    const quint32 id = r.at(1).toUInt();
    QCOMPARE(r.at(3).toUInt(), VideoRecorderBit | ScaleButtonBit);
    QCOMPARE(r.at(4).toUInt(), ScaleButtonBit);
    bool hex = false;
    r.at(7).toString().toULongLong(&hex, 16);
    QVERIFY2(hex, qPrintable(r.at(7).toString()));
    QCOMPARE(r.at(8).toString(), QStringLiteral("camera"));
    QCOMPARE(r.at(9).toUInt(), 2u); // always reply, no auto release
    const QList<Call> acquires = manager.callsTo(QStringLiteral("acquire"));
    QCOMPARE(acquires.size(), 1);
    QCOMPARE(acquires.first().args.value(1).toUInt(), id);

    // The manager takes the resources away (a grant of nothing that answers
    // no request), then advises they are free again: Permissions acquires.
    manager.notify(id, QStringLiteral("grant"), 5, 0, 0);
    QTRY_COMPARE(o->property("losses").toInt(), 1);
    QVERIFY(!o->property("acquired").toBool());
    QVERIFY(!camera->property("acquired").toBool());
    manager.notify(id, QStringLiteral("advice"), 6, 0, VideoRecorderBit);
    QTRY_COMPARE(manager.callsTo(QStringLiteral("acquire")).size(), 2);
    QTRY_VERIFY(o->property("acquired").toBool());
    QCOMPARE(o->property("grants").toInt(), 2);

    QVERIFY(QMetaObject::invokeMethod(o.get(), "release"));
    QTRY_VERIFY(!o->property("acquired").toBool());
    QCOMPARE(o->property("releases").toInt(), 1);
    QCOMPARE(manager.callsTo(QStringLiteral("release")).size(), 1);

    o.reset();
    QTRY_COMPARE(manager.callsTo(QStringLiteral("unregister")).size(), 1);
    QCOMPARE(manager.callsTo(QStringLiteral("unregister")).first().args.value(1).toUInt(), id);
}

void tst_Policy::denied()
{
    FakeManager manager;
    QVERIFY(manager.start());
    manager.deny = true;
    std::unique_ptr<QObject> o = create();
    QVERIFY(o);
    o->setProperty("enabled", true);
    QTRY_COMPARE(manager.callsTo(QStringLiteral("acquire")).size(), 1);
    // Let the manager's answer arrive.
    QTest::qWait(200);
    QVERIFY(!o->property("acquired").toBool());
    QCOMPARE(o->property("grants").toInt(), 0);
}

void tst_Policy::managerStartsLater()
{
    std::unique_ptr<QObject> o = create();
    QVERIFY(o);
    o->setProperty("enabled", true);
    QTRY_VERIFY(o->property("acquired").toBool()); // granted locally
    FakeManager manager;
    QVERIFY(manager.start());
    // The set registers with the new manager and acquires again.
    QTRY_COMPARE(manager.callsTo(QStringLiteral("register")).size(), 1);
    QTRY_COMPARE(manager.callsTo(QStringLiteral("acquire")).size(), 1);
    QTRY_VERIFY(o->property("camera").value<QObject *>()->property("acquired").toBool());
}

int main(int argc, char **argv)
{
    const QByteArray bus = qgetenv("DBUS_SESSION_BUS_ADDRESS");
    if (bus.isEmpty()) {
        fprintf(stderr, "tst_policy: run under dbus-run-session (private bus)\n");
        return 1;
    }
    // The private daemon stands in for the system bus, where the manager is.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", bus);
    QGuiApplication app(argc, argv);
    tst_Policy test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_policy.moc"
