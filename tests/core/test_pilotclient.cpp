#include <QtTest>
#include <QDBusConnection>
#include <QProcess>
#include <QTemporaryDir>

#include "pilotclient.h"

// A pilotd from before ShowSheetFor; FakeCurrentPilot has it.
class FakePilot : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Pilot1")

  public:
    QList<uint> sheetFor;
    int         sheets = 0;

  public slots:
    void ShowSheet() {
        ++sheets;
    }
};

class FakeCurrentPilot : public FakePilot {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Pilot1")

  public slots:
    QString ShowSheetFor(uint pid) {
        sheetFor << pid;
        return QString();
    }
};

class TestPilotClient : public QObject {
    Q_OBJECT

    QTemporaryDir dir;

    // A private session bus; with `activatable`, Pilot's service file is
    // installed in it.
    struct Bus {
        QProcess daemon;
        QString  address;
        ~Bus() {
            daemon.kill();
            daemon.waitForFinished();
        }
    };

    bool startBus(Bus &bus, bool activatable) {
        const QString services = dir.filePath(activatable ? "with" : "without");
        QDir().mkpath(services);
        if (activatable) {
            QFile f(services + "/org.shipwright.Pilot.service");
            if (!f.open(QIODevice::WriteOnly))
                return false;
            f.write("[D-BUS Service]\nName=org.shipwright.Pilot\nExec=/bin/false\n");
        }
        const QString config = services + ".conf";
        QFile         c(config);
        if (!c.open(QIODevice::WriteOnly))
            return false;
        c.write(QStringLiteral("<busconfig><type>session</type><listen>unix:tmpdir=%1</listen>"
                               "<servicedir>%2</servicedir><policy context=\"default\">"
                               "<allow send_destination=\"*\" eavesdrop=\"true\"/>"
                               "<allow eavesdrop=\"true\"/><allow own=\"*\"/></policy>"
                               "</busconfig>")
                    .arg(dir.path(), services)
                    .toUtf8());
        c.close();
        bus.daemon.start("dbus-daemon", {"--config-file=" + config, "--nofork", "--print-address"});
        if (!bus.daemon.waitForReadyRead(5000))
            return false;
        bus.address = QString::fromUtf8(bus.daemon.readLine()).trimmed();
        return !bus.address.isEmpty();
    }

  private slots:
    void activatableIsAvailable() {
        Bus bus;
        QVERIFY(startBus(bus, true));
        PilotClient client(QDBusConnection::connectToBus(bus.address, "a1"));
        QTRY_VERIFY(client.available());
    }

    void absentIsNot() {
        Bus bus;
        QVERIFY(startBus(bus, false));
        PilotClient client(QDBusConnection::connectToBus(bus.address, "b1"));
        QTest::qWait(300);
        QVERIFY(!client.available());
    }

    void followsARunningService() {
        Bus bus;
        QVERIFY(startBus(bus, false));
        PilotClient     client(QDBusConnection::connectToBus(bus.address, "c1"));
        QDBusConnection pilot = QDBusConnection::connectToBus(bus.address, "c2");
        QVERIFY(pilot.registerService(PilotClient::serviceName()));
        QTRY_VERIFY(client.available());
        QVERIFY(pilot.unregisterService(PilotClient::serviceName()));
        QTRY_VERIFY(!client.available());
    }

    void asksForTheAppOnScreen() {
        Bus bus;
        QVERIFY(startBus(bus, false));
        FakeCurrentPilot fake;
        QDBusConnection  pilot = QDBusConnection::connectToBus(bus.address, "d2");
        QVERIFY(pilot.registerObject("/org/shipwright/Pilot", &fake,
                                     QDBusConnection::ExportAllSlots));
        QVERIFY(pilot.registerService(PilotClient::serviceName()));
        PilotClient client(QDBusConnection::connectToBus(bus.address, "d1"));
        client.showSheetFor(4242);
        client.showSheetFor(0);
        QTRY_COMPARE(fake.sheetFor, (QList<uint>{4242, 0}));
        QTest::qWait(100);
        QCOMPARE(fake.sheets, 0);
    }

    void olderPilotGetsShowSheet() {
        Bus bus;
        QVERIFY(startBus(bus, false));
        FakePilot       fake;
        QDBusConnection pilot = QDBusConnection::connectToBus(bus.address, "e2");
        QVERIFY(pilot.registerObject("/org/shipwright/Pilot", &fake,
                                     QDBusConnection::ExportAllSlots));
        QVERIFY(pilot.registerService(PilotClient::serviceName()));
        PilotClient client(QDBusConnection::connectToBus(bus.address, "e1"));
        client.showSheetFor(7);
        QTRY_COMPARE(fake.sheets, 1);
    }

    void watchingPolls() {
        Bus bus;
        QVERIFY(startBus(bus, false));
        PilotClient client(QDBusConnection::connectToBus(bus.address, "f1"));
        QSignalSpy  spy(&client, &PilotClient::watchingChanged);
        client.setWatching(true);
        QVERIFY(client.watching());
        client.setWatching(true);
        client.setWatching(false);
        QVERIFY(!client.watching());
        QCOMPARE(spy.size(), 2);
    }
};

QTEST_GUILESS_MAIN(TestPilotClient)
#include "test_pilotclient.moc"
