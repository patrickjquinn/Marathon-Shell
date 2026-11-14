// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Nemo.DBus without a reachable bus (CMake points both bus addresses at a
// missing socket): a call with an error callback must get that callback,
// with org.freedesktop.DBus.Error.Disconnected, instead of never finishing.
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QtTest>

class tst_NemoDBusNoBus : public QObject
{
    Q_OBJECT

private slots:
    void callsFailWithoutBus_data();
    void callsFailWithoutBus();
};

void tst_NemoDBusNoBus::callsFailWithoutBus_data()
{
    QTest::addColumn<QString>("bus");
    QTest::addColumn<QString>("call");
    QTest::newRow("session typedCall") << "DBus.SessionBus"
                                       << R"(typedCall("Echo", [{ "type": "s", "value": "x" }], ok, failed))";
    QTest::newRow("system call") << "DBus.SystemBus" << R"(call("Echo", ["x"], ok, failed))";
}

void tst_NemoDBusNoBus::callsFailWithoutBus()
{
    QFETCH(QString, bus);
    QFETCH(QString, call);
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    QQmlComponent c(&engine);
    c.setData(QStringLiteral(R"QML(
import QtQuick 2.0
import Nemo.DBus 2.0
DBusInterface {
    bus: %1
    service: "org.shipwright.test"; path: "/org/shipwright/test"; iface: "org.shipwright.test.Echo"
    property string error
    property bool succeeded: false
    property bool returned: false
    function ok() { succeeded = true }
    function failed(name, message) { error = name + ": " + message }
    function run() { %2; returned = true }
})QML").arg(bus, call).toUtf8(), QUrl(QStringLiteral("inline.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QVERIFY(QMetaObject::invokeMethod(o.get(), "run"));
    QVERIFY(o->property("returned").toBool());
    // Asynchronously, as for a call the bus refuses.
    QVERIFY(o->property("error").toString().isEmpty());
    QTRY_VERIFY(!o->property("error").toString().isEmpty());
    QVERIFY2(o->property("error").toString().startsWith(QLatin1String("org.freedesktop.DBus.Error.Disconnected: ")),
             qPrintable(o->property("error").toString()));
    QCOMPARE(o->property("succeeded").toBool(), false);
}

QTEST_MAIN(tst_NemoDBusNoBus)
#include "tst_nemodbus_nobus.moc"
