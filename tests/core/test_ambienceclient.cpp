// clazy:excludeall=const-signal-or-slot (D-Bus fakes: a getter is a slot to be exported)

#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QProcess>
#include <QTest>
#include <QThread>

#include "marathon-app-native/src/ambience.cxxqt.h"

// The shell's Ambience1, on its own thread because fetchNow blocks.
class FakeAmbience : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Ambience1")

  public:
    QVariantMap map;

  public slots:
    QVariantMap GetAmbience() const {
        return map;
    }
};

class TestAmbienceClient : public QObject {
    Q_OBJECT

    QProcess     daemon;
    QString      address;
    QThread      shellThread;
    FakeAmbience fake;

    QString highlight(const marathon::platform::Ambience &a) const {
        return a.getAmbience().value("/desktop/jolla/theme/color/highlight").toString();
    }

    void publish() {
        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Ambience", &fake,
                                     QDBusConnection::ExportAllSlots));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());
        fake.moveToThread(&shellThread);
        shellThread.start();
    }

    void cleanupTestCase() {
        shellThread.quit();
        shellThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }

    // A spare can start before the shell is up and miss its publish.
    void readsWhenTheShellAppearsLater() {
        fake.map = {{"/desktop/jolla/theme/color/highlight", "#759b97"}};
        marathon::platform::Ambience ambience;
        QElapsedTimer                t;
        t.start();
        QVERIFY(!ambience.fetchNow());
        QVERIFY(t.elapsed() < 1500);
        publish();
        QTRY_COMPARE(highlight(ambience), QStringLiteral("#759b97"));
    }

    void fetchNowAnswersWithoutTheEventLoop() {
        fake.map = {{"/desktop/jolla/theme/color/highlight", "#123456"}};
        marathon::platform::Ambience ambience;
        QVERIFY(ambience.fetchNow());
        QCOMPARE(highlight(ambience), QStringLiteral("#123456"));
    }

    void followsChangeSignals() {
        marathon::platform::Ambience ambience;
        QTest::qWait(200);
        QDBusMessage changed = QDBusMessage::createSignal(
            "/org/marathonos/Shell/Ambience", "org.marathonos.Shell.Ambience1", "AmbienceChanged");
        changed << QVariantMap{{"/desktop/jolla/theme/color/highlight", "#abcdef"}};
        QVERIFY(QDBusConnection(QStringLiteral("shell")).send(changed));
        QTRY_COMPARE(highlight(ambience), QStringLiteral("#abcdef"));
    }
};

QTEST_MAIN(TestAmbienceClient)
#include "test_ambienceclient.moc"
