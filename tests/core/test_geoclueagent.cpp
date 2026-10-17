#include <QtTest>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QProcess>
#include <QTemporaryDir>

#include "geoclueagent.h"

class FakeManager : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.GeoClue2.Manager")

  public:
    QStringList agents;

  public slots:
    void AddAgent(const QString &id) {
        agents << id;
    }
};

class TestGeoClueAgent : public QObject {
    Q_OBJECT

    QTemporaryDir dir;
    QProcess      daemon;
    QString       address;

    QDBusConnection startGeoClue(const QString &name, FakeManager &manager) {
        QDBusConnection conn = QDBusConnection::connectToBus(address, name);
        conn.registerObject("/org/freedesktop/GeoClue2/Manager", &manager,
                            QDBusConnection::ExportAllSlots);
        conn.registerService("org.freedesktop.GeoClue2");
        return conn;
    }

    // The agent answers from this thread's event loop, so the call can't block.
    QVariantList authorize(const QDBusConnection &agentBus, const QString &desktopId) {
        QDBusConnection caller = QDBusConnection::connectToBus(address, "caller");
        QDBusMessage    msg    = QDBusMessage::createMethodCall(
            agentBus.baseService(), "/org/freedesktop/GeoClue2/Agent",
            "org.freedesktop.GeoClue2.Agent", "AuthorizeApp");
        msg << desktopId << 4u;
        QDBusPendingCall call = caller.asyncCall(msg);
        QDeadlineTimer deadline(5000);
        while (!call.isFinished() && !deadline.hasExpired())
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        return call.reply().arguments();
    }

  private slots:
    void initTestCase() {
        const QString config = dir.filePath("bus.conf");
        QFile         c(config);
        QVERIFY(c.open(QIODevice::WriteOnly));
        c.write(QStringLiteral("<busconfig><type>session</type><listen>unix:tmpdir=%1</listen>"
                               "<policy context=\"default\"><allow send_destination=\"*\"/>"
                               "<allow receive_sender=\"*\"/><allow own=\"*\"/></policy>"
                               "</busconfig>")
                    .arg(dir.path())
                    .toUtf8());
        c.close();
        daemon.start("dbus-daemon", {"--config-file=" + config, "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        QVERIFY(!address.isEmpty());
    }

    void cleanupTestCase() {
        daemon.kill();
        daemon.waitForFinished();
    }

    void registersWithEachGeoClueThatStarts() {
        GeoClueAgent agent(QDBusConnection::connectToBus(address, "a1"),
                           [](const QString &) { return true; });
        QSignalSpy   registered(&agent, &GeoClueAgent::registered);
        for (int run = 1; run <= 2; ++run) {
            const QString   name = QStringLiteral("geoclue%1").arg(run);
            FakeManager     manager;
            QDBusConnection geoclue = startGeoClue(name, manager);
            QTRY_COMPARE(registered.count(), run);
            QCOMPARE(manager.agents, QStringList{GeoClueAgent::agentId()});
            // Idle GeoClue exits, forgetting its agents.
            QDBusConnection::disconnectFromBus(name);
        }
    }

    void registersWithAGeoClueAlreadyRunning() {
        FakeManager     manager;
        QDBusConnection geoclue = startGeoClue("geoclue3", manager);
        GeoClueAgent    agent(QDBusConnection::connectToBus(address, "a2"),
                              [](const QString &) { return true; });
        QTRY_COMPARE(manager.agents, QStringList{GeoClueAgent::agentId()});
        QDBusConnection::disconnectFromBus("geoclue3");
    }

    void answersWithTheAuthorizersVerdict() {
        QDBusConnection bus = QDBusConnection::connectToBus(address, "a3");
        GeoClueAgent    agent(bus, [](const QString &id) { return id == "marathon-weather"; });

        QCOMPARE(authorize(bus, "marathon-weather"), (QVariantList{true, 4u}));
        QCOMPARE(authorize(bus, "com.example.Tracker"), (QVariantList{false, 0u}));
    }
};

QTEST_GUILESS_MAIN(TestGeoClueAgent)
#include "test_geoclueagent.moc"
