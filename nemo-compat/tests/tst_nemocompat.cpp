// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Nemo.DBus, Nemo.Notifications, Nemo.KeepAlive and Nemo.Configuration (and their legacy
// org.nemomobile.* URIs) on a private dbus-daemon, against FakeServices.
// Run under dbus-run-session (see CMakeLists.txt); the system bus is pointed
// at the same private daemon so nemo-keepalive's MCE calls reach the fake.

#include "fakeservices.h"

#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QFile>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QDBusPendingReply>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QTest>

class tst_NemoCompat : public QObject
{
    Q_OBJECT

public:
    explicit tst_NemoCompat(FakeServices *fake)
        : m_fake(fake)
    {
    }

private slots:
    void initTestCase();
    void init() { m_fake->clearCalls(); }

    void imports_data();
    void imports();

    void dbusTypedCallAndCallbacks();
    void dbusCallWithErrorCallback();
    void dbusProperties();
    void dbusSignals();
    void dbusAdaptor();
    void dbusServiceStatus();

    void notificationPublish();
    void notificationUpdateAndClose();
    void notificationSignals();
    void notificationList();
    void legacyNotification();

    void displayBlanking();
    void keepAlive();
    void backgroundJob();
    void legacyKeepAliveSingletons();

    void configurationValue();
    void configurationGroup();
    void configurationNestedGroups();
    void configurationExternalChange();
    void legacyConfiguration();

    void lipstickLauncherItem();
    void policyPermissions();
    void ngfPlayback();
    void ngfFailure();
    void legacyNgf();

private:
    QObject *create(const QByteArray &qml);

    FakeServices *m_fake;
    QQmlEngine *m_engine = nullptr;
    QList<QObject *> m_objects;
};

QObject *tst_NemoCompat::create(const QByteArray &qml)
{
    QQmlComponent c(m_engine);
    c.setData(qml, QUrl(QStringLiteral("inline.qml")));
    QObject *o = c.create();
    if (!o)
        qWarning().noquote() << c.errorString();
    else
        m_objects.append(o);
    return o;
}

void tst_NemoCompat::initTestCase()
{
    QVERIFY(m_fake->ready());
    m_engine = new QQmlEngine(this);
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
    // Nemo.Configuration's host fallback store (no mlite6 here); CMake points
    // KEEL_DCONF_FILE into the build tree.
    if (!qEnvironmentVariableIsEmpty("KEEL_DCONF_FILE"))
        QFile::remove(qEnvironmentVariable("KEEL_DCONF_FILE"));
}

void tst_NemoCompat::imports_data()
{
    QTest::addColumn<QByteArray>("imports");
    QTest::addColumn<QByteArray>("body");
    QTest::newRow("Nemo.DBus 2.0") << QByteArray("import Nemo.DBus 2.0") << QByteArray("DBusInterface { }");
    QTest::newRow("org.nemomobile.dbus 2.0") << QByteArray("import org.nemomobile.dbus 2.0")
                                             << QByteArray("DBusAdaptor { }");
    QTest::newRow("Nemo.Notifications 1.0") << QByteArray("import Nemo.Notifications 1.0")
                                            << QByteArray("Notification { }");
    QTest::newRow("org.nemomobile.notifications 1.0") << QByteArray("import org.nemomobile.notifications 1.0")
                                                      << QByteArray("Notification { }");
    QTest::newRow("Nemo.KeepAlive 1.2") << QByteArray("import Nemo.KeepAlive 1.2")
                                        << QByteArray("DisplayBlanking { }");
    QTest::newRow("Nemo.KeepAlive 1.1") << QByteArray("import Nemo.KeepAlive 1.1") << QByteArray("KeepAlive { }");
    QTest::newRow("org.nemomobile.keepalive 1.1") << QByteArray("import org.nemomobile.keepalive 1.1")
                                                  << QByteArray("BackgroundJob { }");
    QTest::newRow("Nemo.Configuration 1.0") << QByteArray("import Nemo.Configuration 1.0")
                                            << QByteArray("ConfigurationValue { key: '/keel/test/x' }");
    QTest::newRow("org.nemomobile.configuration 1.0") << QByteArray("import org.nemomobile.configuration 1.0")
                                                      << QByteArray("ConfigurationGroup { path: '/keel/test' }");
}

void tst_NemoCompat::imports()
{
    QFETCH(QByteArray, imports);
    QFETCH(QByteArray, body);
    QObject *o = create("import QtQuick 2.0\n" + imports + "\n" + body);
    QVERIFY(o);
}

void tst_NemoCompat::dbusTypedCallAndCallbacks()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusInterface {
    service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"
    property var echoed
    property var sum
    function run() {
        typedCall("Echo", [{ "type": "s", "value": "hello" }], function(r) { echoed = r })
        typedCall("Add", [{ "type": "i", "value": 2 }, { "type": "i", "value": 40 }], function(r) { sum = r })
    }
})QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "run");
    QTRY_COMPARE(o->property("echoed").toString(), QStringLiteral("hello"));
    QTRY_COMPARE(o->property("sum").toInt(), 42);
    QCOMPARE(m_fake->calls(QStringLiteral("Echo")).value(0).arguments, QVariantList { QStringLiteral("hello") });
}

void tst_NemoCompat::dbusCallWithErrorCallback()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusInterface {
    service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"
    property string error
    property bool succeeded: false
    function run() {
        call("Fail", undefined, function() { succeeded = true }, function(e, message) { error = e + ":" + message })
    }
})QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "run");
    QTRY_VERIFY(!o->property("error").toString().isEmpty());
    QVERIFY(o->property("error").toString().contains(QLatin1String("org.shipwright.test.Error.Failed")));
    QCOMPARE(o->property("succeeded").toBool(), false);
}

void tst_NemoCompat::dbusProperties()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusInterface {
    service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"
    propertiesEnabled: true
    property string name
    function read() { return getProperty("Name") }
    function write(v) { setProperty("Name", v) }
})QML");
    QVERIFY(o);
    QVariant v;
    QMetaObject::invokeMethod(o, "read", Q_RETURN_ARG(QVariant, v));
    QCOMPARE(v.toString(), QStringLiteral("fake"));
    // propertiesEnabled mirrors remote properties into same-named QML ones.
    QTRY_COMPARE(o->property("name").toString(), QStringLiteral("fake"));
    QMetaObject::invokeMethod(o, "write", Q_ARG(QVariant, QStringLiteral("renamed")));
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Set")).size(), 1);
    QMetaObject::invokeMethod(o, "read", Q_RETURN_ARG(QVariant, v));
    QCOMPARE(v.toString(), QStringLiteral("renamed"));
}

void tst_NemoCompat::dbusSignals()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusInterface {
    service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"
    signalsEnabled: true
    property string last
    property int count: 0
    function pinged(text) { last = text; count++ }
})QML");
    QVERIFY(o);
    // Wait for the interface to introspect the fake and connect the signal.
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("Introspect")).isEmpty());
    // The match rule reaches the bus daemon asynchronously and is not visible
    // to the fake, so emit until the first signal arrives instead of sleeping.
    const auto emitPing = [this] {
        m_fake->emitSignal(QStringLiteral("/org/shipwright/test"),
                           QStringLiteral("org.shipwright.test.Echo"),
                           QStringLiteral("Pinged"), { QStringLiteral("ping 1") });
        return true;
    };
    QTRY_VERIFY(emitPing() && o->property("count").toInt() >= 1);
    QCOMPARE(o->property("last").toString(), QStringLiteral("ping 1"));
}

void tst_NemoCompat::dbusAdaptor()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusAdaptor {
    service: "org.shipwright.test.adaptor"; path: "/adaptor"; iface: "org.shipwright.test.Adaptor"
    xml: '<interface name="org.shipwright.test.Adaptor">'
       + '<method name="hello"><arg name="who" type="s" direction="in"/><arg type="s" direction="out"/></method>'
       + '<property name="mood" type="s" access="readwrite"/>'
       + '<signal name="changed"><arg type="s"/></signal>'
       + '</interface>'
    property string mood: "calm"
    function hello(who) { return "hello " + who }
    function announce() { emitSignal("changed", ["now"]) }
})QML");
    QVERIFY(o);
    QTRY_VERIFY(m_fake->connection().interface()->isServiceRegistered(QStringLiteral("org.shipwright.test.adaptor")));
    QDBusPendingReply<QString> r = m_fake->asyncCall(QStringLiteral("org.shipwright.test.adaptor"),
                                                     QStringLiteral("/adaptor"),
                                                     QStringLiteral("org.shipwright.test.Adaptor"),
                                                     QStringLiteral("hello"), { QStringLiteral("keel") });
    QTRY_VERIFY(r.isFinished());
    QVERIFY2(!r.isError(), qPrintable(r.error().message()));
    QCOMPARE(r.value(), QStringLiteral("hello keel"));

    QDBusPendingReply<QDBusVariant> p = m_fake->asyncCall(
        QStringLiteral("org.shipwright.test.adaptor"), QStringLiteral("/adaptor"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"),
        { QStringLiteral("org.shipwright.test.Adaptor"), QStringLiteral("mood") });
    QTRY_VERIFY(p.isFinished());
    QVERIFY2(!p.isError(), qPrintable(p.error().message()));
    QCOMPARE(p.value().variant().toString(), QStringLiteral("calm"));

    QMetaObject::invokeMethod(o, "announce");
    QTRY_COMPARE(m_fake->observedSignals().size(), 1);
    QCOMPARE(m_fake->observedSignals().constFirst().member, QStringLiteral("changed"));
    QCOMPARE(m_fake->observedSignals().constFirst().arguments, QVariantList { QStringLiteral("now") });
}

void tst_NemoCompat::dbusServiceStatus()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
Item {
    property alias present: present
    property alias absent: absent
    DBusInterface { id: present; service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"; watchServiceStatus: true }
    DBusInterface { id: absent; service: "org.shipwright.nobody"; path: "/"; iface: "org.shipwright.nobody"; watchServiceStatus: true }
})QML");
    QVERIFY(o);
    auto *present = o->property("present").value<QObject *>();
    auto *absent = o->property("absent").value<QObject *>();
    // DBusInterface.Unknown == 0, Unavailable == 1, Available == 2.
    QTRY_COMPARE(present->property("status").toInt(), 2);
    // As upstream: a service that is missing at start stays Unknown until it
    // appears or disappears.
    QCOMPARE(absent->property("status").toInt(), 0);
    QVERIFY(m_fake->connection().registerService(QStringLiteral("org.shipwright.nobody")));
    QTRY_COMPARE(absent->property("status").toInt(), 2);
    QVERIFY(m_fake->connection().unregisterService(QStringLiteral("org.shipwright.nobody")));
    QTRY_COMPARE(absent->property("status").toInt(), 1);
}

void tst_NemoCompat::notificationPublish()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Notifications 1.0
Notification {
    appName: "keeltest"
    category: "x-keel.test"
    summary: "Summary"
    body: "Body text"
    previewSummary: "Preview"
    urgency: Notification.Critical
    expireTimeout: 5000
    remoteActions: [ { "name": "default", "displayName": "Open", "service": "org.shipwright.test",
                       "path": "/org/shipwright/test", "iface": "org.shipwright.test.Echo", "method": "Echo",
                       "arguments": [ "from notification" ] } ]
})QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "publish");
    const QList<RecordedCall> notify = m_fake->calls(QStringLiteral("Notify"));
    QCOMPARE(notify.size(), 1);
    const QVariantList a = notify.constFirst().arguments;
    QCOMPARE(a.value(0).toString(), QStringLiteral("keeltest"));
    QCOMPARE(a.value(1).toUInt(), 0u);
    QCOMPARE(a.value(3).toString(), QStringLiteral("Summary"));
    QCOMPARE(a.value(4).toString(), QStringLiteral("Body text"));
    QCOMPARE(a.value(5).toStringList(), (QStringList { QStringLiteral("default"), QStringLiteral("Open") }));
    const auto hints = qdbus_cast<QVariantMap>(a.value(6));
    QCOMPARE(hints.value(QStringLiteral("category")).toString(), QStringLiteral("x-keel.test"));
    QCOMPARE(hints.value(QStringLiteral("urgency")).toInt(), 2);
    QCOMPARE(hints.value(QStringLiteral("x-nemo-preview-summary")).toString(), QStringLiteral("Preview"));
    QVERIFY(hints.contains(QStringLiteral("x-nemo-remote-action-default")));
    QCOMPARE(a.value(7).toInt(), 5000);
    // The server's id becomes replacesId.
    QVERIFY(o->property("replacesId").toUInt() > 100u);
}

void tst_NemoCompat::notificationUpdateAndClose()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Notifications 1.0
Notification { appName: "keeltest"; summary: "one" })QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "publish");
    const uint id = o->property("replacesId").toUInt();
    QVERIFY(id > 0);
    o->setProperty("summary", QStringLiteral("two"));
    QMetaObject::invokeMethod(o, "publish");
    const QList<RecordedCall> notify = m_fake->calls(QStringLiteral("Notify"));
    QCOMPARE(notify.size(), 2);
    QCOMPARE(notify.at(1).arguments.value(1).toUInt(), id); // replaces the first
    QCOMPARE(notify.at(1).arguments.value(3).toString(), QStringLiteral("two"));
    QMetaObject::invokeMethod(o, "close");
    QTRY_COMPARE(m_fake->calls(QStringLiteral("CloseNotification")).size(), 1);
    QCOMPARE(m_fake->calls(QStringLiteral("CloseNotification")).constFirst().arguments.value(0).toUInt(), id);
}

void tst_NemoCompat::notificationSignals()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Notifications 1.0
Notification {
    appName: "keeltest"; summary: "signals"
    remoteActions: [ { "name": "default", "displayName": "Open" }, { "name": "reply", "displayName": "Reply" } ]
    property int clicks: 0
    property string action
    property int closeReason: -1
    onClicked: clicks++
    onActionInvoked: function(name) { action = name }
    onClosed: function(reason) { closeReason = reason }
})QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "publish");
    const uint id = o->property("replacesId").toUInt();
    const QString path = QStringLiteral("/org/freedesktop/Notifications");
    const QString iface = QStringLiteral("org.freedesktop.Notifications");
    m_fake->emitSignal(path, iface, QStringLiteral("ActionInvoked"), { id + 1000, QStringLiteral("default") });
    m_fake->emitSignal(path, iface, QStringLiteral("ActionInvoked"), { id, QStringLiteral("default") });
    QTRY_COMPARE(o->property("clicks").toInt(), 1); // the other id is ignored
    m_fake->emitSignal(path, iface, QStringLiteral("ActionInvoked"), { id, QStringLiteral("reply") });
    QTRY_COMPARE(o->property("action").toString(), QStringLiteral("reply"));
    m_fake->emitSignal(path, iface, QStringLiteral("NotificationClosed"), { id, 2u });
    QTRY_COMPARE(o->property("closeReason").toInt(), 2);
}

void tst_NemoCompat::notificationList()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Notifications 1.0
Item {
    Notification { id: a; appName: "tst_nemocompat"; summary: "listed" }
    function publishAndList() {
        a.publish()
        var list = a.notifications()
        var out = []
        for (var i = 0; i < list.length; ++i) out.push(list[i].summary)
        return out.join(",")
    }
})QML");
    QVERIFY(o);
    QVariant r;
    QMetaObject::invokeMethod(o, "publishAndList", Q_RETURN_ARG(QVariant, r));
    // notifications() asks for this application's notifications by app name.
    QCOMPARE(m_fake->calls(QStringLiteral("GetNotifications")).size(), 1);
    QVERIFY2(r.toString().contains(QLatin1String("listed")), qPrintable(r.toString()));
}

void tst_NemoCompat::legacyNotification()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import org.nemomobile.notifications 1.0
Notification { appName: "legacy"; summary: "old import" })QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "publish");
    QCOMPARE(m_fake->calls(QStringLiteral("Notify")).value(0).arguments.value(3).toString(),
             QStringLiteral("old import"));
}

void tst_NemoCompat::displayBlanking()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.KeepAlive 1.2
DisplayBlanking { })QML");
    QVERIFY(o);
    // DisplayBlanking.On == 3 after get_display_status() returned "on".
    QTRY_COMPARE(o->property("status").toInt(), 3);
    o->setProperty("preventBlanking", true);
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_display_blanking_pause")).isEmpty());
    m_fake->emitSignal(QStringLiteral("/com/nokia/mce/signal"), QStringLiteral("com.nokia.mce.signal"),
                       QStringLiteral("display_status_ind"), { QStringLiteral("off") });
    QTRY_COMPARE(o->property("status").toInt(), 1); // DisplayBlanking.Off
    o->setProperty("preventBlanking", false);
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_display_cancel_blanking_pause")).isEmpty());
}

void tst_NemoCompat::keepAlive()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.KeepAlive 1.2
KeepAlive { })QML");
    QVERIFY(o);
    o->setProperty("enabled", true);
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_cpu_keepalive_start")).isEmpty());
    o->setProperty("enabled", false);
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_cpu_keepalive_stop")).isEmpty());
}

void tst_NemoCompat::backgroundJob()
{
    // KEEL_IPHB_FALLBACK_SCALE_MS=20 (CMakeLists.txt): 30 s waits take 0.6 s.
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.KeepAlive 1.2
BackgroundJob {
    frequency: BackgroundJob.ThirtySeconds
    property int runs: 0
    property bool wasRunning: false
    onTriggered: { runs++; wasRunning = running; finished() }
})QML");
    QVERIFY(o);
    o->setProperty("enabled", true);
    QTRY_VERIFY_WITH_TIMEOUT(o->property("runs").toInt() >= 2, 10000);
    QVERIFY(o->property("wasRunning").toBool());
    QVERIFY(!m_fake->calls(QStringLiteral("req_cpu_keepalive_start")).isEmpty());
    o->setProperty("enabled", false);
    QTRY_COMPARE(o->property("running").toBool(), false);
}

void tst_NemoCompat::legacyKeepAliveSingletons()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import org.nemomobile.keepalive 1.0
QtObject {
    function enable() { KeepAlive.enabled = true; DisplayBlanking.preventBlanking = true }
    function disable() { KeepAlive.enabled = false; DisplayBlanking.preventBlanking = false }
})QML");
    QVERIFY(o);
    QMetaObject::invokeMethod(o, "enable");
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_cpu_keepalive_start")).isEmpty());
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_display_blanking_pause")).isEmpty());
    QMetaObject::invokeMethod(o, "disable");
    QTRY_VERIFY(!m_fake->calls(QStringLiteral("req_cpu_keepalive_stop")).isEmpty());
}

void tst_NemoCompat::configurationValue()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Configuration 1.0
QtObject {
    property int changes: 0
    property ConfigurationValue a: ConfigurationValue {
        key: "/keel/test/value/a"
        defaultValue: 7
        onValueChanged: changes++
    }
    property ConfigurationValue b: ConfigurationValue { key: "/keel/test/value/a" }
    property ConfigurationValue list: ConfigurationValue { key: "/keel/test/value/list" }
})QML");
    QVERIFY(o);
    auto *a = o->property("a").value<QObject *>();
    auto *b = o->property("b").value<QObject *>();
    auto *list = o->property("list").value<QObject *>();
    QCOMPARE(a->property("value").toInt(), 7); // unset: the default
    QVERIFY(!b->property("value").isValid());

    a->setProperty("value", 42);
    QCOMPARE(a->property("value").toInt(), 42);
    QCOMPARE(b->property("value").toInt(), 42); // same key, other item
    QCOMPARE(o->property("changes").toInt(), 1);

    b->setProperty("value", QStringLiteral("text"));
    QCOMPARE(a->property("value").toString(), QStringLiteral("text"));

    list->setProperty("value", QStringList{QStringLiteral("x"), QStringLiteral("y")});
    QCOMPARE(list->property("value").toStringList(), (QStringList{QStringLiteral("x"), QStringLiteral("y")}));

    // Persisted in the fallback store's file.
    QFile file(qEnvironmentVariable("KEEL_DCONF_FILE"));
    QVERIFY(file.open(QIODevice::ReadOnly));
    QVERIFY(file.readAll().contains("/keel/test/value/a"));

    // undefined unsets the key; the default shows again.
    QMetaObject::invokeMethod(a, "sync");
    a->setProperty("value", QVariant());
    QCOMPARE(a->property("value").toInt(), 7);
}

void tst_NemoCompat::configurationGroup()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Configuration 1.0
QtObject {
    id: root
    // Outside the group: a property declared on the group is itself bound
    // to a key.
    property string lastChanged
    property ConfigurationValue external: ConfigurationValue { key: "/keel/test/group/count" }
    property ConfigurationGroup group: ConfigurationGroup {
        id: group
        path: "/keel/test/group"
        property int count: 3
        property string name: "default"
        property bool flag
        onValueChanged: (key) => root.lastChanged = key
    }
    function readOther() { return group.value("other", "fallback") }
    function writeOther(v) { group.setValue("other", v) }
})QML");
    QVERIFY(o);
    auto *group = o->property("group").value<QObject *>();
    auto *external = o->property("external").value<QObject *>();
    QCOMPARE(group->property("count").toInt(), 3);

    // A bound property is written to its key...
    group->setProperty("count", 5);
    QCOMPARE(external->property("value").toInt(), 5);
    // ...and follows the key when someone else writes it.
    external->setProperty("value", 9);
    QCOMPARE(group->property("count").toInt(), 9);
    QCOMPARE(o->property("lastChanged").toString(), QStringLiteral("count"));

    group->setProperty("flag", true);
    QVariant v;
    QMetaObject::invokeMethod(o, "readOther", Q_RETURN_ARG(QVariant, v));
    QCOMPARE(v.toString(), QStringLiteral("fallback"));
    QMetaObject::invokeMethod(o, "writeOther", Q_ARG(QVariant, QVariant(QStringLiteral("set"))));
    QMetaObject::invokeMethod(o, "readOther", Q_RETURN_ARG(QVariant, v));
    QCOMPARE(v.toString(), QStringLiteral("set"));

    // A second group on the same path starts from the stored values.
    QObject *again = create(R"QML(
import QtQuick 2.0
import Nemo.Configuration 1.0
ConfigurationGroup {
    path: "/keel/test/group"
    property int count: 1
    property bool flag
})QML");
    QVERIFY(again);
    QCOMPARE(again->property("count").toInt(), 9);
    QCOMPARE(again->property("flag").toBool(), true);

    QMetaObject::invokeMethod(group, "clear");
    QVERIFY(!external->property("value").isValid());
}

void tst_NemoCompat::configurationNestedGroups()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Configuration 1.0
ConfigurationGroup {
    path: "/keel/test/nested"
    property alias child: child
    property ConfigurationValue direct: ConfigurationValue { key: "/keel/test/nested/sub/level" }
    ConfigurationGroup {
        id: child
        path: "sub"
        property int level: 1
    }
})QML");
    QVERIFY(o);
    auto *child = o->property("child").value<QObject *>();
    auto *direct = o->property("direct").value<QObject *>();
    QCOMPARE(child->property("scope").value<QObject *>(), o);
    child->setProperty("level", 4);
    QCOMPARE(direct->property("value").toInt(), 4);
    direct->setProperty("value", 6);
    QCOMPARE(child->property("level").toInt(), 6);
}

void tst_NemoCompat::configurationExternalChange()
{
    // Another process (here: a direct write of the store's file) changes a
    // key; the file watch brings the change in.
    QObject *o = create(R"QML(
import QtQuick 2.0
import Nemo.Configuration 1.0
ConfigurationValue { key: "/keel/test/external/x"; defaultValue: 0 }
)QML");
    QVERIFY(o);
    QFile in(qEnvironmentVariable("KEEL_DCONF_FILE"));
    QByteArray json = "{}";
    if (in.open(QIODevice::ReadOnly))
        json = in.readAll();
    in.close();
    json.replace(json.lastIndexOf('}'), 1, json.trimmed() == "{}" ? QByteArray("\"/keel/test/external/x\": 11}")
                                                                    : QByteArray(", \"/keel/test/external/x\": 11}"));
    QSaveFile out(qEnvironmentVariable("KEEL_DCONF_FILE"));
    QVERIFY(out.open(QIODevice::WriteOnly));
    out.write(json);
    QVERIFY(out.commit());
    QTRY_COMPARE(o->property("value").toInt(), 11);
}

void tst_NemoCompat::legacyConfiguration()
{
    QObject *o = create(R"QML(
import QtQuick 2.0
import org.nemomobile.configuration 1.0
ConfigurationGroup {
    path: "/keel/test/legacy"
    property real ratio: 0.5
})QML");
    QVERIFY(o);
    o->setProperty("ratio", 1.5);
    QObject *v = create(R"QML(
import QtQuick 2.0
import org.nemomobile.configuration 1.0
ConfigurationValue { key: "/keel/test/legacy/ratio" }
)QML");
    QVERIFY(v);
    QCOMPARE(v->property("value").toDouble(), 1.5);
}

void tst_NemoCompat::lipstickLauncherItem()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath(QStringLiteral("harbour-keeltest.desktop"));
    QFile desktop(path);
    QVERIFY(desktop.open(QIODevice::WriteOnly));
    desktop.write("[Desktop Entry]\nType=Application\nName=Keel Test\nName[fi]=Keel-testi\n"
                  "Icon=harbour-keeltest\nExec=/bin/true %U\nCategories=Utility;Network;\n"
                  "[X-Sailjail]\nPermissions=Internet\n");
    desktop.close();

    QObject *o = create(R"QML(
import QtQuick 2.0
import org.nemomobile.lipstick 0.1 as Lipstick
Lipstick.LauncherItem { }
)QML");
    QVERIFY(o);
    QVERIFY(!o->property("isValid").toBool());
    o->setProperty("filePath", path);
    QVERIFY(o->property("isValid").toBool());
    QCOMPARE(o->property("titleUnlocalized").toString(), QStringLiteral("Keel Test"));
    QCOMPARE(o->property("iconId").toString(), QStringLiteral("harbour-keeltest"));
    QCOMPARE(o->property("fileID").toString(), QStringLiteral("harbour-keeltest.desktop"));
    QCOMPARE(o->property("desktopCategories").toStringList(),
             (QStringList{QStringLiteral("Utility"), QStringLiteral("Network")}));
    QVERIFY(o->property("isSandboxed").toBool());
    QVERIFY(o->property("shouldDisplay").toBool());
    QVERIFY(!o->property("isLaunching").toBool());
    QMetaObject::invokeMethod(o, "launchApplication");
    QVERIFY(o->property("isLaunching").toBool());
}

void tst_NemoCompat::policyPermissions()
{
    for (const char *uri : {"Nemo.Policy", "org.nemomobile.policy"}) {
        QObject *o = create(QByteArray("import QtQuick 2.0\nimport ") + uri + R"QML( 1.0
Permissions {
    property int grants: 0
    property int releases: 0
    property alias camera: camera
    applicationClass: "camera"
    enabled: false
    onGranted: grants++
    onReleased: releases++
    Resource { id: camera; type: Resource.VideoRecorder; optional: false }
    Resource { type: Resource.ScaleButton; optional: true }
})QML");
        QVERIFY(o);
        auto *camera = o->property("camera").value<QObject *>();
        // No resource policy manager on this bus: Keel's engine grants
        // locally (tst_policy covers the manager).
        QVERIFY(!o->property("acquired").toBool());
        o->setProperty("enabled", true);
        QTRY_VERIFY(o->property("acquired").toBool());
        QVERIFY(camera->property("acquired").toBool());
        QCOMPARE(o->property("grants").toInt(), 1);
        QMetaObject::invokeMethod(o, "release");
        QTRY_VERIFY(!o->property("acquired").toBool());
        QCOMPARE(o->property("releases").toInt(), 1);
    }
}

void tst_NemoCompat::ngfPlayback()
{
    // libngf-qt's plugin against the fake ngfd: play() sends Play with the
    // event and its bool/int/string properties, the reply's id ties ngfd's
    // Status signals to the item, pause/resume/stop map to Pause and Stop.
    QObject *o = create(R"QML(import QtQuick 2.0
import Nemo.Ngf 1.0
NonGraphicalFeedback {
    event: "chat_fg"
    properties: [
        NgfProperty { name: "media.audio"; value: false },
        NgfProperty { name: "sound.volume"; value: 3 },
        NgfProperty { name: "sound.filename"; value: "/tmp/x.ogg" },
        NgfProperty { name: "ignored.real"; value: 1.5 }
    ]
})QML");
    QVERIFY(o);
    QCOMPARE(o->property("status").toInt(), 0); // Stopped
    QVERIFY(QMetaObject::invokeMethod(o, "play"));
    QVERIFY(o->property("connected").toBool());
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Play")).size(), 1);
    const RecordedCall play = m_fake->calls(QStringLiteral("Play")).first();
    QCOMPARE(play.path, QStringLiteral("/com/nokia/NonGraphicFeedback1"));
    QCOMPARE(play.interface, QStringLiteral("com.nokia.NonGraphicFeedback1"));
    QCOMPARE(play.arguments.value(0).toString(), QStringLiteral("chat_fg"));
    const auto props = qdbus_cast<QVariantMap>(play.arguments.value(1));
    QCOMPARE(props.value(QStringLiteral("media.audio")), QVariant(false));
    QCOMPARE(props.value(QStringLiteral("sound.volume")), QVariant(3));
    QCOMPARE(props.value(QStringLiteral("sound.filename")), QVariant(QStringLiteral("/tmp/x.ogg")));
    QVERIFY(!props.contains(QStringLiteral("ignored.real"))); // ngfd takes bool, int, string only
    QTRY_COMPARE(o->property("status").toInt(), 2); // Playing (Play replied with id 42)

    const QString path = QStringLiteral("/com/nokia/NonGraphicFeedback1");
    const QString iface = QStringLiteral("com.nokia.NonGraphicFeedback1");
    QVERIFY(QMetaObject::invokeMethod(o, "pause"));
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Pause")).size(), 1);
    QCOMPARE(m_fake->calls(QStringLiteral("Pause")).first().arguments,
             (QVariantList { QVariant(42u), QVariant(true) }));
    m_fake->emitSignal(path, iface, QStringLiteral("Status"), { 42u, 3u }); // paused
    QTRY_COMPARE(o->property("status").toInt(), 3);
    QVERIFY(QMetaObject::invokeMethod(o, "resume"));
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Pause")).size(), 2);
    QCOMPARE(m_fake->calls(QStringLiteral("Pause")).last().arguments.value(1), QVariant(false));
    m_fake->emitSignal(path, iface, QStringLiteral("Status"), { 42u, 2u }); // playing
    QTRY_COMPARE(o->property("status").toInt(), 2);
    // ngfd reports the end of the event: back to Stopped, no Stop call.
    m_fake->emitSignal(path, iface, QStringLiteral("Status"), { 42u, 1u }); // completed
    QTRY_COMPARE(o->property("status").toInt(), 0);
    QCOMPARE(m_fake->calls(QStringLiteral("Stop")).size(), 0);

    // Play again and stop it from QML.
    QVERIFY(QMetaObject::invokeMethod(o, "play"));
    QTRY_COMPARE(o->property("status").toInt(), 2);
    QVERIFY(QMetaObject::invokeMethod(o, "stop"));
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Stop")).size(), 1);
    QCOMPARE(m_fake->calls(QStringLiteral("Stop")).first().arguments.value(0), QVariant(43u));
    QCOMPARE(o->property("status").toInt(), 0);
}

void tst_NemoCompat::ngfFailure()
{
    // A Play error from ngfd turns into status Failed.
    QObject *o = create(R"QML(import QtQuick 2.0
import Nemo.Ngf 1.0
NonGraphicalFeedback { event: "unknown_event" })QML");
    QVERIFY(o);
    QVERIFY(QMetaObject::invokeMethod(o, "play"));
    QTRY_COMPARE(o->property("status").toInt(), 1); // Failed
}

void tst_NemoCompat::legacyNgf()
{
    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("org.nemomobile.ngf is deprecated")));
    QObject *o = create(R"QML(import QtQuick 2.0
import org.nemomobile.ngf 1.0
NonGraphicalFeedback { event: "chat_bg" })QML");
    QVERIFY(o);
    QVERIFY(QMetaObject::invokeMethod(o, "play"));
    QTRY_COMPARE(m_fake->calls(QStringLiteral("Play")).size(), 1);
    QCOMPARE(m_fake->calls(QStringLiteral("Play")).first().arguments.value(0).toString(), QStringLiteral("chat_bg"));
}

int main(int argc, char **argv)
{
    const QByteArray bus = qgetenv("DBUS_SESSION_BUS_ADDRESS");
    if (bus.isEmpty()) {
        fprintf(stderr, "tst_nemocompat: run under dbus-run-session (private bus)\n");
        return 1;
    }
    // One private daemon serves as both session and system bus.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", bus);
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("tst_nemocompat"));
    FakeServices fake(QString::fromUtf8(bus));
    tst_NemoCompat test(&fake);
    return QTest::qExec(&test, argc, argv);
}

#include "tst_nemocompat.moc"
