#include <QTest>
#include <QDBusConnection>
#include <QElapsedTimer>
#include <QProcess>
#include <QThread>

#include "ambienceclient.h"

// Stands in for the shell's org.marathonos.Shell.Ambience1.
class FakeAmbience : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Ambience1")

  public:
    QVariantMap map;

  public slots:
    QVariantMap GetAmbience() const {
        return map;
    }

  signals:
    void AmbienceChanged(const QVariantMap &ambience);
};

class TestAmbienceClient : public QObject {
    Q_OBJECT

    QProcess daemon;
    QString  address;

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

    void fetchesWhenTheShellAppearsLater() {
        QDBusConnection client = QDBusConnection::connectToBus(address, "client1");
        QVERIFY(client.isConnected());
        AmbienceClient ambience(client);
        QTest::qWait(200);
        QVERIFY(ambience.ambience().isEmpty());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell1");
        FakeAmbience    fake;
        fake.map = {{"/desktop/jolla/theme/color/highlight", "#759b97"}};
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Ambience", &fake,
                                     QDBusConnection::ExportAllSlots |
                                         QDBusConnection::ExportAllSignals));
        QVERIFY(shell.registerService("org.marathonos.Shell"));

        QTRY_COMPARE(ambience.ambience().value("/desktop/jolla/theme/color/highlight").toString(),
                     QStringLiteral("#759b97"));
        shell.unregisterService("org.marathonos.Shell");
        QDBusConnection::disconnectFromBus("shell1");
        QDBusConnection::disconnectFromBus("client1");
    }

    void fetchNowReturnsTheAmbienceWithoutTheEventLoop() {
        // The real shell is another process; a thread stands in so the
        // blocking call can be answered.
        QThread         shellThread;
        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell3");
        FakeAmbience    fake;
        fake.map = {{"/desktop/jolla/theme/color/highlight", "#123456"}};
        fake.moveToThread(&shellThread);
        shellThread.start();
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Ambience", &fake,
                                     QDBusConnection::ExportAllSlots |
                                         QDBusConnection::ExportAllSignals));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
        QDBusConnection client = QDBusConnection::connectToBus(address, "client3");
        AmbienceClient  ambience(client);
        QVERIFY(ambience.fetchNow(1000));
        QCOMPARE(ambience.ambience().value("/desktop/jolla/theme/color/highlight").toString(),
                 QStringLiteral("#123456"));
        shell.unregisterService("org.marathonos.Shell");
        shell.unregisterObject("/org/marathonos/Shell/Ambience");
        shellThread.quit();
        shellThread.wait();
        fake.moveToThread(thread());
        QDBusConnection::disconnectFromBus("shell3");
        QDBusConnection::disconnectFromBus("client3");
    }

    void fetchNowFailsFastWithoutTheShell() {
        QDBusConnection client = QDBusConnection::connectToBus(address, "client4");
        AmbienceClient  ambience(client);
        QElapsedTimer   t;
        t.start();
        QVERIFY(!ambience.fetchNow(1000));
        QVERIFY(t.elapsed() < 1500);
        QDBusConnection::disconnectFromBus("client4");
    }

    void followsChangeSignals() {
        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell2");
        FakeAmbience    fake;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Ambience", &fake,
                                     QDBusConnection::ExportAllSlots |
                                         QDBusConnection::ExportAllSignals));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
        QDBusConnection client = QDBusConnection::connectToBus(address, "client2");
        AmbienceClient  ambience(client);
        QTest::qWait(200);
        emit fake.AmbienceChanged({{"/desktop/jolla/theme/color_scheme", "darkonlight"}});
        QTRY_COMPARE(ambience.ambience().value("/desktop/jolla/theme/color_scheme").toString(),
                     QStringLiteral("darkonlight"));
        shell.unregisterService("org.marathonos.Shell");
        QDBusConnection::disconnectFromBus("shell2");
        QDBusConnection::disconnectFromBus("client2");
    }
};

QTEST_MAIN(TestAmbienceClient)
#include "test_ambienceclient.moc"
