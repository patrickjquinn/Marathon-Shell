#include <QtTest>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QProcess>
#include <QTemporaryDir>

// What a Keel app serves, once it is up.
class FakeActions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Keel.Actions")
  public slots:
    QString Describe() {
        return QStringLiteral("{}");
    }
};

// The shell's Navigation1: a started app takes its name a moment later.
class FakeNavigation : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Navigation1")
  public:
    QString     address;
    QStringList started;
    FakeActions actions;

  public slots:
    bool StartAppInBackground(const QString &appId) {
        started << appId;
        if (appId != QLatin1String("notes"))
            return false;
        QTimer::singleShot(300, this, [this, appId]() {
            QDBusConnection app = QDBusConnection::connectToBus(address, QStringLiteral("app"));
            app.registerObject(QStringLiteral("/org/shipwright/Keel/Actions"), &actions,
                               QDBusConnection::ExportAllSlots);
            app.registerService(QStringLiteral("org.marathonos.") + appId);
        });
        return true;
    }
};

// Bus activation of org.marathonos.<app> through the generated activation
// file and marathon-activate, on a private dbus-daemon (which runs Exec=; the
// device's dbus-broker runs SystemdService=, the same script).
class TestKeelActivation : public QObject {
    Q_OBJECT

    QTemporaryDir  dir;
    QProcess       daemon;
    QString        address;
    FakeNavigation navigation;

    QDBusMessage   describe(const QString &app) {
        QDBusConnection bus = QDBusConnection::connectToBus(address, QStringLiteral("caller"));
        QDBusPendingCall pending = bus.asyncCall(
            QDBusMessage::createMethodCall(app, QStringLiteral("/org/shipwright/Keel/Actions"),
                                           QStringLiteral("org.shipwright.Keel.Actions"),
                                           QStringLiteral("Describe")),
            30000);
        QDeadlineTimer deadline(30000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(20);
        return pending.reply();
    }

  private slots:
    void initTestCase() {
        QFile config(dir.filePath("session.conf"));
        QVERIFY(config.open(QIODevice::WriteOnly));
        config.write(QStringLiteral("<busconfig><type>session</type>"
                                    "<listen>unix:tmpdir=/tmp</listen>"
                                    "<servicedir>%1</servicedir>"
                                    "<policy context=\"default\"><allow send_destination=\"*\"/><allow receive_sender=\"*\"/>"
                                    "<allow own=\"*\"/></policy></busconfig>")
                         .arg(QStringLiteral(SERVICES_DIR))
                         .toUtf8());
        config.close();
        daemon.start("dbus-daemon", {"--config-file=" + config.fileName(), "--nofork",
                                     "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
        QVERIFY(address.startsWith(QLatin1String("unix:")));
        navigation.address = address;

        QDBusConnection shell = QDBusConnection::connectToBus(address, QStringLiteral("shell"));
        QVERIFY(shell.registerObject(QStringLiteral("/org/marathonos/Shell/Navigation"),
                                     &navigation, QDBusConnection::ExportAllSlots));
        QVERIFY(shell.registerService(QStringLiteral("org.marathonos.Shell")));
    }

    void cleanupTestCase() {
        daemon.kill();
        daemon.waitForFinished();
    }

    void aCallStartsTheAppAndIsDelivered() {
        const QDBusMessage reply = describe("org.marathonos.notes");
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(reply.arguments().value(0).toString(), QStringLiteral("{}"));
        QCOMPARE(navigation.started, QStringList{"notes"});
    }

    void aRefusedStartFailsTheCall() {
        const QDBusMessage reply = describe("org.marathonos.refused");
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QCOMPARE(navigation.started.last(), QStringLiteral("refused"));
    }

    void anAppWithoutActionsIsNotActivatable() {
        const QDBusMessage reply = describe("org.marathonos.plain");
        QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.ServiceUnknown"));
    }
};

QTEST_GUILESS_MAIN(TestKeelActivation)
#include "test_keelactivation.moc"
