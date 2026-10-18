#include <QDBusConnection>
#include <QProcess>
#include <QThread>
#include <QTest>
#include <QSignalSpy>

#include "ipc/shellipcclients.h"

// The shell's Location1: one GeoClue session shared by the shell and apps.
class FakeLocation : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Location1")

    bool m_active = false;

  public slots:
    bool IsAvailable() const {
        return true;
    }
    bool IsActive() const {
        return m_active;
    }
    void Start() {
        setActive(true);
    }
    void Stop() {
        setActive(false);
    }
    QVariantMap GetLocation() const {
        return {};
    }
    void setActive(bool active) {
        m_active = active;
        emit activeChanged(active);
    }

  signals:
    void activeChanged(bool active);
};

class TestLocationClient : public QObject {
    Q_OBJECT

    QProcess     daemon;
    QThread      serviceThread;
    FakeLocation location;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        // Registered before the move so its signal relay moves with it.
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Location", &location,
                                     QDBusConnection::ExportAllSlots |
                                         QDBusConnection::ExportAllSignals));
        location.moveToThread(&serviceThread);
        serviceThread.start();
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }
    void cleanupTestCase() {
        serviceThread.quit();
        serviceThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }

    void stopShowsTheSessionStopped() {
        LocationClient client;
        client.start();
        QVERIFY(client.active());
        client.stop();
        QTRY_VERIFY(!client.active());
    }

    void followsTheShellStoppingIt() {
        LocationClient client;
        client.start();
        QVERIFY(client.active());
        QSignalSpy changed(&client, &LocationClient::activeChanged);
        QMetaObject::invokeMethod(&location, "setActive", Q_ARG(bool, false));
        QTRY_VERIFY(!client.active());
        QCOMPARE(changed.count(), 1);
    }
};

QTEST_MAIN(TestLocationClient)
#include "test_locationclient.moc"
