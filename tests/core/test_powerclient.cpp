#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QProcess>
#include <QThread>
#include <QTest>

#include "marathon-app-native/src/power.cxxqt.h"
#include "marathon-app-native/src/shell.cxxqt.h"

// The shell's Power1 and Permissions1, on their own thread because the
// client blocks on its calls.
class FakePower : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Power1")

  public:
    QAtomicInt  refuse;
    QStringList calls;

  public slots:
    QVariantMap GetState() {
        return {};
    }
    bool Wake(const QString &reason) {
        calls << QStringLiteral("Wake %1").arg(reason);
        if (refuse.loadRelaxed())
            sendErrorReply(QDBusError::AccessDenied, QStringLiteral("Missing permission: system"));
        return true;
    }
    bool ScheduleWake(qint64 epochSecs, const QString &reason) {
        calls << QStringLiteral("ScheduleWake %1 %2").arg(QString::number(epochSecs), reason);
        return !refuse.loadRelaxed();
    }
};

class FakePermissions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public slots:
    bool HasPermission(const QString &, const QString &) {
        return true;
    }
};

class TestPowerClient : public QObject {
    Q_OBJECT

    QProcess        daemon;
    QThread         serviceThread;
    FakePower       power;
    FakePermissions permissions;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());
        marathon::platform::set_app_id("test");

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        power.moveToThread(&serviceThread);
        permissions.moveToThread(&serviceThread);
        serviceThread.start();
        const auto all = QDBusConnection::ExportAllSlots;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Power", &power, all));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Permissions", &permissions, all));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }
    void cleanupTestCase() {
        serviceThread.quit();
        serviceThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }
    void init() {
        power.refuse.storeRelaxed(0);
    }

    void wakeReportsTheShellsAnswer() {
        marathon::platform::Power client;
        QVERIFY(client.wake(QStringLiteral("alarm")));
        power.refuse.storeRelaxed(1);
        QVERIFY(!client.wake(QStringLiteral("call")));
        QCOMPARE(power.calls.mid(power.calls.size() - 2), (QStringList{"Wake alarm", "Wake call"}));
    }

    void scheduleWakeSendsTheTimeInSeconds() {
        marathon::platform::Power client;
        const QDateTime when = QDateTime::fromSecsSinceEpoch(1792236376);
        QVERIFY(client.scheduleWake(when, QStringLiteral("test")));
        QCOMPARE(power.calls.last(), QStringLiteral("ScheduleWake 1792236376 test"));
        power.refuse.storeRelaxed(1);
        QVERIFY(!client.scheduleWake(when, QStringLiteral("test")));
    }
};

QTEST_MAIN(TestPowerClient)
#include "test_powerclient.moc"
