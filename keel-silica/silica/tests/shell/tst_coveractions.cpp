// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Cover actions in direct mode (plugin/cpp/coveractions.h), on a private
// session bus: the bus name, object path and _APP_COVER_ACTION value are
// what Silica's Qt 5 covers give Lipstick (captured on a Jolla Phone,
// Sailfish OS 5.2.0.18), and only the owner of com.jolla.lipstick can
// trigger an action.

#include "coveractions.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QLoggingCategory>
#include <QSignalSpy>
#include <QTest>

Q_LOGGING_CATEGORY(lcKeelShell, "keel.shell")

using keel::CoverActions;

class tst_CoverActions : public QObject
{
    Q_OBJECT

private slots:
    void serviceName();
    void objectPath();
    void propertyValue();
    void onlyLipstickTriggers();
};

void tst_CoverActions::serviceName()
{
    // Jolla Notes, sandboxed (pid 32 in its namespace), as on the phone.
    QCOMPARE(CoverActions::serviceName(QStringLiteral("com.jolla"), QStringLiteral("notes"), 32, 1),
             QStringLiteral("org.sailfishos.coveraction.com.jolla.notes.pid32.id1"));
    // Keel apps' names have '-', which no bus name or path element may have.
    QCOMPARE(CoverActions::serviceName(QStringLiteral("org.shipwright"), QStringLiteral("shoal-keys"), 4023, 2),
             QStringLiteral("org.sailfishos.coveraction.org.shipwright.shoal_keys.pid4023.id2"));
    QCOMPARE(CoverActions::serviceName(QString(), QStringLiteral("9lives"), 7, 1),
             QStringLiteral("org.sailfishos.coveraction._9lives.pid7.id1"));
    QCOMPARE(CoverActions::serviceName(QString(), QString(), 7, 1),
             QStringLiteral("org.sailfishos.coveraction.app.pid7.id1"));
}

void tst_CoverActions::objectPath()
{
    QCOMPARE(CoverActions::objectPath(QStringLiteral("org.sailfishos.coveraction.com.jolla.notes.pid32.id1")),
             QStringLiteral("/org/sailfishos/coveraction/com/jolla/notes/pid32/id1"));
}

void tst_CoverActions::propertyValue()
{
    // Silica's, for a CoverActionList (iconBackground: true) of two actions.
    const QString service = QStringLiteral("org.sailfishos.coveraction.covertest.covertest.pid42333.id1");
    QCOMPARE(CoverActions::propertyValue(service,
                                         {QStringLiteral("image://theme/icon-cover-previous"),
                                          QStringLiteral("image://theme/icon-cover-next")},
                                         true),
             service + QStringLiteral("\ntrigger\n0\nimage://theme/icon-cover-previous\n")
                     + service + QStringLiteral("\ntrigger\n1\nimage://theme/icon-cover-next\n1"));
    // Jolla Notes: one action, no background.
    const QString notes = QStringLiteral("org.sailfishos.coveraction.com.jolla.notes.pid38892.id1");
    QCOMPARE(CoverActions::propertyValue(notes, {QStringLiteral("image://theme/icon-cover-new")}, false),
             notes + QStringLiteral("\ntrigger\n0\nimage://theme/icon-cover-new\n0"));
    QCOMPARE(CoverActions::propertyValue(notes, {}, true), QString());
}

// Asynchronous: the object answers on this thread's event loop.
static QDBusMessage callTrigger(QDBusConnection &bus, const QString &service, int index)
{
    QDBusMessage call = QDBusMessage::createMethodCall(service, CoverActions::objectPath(service),
                                                       QStringLiteral("org.sailfishos.silica.coveraction"),
                                                       QStringLiteral("trigger"));
    call << index;
    QDBusPendingCall pending = bus.asyncCall(call);
    for (int waited = 0; !pending.isFinished() && waited < 10000; waited += 10)
        QTest::qWait(10);
    return pending.reply();
}

void tst_CoverActions::onlyLipstickTriggers()
{
    QDBusConnection app = QDBusConnection::sessionBus();
    if (!app.isConnected())
        QSKIP("no session bus (run under dbus-run-session)");
    const QString service = CoverActions::serviceName(QStringLiteral("org.shipwright"),
                                                      QStringLiteral("keel-test"), 1, 1);
    CoverActions actions(app, service);
    QVERIFY(actions.registered());
    QSignalSpy triggered(&actions, &CoverActions::triggered);

    // Anyone else on the bus is refused.
    QDBusConnection other = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("other"));
    QVERIFY(other.isConnected());
    QDBusMessage reply = callTrigger(other, service, 0);
    QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
    QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.AccessDenied"));
    QCOMPARE(triggered.count(), 0);

    // Lipstick is heard.
    QDBusConnection lipstick = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("lipstick"));
    QVERIFY(lipstick.isConnected());
    QVERIFY(lipstick.registerService(QStringLiteral("com.jolla.lipstick")));
    reply = callTrigger(lipstick, service, 1);
    QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
    QTRY_COMPARE(triggered.count(), 1);
    QCOMPARE(triggered.at(0).at(0).toInt(), 1);

    // The name and object go with the cover.
    {
        CoverActions second(app, CoverActions::serviceName(QString(), QStringLiteral("second"), 1, 2));
        QVERIFY(second.registered());
        QVERIFY(app.interface()->isServiceRegistered(second.service()).value());
    }
    QVERIFY(!app.interface()->isServiceRegistered(
                    CoverActions::serviceName(QString(), QStringLiteral("second"), 1, 2)).value());

    QDBusConnection::disconnectFromBus(QStringLiteral("other"));
    QDBusConnection::disconnectFromBus(QStringLiteral("lipstick"));
}

QTEST_GUILESS_MAIN(tst_CoverActions)
#include "tst_coveractions.moc"
