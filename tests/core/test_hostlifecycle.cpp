#include <QtTest>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QProcess>
#include <QTemporaryDir>

#include "hostlifecycle.h"
#include "keelhost.h"

class TestHostLifecycle : public QObject {
    Q_OBJECT

    QProcess      daemon;
    QString       address;
    QTemporaryDir runtime;

    // From the shell's side, as AppLaunchService calls it.
    QDBusMessage callAs(const QString &connection, const QString &appId, const QString &method,
                        const QVariantList &args) {
        QDBusConnection bus = QDBusConnection::connectToBus(address, connection);
        QDBusMessage    msg = QDBusMessage::createMethodCall(
            HostLifecycle::serviceName(appId),
            QStringLiteral("/org/marathonos/AppRunner/Lifecycle"),
            QStringLiteral("org.marathonos.AppRunner.Lifecycle1"), method);
        msg.setArguments(args);
        QDBusPendingCall pending = bus.asyncCall(msg, 5000);
        QDeadlineTimer   deadline(5000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(10);
        return pending.reply();
    }

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        QVERIFY(!address.isEmpty());
    }

    void cleanupTestCase() {
        daemon.kill();
        daemon.waitForFinished();
    }

    void serviceNameMatchesTheShells() {
        QCOMPARE(HostLifecycle::serviceName("shipwright-pacific"),
                 QStringLiteral("org.marathonos.AppRunner.shipwright_pacific"));
    }

    void shellDrivesActiveAndCover() {
        KeelHost      host(144);
        HostLifecycle lifecycle(&host, QCoreApplication::applicationPid());
        QVERIFY(lifecycle.registerOn(QDBusConnection::connectToBus(address, "host1"), "app.one"));
        QSignalSpy active(&host, &KeelHost::ActiveChanged);

        QCOMPARE(callAs("shell1", "app.one", "SetActive", {true}).type(),
                 QDBusMessage::ReplyMessage);
        QVERIFY(host.active());
        QCOMPARE(active.size(), 1);
        QCOMPARE(callAs("shell1", "app.one", "SetCoverStatus", {1}).type(),
                 QDBusMessage::ReplyMessage);
        QCOMPARE(host.coverStatus(), 1);
        callAs("shell1", "app.one", "SetActive", {false});
        QVERIFY(!host.active());
    }

    void othersAreRefused() {
        KeelHost      host(144);
        HostLifecycle lifecycle(&host, QCoreApplication::applicationPid() + 1);
        QVERIFY(lifecycle.registerOn(QDBusConnection::connectToBus(address, "host2"), "app.two"));
        const QDBusMessage reply = callAs("other2", "app.two", "SetActive", {true});
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QVERIFY(!host.active());
    }
};

QTEST_GUILESS_MAIN(TestHostLifecycle)
#include "test_hostlifecycle.moc"
