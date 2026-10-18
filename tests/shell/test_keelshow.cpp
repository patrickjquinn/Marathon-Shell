#include <QTest>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QJsonDocument>
#include <QProcess>
#include <QTemporaryDir>

#include <csignal>

// The shell's Navigation1, as the runner's Keel host calls it to raise the app.
class FakeNavigation : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Navigation1")
  public:
    QStringList launched;

  public slots:
    bool LaunchApp(const QString &appId) {
        launched << appId;
        return true;
    }
};

static const char kApp[] = R"(import QtQuick
import Sailfish.Silica 1.0
import Keel.Actions 1.0

ApplicationWindow {
    id: app
    initialPage: Component { Page { objectName: "first" } }
    Component { id: second; Page { objectName: "second" } }
    KeelPage { name: "second"; description: "The second page."; onShow: app.pageStack.push(second, {}, PageStackAction.Immediate) }
    KeelAction {
        name: "fix.page"
        description: "The page on top."
        readOnly: true
        onInvoked: (args, call) => call.reply({ page: app.pageStack.currentPage.objectName, depth: app.pageStack.depth })
    }
}
)";

static const char kManifest[] = R"({"appId": "org.marathonos.kfix", "entities": [], "prompts": [], "tools": [
 {"name": "org.marathonos.kfix/app.show", "title": "Show", "description": "Show the app and one of its pages.",
  "_meta": {"org.shipwright.keel/action": "app.show", "org.shipwright.keel/result": "none"},
  "inputSchema": {"type": "object", "additionalProperties": false,
                  "properties": {"page": {"type": "string", "enum": ["second"]}}}},
 {"name": "org.marathonos.kfix/fix.page", "description": "The page on top.",
  "_meta": {"org.shipwright.keel/action": "fix.page", "org.shipwright.keel/result": "object"},
  "inputSchema": {"type": "object", "additionalProperties": false, "properties": {}},
  "outputSchema": {"type": "object", "properties": {"page": {"type": "string"}, "depth": {"type": "integer"}}}}
]})";

// app.show for an app that is not running: bus activation starts the real
// marathon-app-runner, and the call arrives while it loads the app.
// MARATHON_APP_RUNNER names the runner, KEEL_QML a Keel build's qml directory.
class TestKeelShow : public QObject {
    Q_OBJECT

    QTemporaryDir  dir;
    QProcess       daemon;
    QString        address;
    FakeNavigation navigation;

    void write(const QString &path, const QByteArray &data) {
        QVERIFY(QDir().mkpath(QFileInfo(dir.filePath(path)).path()));
        QFile f(dir.filePath(path));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(data);
    }

    QDBusMessage invoke(const QString &action, const QByteArray &arguments) {
        QDBusConnection bus = QDBusConnection::connectToBus(address, QStringLiteral("caller"));
        QDBusMessage    msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.marathonos.kfix"), QStringLiteral("/org/shipwright/Keel/Actions"),
            QStringLiteral("org.shipwright.Keel.Actions"), QStringLiteral("Invoke"));
        msg << action << QString::fromUtf8(arguments) << QVariantMap();
        QDBusPendingCall pending = bus.asyncCall(msg, 30000);
        QDeadlineTimer   deadline(30000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(20);
        return pending.reply();
    }

  private slots:
    void initTestCase() {
        const QString runner = qEnvironmentVariable("MARATHON_APP_RUNNER");
        const QString keel   = qEnvironmentVariable("KEEL_QML");
        QVERIFY2(!runner.isEmpty() && !keel.isEmpty(), "set MARATHON_APP_RUNNER and KEEL_QML");
        write("apps/kfix/manifest.json",
              R"({"id": "kfix", "name": "Kfix", "version": "1.0.0", "entryPoint": "KfixApp.qml", "icon": "icon.svg"})");
        write("apps/kfix/MarathonApp/Kfix/qmldir", "module MarathonApp.Kfix\nKfixApp 1.0 KfixApp.qml\n");
        write("apps/kfix/MarathonApp/Kfix/KfixApp.qml", kApp);
        write("share/keel/actions/org.marathonos.kfix.json", kManifest);
        write("services/org.marathonos.kfix.service",
              "[D-BUS Service]\nName=org.marathonos.kfix\nExec=" + runner.toUtf8() + " --app-id kfix\n");
        address = QStringLiteral("unix:path=") + dir.filePath("bus");
        write("session.conf",
              QStringLiteral("<busconfig><type>session</type><listen>%1</listen><servicedir>%2</servicedir>"
                             "<policy context=\"default\"><allow send_destination=\"*\"/>"
                             "<allow receive_sender=\"*\"/><allow own=\"*\"/></policy></busconfig>")
                  .arg(address, dir.filePath("services"))
                  .toUtf8());

        // The environment the runner is activated with.
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("DBUS_SESSION_BUS_ADDRESS", address);
        env.insert("MARATHON_APPS_DIR", dir.filePath("apps"));
        env.insert("XDG_DATA_DIRS", dir.filePath("share"));
        env.insert("XDG_RUNTIME_DIR", dir.path());
        env.insert("XDG_CACHE_HOME", dir.filePath("cache"));
        env.insert("QML_IMPORT_PATH", keel);
        env.insert("QT_QPA_PLATFORM", "offscreen");
        env.insert("MARATHON_SHELL_PID", QString::number(QCoreApplication::applicationPid()));
        daemon.setProcessEnvironment(env);
        daemon.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        daemon.start("dbus-daemon", {"--config-file=" + dir.filePath("session.conf"), "--nofork"});
        QVERIFY(daemon.waitForStarted(5000));
        QTRY_VERIFY(QFile::exists(dir.filePath("bus")));

        QDBusConnection shell = QDBusConnection::connectToBus(address, QStringLiteral("shell"));
        QVERIFY(shell.isConnected());
        QVERIFY(shell.registerObject(QStringLiteral("/org/marathonos/Shell/Navigation"), &navigation,
                                     QDBusConnection::ExportAllSlots));
        QVERIFY(shell.registerService(QStringLiteral("org.marathonos.Shell")));
    }

    void cleanupTestCase() {
        QDBusConnection bus = QDBusConnection::connectToBus(address, QStringLiteral("caller"));
        const auto      pid = bus.interface()->servicePid(QStringLiteral("org.marathonos.kfix"));
        if (pid.isValid() && pid.value() > 0)
            ::kill(pid.value(), SIGKILL);
        daemon.kill();
        daemon.waitForFinished();
    }

    // The page opens over the first one, and the app asks the shell to show it.
    void showStartsTheAppInFrontOnItsPage() {
        const QDBusMessage reply = invoke("app.show", R"({"page": "second"})");
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QTRY_COMPARE_WITH_TIMEOUT(navigation.launched, QStringList{"kfix"}, 10000);
        const QDBusMessage page = invoke("fix.page", "{}");
        QCOMPARE(page.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(QJsonDocument::fromJson(page.arguments().value(0).toString().toUtf8()).toVariant(),
                 QVariant(QVariantMap{{"page", "second"}, {"depth", 2}}));
    }
};

QTEST_GUILESS_MAIN(TestKeelShow)
#include "test_keelshow.moc"
