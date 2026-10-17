#include <QDBusConnection>
#include <QProcess>
#include <QThread>
#include <QtTest>

#include "ipc/shellipcclients.h"

// Power1 and Display1 need the system permission, which the shell refuses
// an unprotected app; their clients say so instead of showing empty state.
class FakePower : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Power1")

  public slots:
    QVariantMap GetState() {
        return {{"batteryLevel", 81}};
    }
};

class FakeDisplay : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Display1")

  public slots:
    QVariantMap GetState() {
        return {{"brightness", 0.5}};
    }
};

class FakePermissions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public:
    QAtomicInt allowed = 0;

  public slots:
    bool HasPermission(const QString &, const QString &) {
        return allowed.loadRelaxed();
    }
    void RequestPermission(const QString &appId, const QString &permission) {
        if (!allowed.loadRelaxed())
            emit PermissionDenied(appId, permission);
    }
    void grant(const QString &appId, const QString &permission) {
        allowed.storeRelaxed(1);
        emit PermissionGranted(appId, permission);
    }

  signals:
    void PermissionGranted(const QString &appId, const QString &permission);
    void PermissionDenied(const QString &appId, const QString &permission);
};

class TestRefusedClients : public QObject {
    Q_OBJECT

    QProcess        daemon;
    QThread         serviceThread;
    FakePower       power;
    FakeDisplay     display;
    FakePermissions permissions;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        const auto      flags = QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Power", &power, flags));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Display", &display, flags));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Permissions", &permissions, flags));
        power.moveToThread(&serviceThread);
        display.moveToThread(&serviceThread);
        permissions.moveToThread(&serviceThread);
        serviceThread.start();
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }
    void cleanupTestCase() {
        serviceThread.quit();
        serviceThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }
    void init() {
        permissions.allowed.storeRelaxed(0);
    }

    void powerSaysWhenRefused() {
        PowerClient client("test");
        QTRY_VERIFY(!client.permitted());
        QCOMPARE(client.batteryLevel(), 0);
        QMetaObject::invokeMethod(&permissions, "grant", Q_ARG(QString, "test"),
                                  Q_ARG(QString, "system"));
        QTRY_COMPARE(client.batteryLevel(), 81);
        QVERIFY(client.permitted());
    }

    void displaySaysWhenRefused() {
        DisplayClient client("test");
        QTRY_VERIFY(!client.permitted());
        QMetaObject::invokeMethod(&permissions, "grant", Q_ARG(QString, "test"),
                                  Q_ARG(QString, "system"));
        QTRY_COMPARE(client.brightness(), 0.5);
        QVERIFY(client.permitted());
    }
};

QTEST_GUILESS_MAIN(TestRefusedClients)
#include "test_refusedclients.moc"
