// clazy:excludeall=const-signal-or-slot (D-Bus fakes: a getter is a slot to be exported)

#include <QDBusConnection>
#include <QProcess>
#include <QThread>
#include <QTest>

#include "ipc/shellipcclients.h"

// The shell answers an undecided permission with nothing and asks the user;
// a client loaded at startup reads again once the user allows it.
class FakeAlarms : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Alarm1")

  public:
    QAtomicInt granted = 0;

  public slots:
    QVariantList GetAlarms() const {
        if (!granted.loadRelaxed())
            return {};
        return {QVariantMap{{"id", "a1"}, {"time", "07:00"}, {"enabled", true}}};
    }
    QVariantList GetActiveAlarms() const {
        return {};
    }
};

class FakeLocation : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Location1")

  public:
    QAtomicInt granted = 0;

  public slots:
    bool IsAvailable() const {
        return granted.loadRelaxed();
    }
    bool IsActive() const {
        return false;
    }
    QVariantMap GetLocation() const {
        return {};
    }
};

class FakePermissions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public slots:
    void grant(const QString &appId, const QString &permission) {
        emit PermissionGranted(appId, permission);
    }

  signals:
    void PermissionGranted(const QString &appId, const QString &permission);
};

class TestGrantRefresh : public QObject {
    Q_OBJECT

    QProcess        daemon;
    QThread         serviceThread;
    FakeAlarms      alarms;
    FakeLocation    location;
    FakePermissions permissions;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        const auto      flags = QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Alarm", &alarms, flags));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Location", &location, flags));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Permissions", &permissions, flags));
        alarms.moveToThread(&serviceThread);
        location.moveToThread(&serviceThread);
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

    void alarmsReadAgainOnceAllowed() {
        AlarmClient client;
        QCOMPARE(client.alarms().size(), 0);
        alarms.granted = 1;
        QMetaObject::invokeMethod(&permissions, "grant", Q_ARG(QString, "test"),
                                  Q_ARG(QString, "alarms"));
        QTRY_COMPARE(client.alarms().size(), 1);
    }

    void locationReadsAgainOnceAllowed() {
        LocationClient client;
        QVERIFY(!client.available());
        location.granted = 1;
        QMetaObject::invokeMethod(&permissions, "grant", Q_ARG(QString, "test"),
                                  Q_ARG(QString, "location"));
        QTRY_VERIFY(client.available());
    }
};

QTEST_GUILESS_MAIN(TestGrantRefresh)
#include "test_grantrefresh.moc"
