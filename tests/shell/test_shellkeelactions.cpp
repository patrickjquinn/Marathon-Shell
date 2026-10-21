#include <QTest>
#include <QSignalSpy>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>

#include "marathon-shell-native/src/apps.cxxqt.h"
#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "marathon-shell-native/src/display.cxxqt.h"
#include "ipc/shellkeelactions.h"
#include "sessionstore.h"
#include "taskmodel.h"
#include "uistore.h"

class FakeCompositor : public QObject {
    Q_OBJECT
  public:
    QStringList      spawned;
    Q_INVOKABLE void launchApp(const QString &command) {
        spawned << command;
    }
};

class FakeShell : public QObject {
    Q_OBJECT
  public:
    Q_INVOKABLE void show(const QVariant &, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &) {}
    Q_INVOKABLE void openApp(const QVariant &, const QVariant &, const QVariant &) {}
};

// org.shipwright.Keel.Actions on org.marathonos.shell, on a private bus.
class TestShellKeelActions : public QObject {
    Q_OBJECT

    Apps                apps;
    TaskModel               tasks;
    AppLaunchService        launcher{&apps, &tasks};
    AppLifecycleManager     lifecycle{&tasks, &launcher};
    UIStore                 ui;
    SessionStore            session;
    marathon::Display                 display;
    FakeCompositor          compositor;
    FakeShell               shell;
    ShellKeelActions        actions{&apps, &tasks, &launcher, &lifecycle, &ui, &session, &display};

    static QDBusMessage     call(const QString &method, const QVariantList &args) {
        QDBusConnection bus =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("caller"));
        QDBusMessage message = QDBusMessage::createMethodCall(
            QStringLiteral("org.marathonos.shell"), QStringLiteral("/org/shipwright/Keel/Actions"),
            QStringLiteral("org.shipwright.Keel.Actions"), method);
        message.setArguments(args);
        QDBusPendingCall pending = bus.asyncCall(message, 5000);
        QDeadlineTimer   deadline(5000);
        while (!pending.isFinished() && !deadline.hasExpired())
            QTest::qWait(10);
        return pending.reply();
    }

    static QDBusMessage invoke(const QString &action, const QString &arguments) {
        return call(QStringLiteral("Invoke"), {action, arguments, QVariantMap()});
    }

    static QJsonObject result(const QDBusMessage &reply) {
        return QJsonDocument::fromJson(reply.arguments().value(0).toString().toUtf8()).object();
    }

    static QString error(const QDBusMessage &reply) {
        return reply.errorName().section(QLatin1Char('.'), -1);
    }

  private slots:
    void initTestCase() {
        launcher.setCompositor(&compositor);
        launcher.setAppWindow(&shell);
        launcher.setUiStore(&shell);
        apps.addApps({QVariantMap{{"id", "notes"}, {"name", "Notes"}, {"icon", "notes"},
                                  {"type", "native"}, {"exec", "notes-bin"}}});
        session.setIsLocked(false);
        QVERIFY(actions.registerOnSessionBus());
    }

    void describeServesTheManifest() {
        const QJsonObject manifest = result(call(QStringLiteral("Describe"), {}));
        QCOMPARE(manifest.value("appId").toString(), QStringLiteral("org.marathonos.shell"));
        QCOMPARE(manifest.value("tools").toArray().size(), 9);
    }

    void stateIsRead() {
        const QDBusMessage reply = invoke(QStringLiteral("shell.state"), QStringLiteral("{}"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(result(reply),
                 QJsonObject({{"locked", false},
                              {"screenOn", true},
                              {"foregroundApp", ""},
                              {"quickSettingsOpen", false}}));
    }

    void appsAreListed() {
        const QJsonObject list = result(invoke(QStringLiteral("apps.list"), QStringLiteral("{}")));
        QCOMPARE(list.value("result").toArray(),
                 QJsonArray({QJsonObject{{"id", "notes"}, {"name", "Notes"}}}));
    }

    void launchStartsTheApp() const {
        const QDBusMessage reply =
            invoke(QStringLiteral("app.launch"), QStringLiteral(R"({"id":"notes"})"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(compositor.spawned, QStringList{"notes-bin"});
    }

    void aHiddenAppLaunches() const {
        QTemporaryDir    data;
        const QByteArray old = qgetenv("XDG_DATA_HOME");
        qputenv("XDG_DATA_HOME", data.path().toUtf8());
        QVERIFY(QDir().mkpath(data.filePath("applications")));
        QFile entry(data.filePath("applications/hidden.desktop"));
        QVERIFY(entry.open(QIODevice::WriteOnly));
        entry.write("[Desktop Entry]\nType=Application\nName=Hidden\nExec=hidden-bin\nNoDisplay=true\n");
        entry.close();

        const QDBusMessage reply =
            invoke(QStringLiteral("app.launch"), QStringLiteral(R"({"id":"hidden"})"));
        qputenv("XDG_DATA_HOME", old);
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QVERIFY(compositor.spawned.contains(QStringLiteral("hidden-bin")));
    }

    void argumentsAreChecked_data() {
        QTest::addColumn<QString>("action");
        QTest::addColumn<QString>("arguments");
        QTest::addColumn<QString>("error");
        QTest::newRow("missing") << "app.launch" << "{}" << "InvalidArguments";
        QTest::newRow("unknown") << "app.launch" << R"({"id":"notes","x":"y"})"
                                 << "InvalidArguments";
        QTest::newRow("not a string") << "app.launch" << R"({"id":5})" << "InvalidArguments";
        QTest::newRow("too long") << "app.launch"
                                  << QStringLiteral(R"({"id":"%1"})").arg(QString(257, 'a'))
                                  << "InvalidArguments";
        QTest::newRow("not installed") << "app.launch" << R"({"id":"nope"})"
                                       << "InvalidArguments";
        QTest::newRow("not open") << "app.close" << R"({"id":"notes"})" << "InvalidArguments";
        QTest::newRow("not json") << "shell.state" << "[" << "InvalidArguments";
        QTest::newRow("no such action") << "shell.reboot" << "{}" << "UnknownAction";
    }

    void argumentsAreChecked() const {
        QFETCH(QString, action);
        QFETCH(QString, arguments);
        QFETCH(QString, error);
        const int          spawned = compositor.spawned.size();
        const QDBusMessage reply   = invoke(action, arguments);
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QCOMPARE(TestShellKeelActions::error(reply), error);
        QCOMPARE(compositor.spawned.size(), spawned);
    }

    void closeClosesTheTask() {
        tasks.launchTask(QStringLiteral("notes"), QStringLiteral("Notes"), QString(),
                         QStringLiteral("marathon"));
        const QJsonArray open = result(invoke(QStringLiteral("apps.running"), QStringLiteral("{}")))
                                    .value("result")
                                    .toArray();
        QCOMPARE(open, QJsonArray({QJsonObject{{"id", "notes"}, {"name", "Notes"}}}));
        const QDBusMessage reply =
            invoke(QStringLiteral("app.close"), QStringLiteral(R"({"id":"notes"})"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(tasks.rowCount(), 0);
    }

    void switcherAsksTheShell() {
        QSignalSpy home(&launcher, &AppLaunchService::homeRequested);
        QCOMPARE(invoke(QStringLiteral("shell.switcher"), QStringLiteral("{}")).type(),
                 QDBusMessage::ReplyMessage);
        QCOMPARE(home.size(), 1);
        QCOMPARE(home.first().first().toBool(), true);
    }

    void lockedRefusesChanges() {
        session.setIsLocked(true);
        const QDBusMessage launch =
            invoke(QStringLiteral("app.launch"), QStringLiteral(R"({"id":"notes"})"));
        QCOMPARE(error(launch), QStringLiteral("NotAvailable"));
        QCOMPARE(result(invoke(QStringLiteral("shell.state"), QStringLiteral("{}")))
                     .value("locked")
                     .toBool(),
                 true);
        session.setIsLocked(false);
    }

    // A process the shell started is one of its apps.
    void appsAreRefused() {
        const QString target = QStringLiteral("org.marathonos.shell");
        const QString path   = QStringLiteral("/org/shipwright/Keel/Actions");
        const QString iface  = QStringLiteral("org.shipwright.Keel.Actions");
        QProcess      app;
        app.start(
            QStringLiteral("busctl"),
            {"--user", "call", target, path, iface, "Invoke", "ssa{sv}", "shell.state", "{}", "0"});
        QTRY_COMPARE_WITH_TIMEOUT(app.state(), QProcess::NotRunning, 10000);
        QVERIFY(app.exitCode() != 0);
        const QByteArray refusal = app.readAllStandardError();
        QVERIFY2(refusal.contains("Access denied"), refusal.constData());

        app.start(QStringLiteral("busctl"), {"--user", "call", target, path, iface, "Describe"});
        QTRY_COMPARE_WITH_TIMEOUT(app.state(), QProcess::NotRunning, 10000);
        QCOMPARE(app.exitCode(), 0);
    }
};

QTEST_GUILESS_MAIN(TestShellKeelActions)
#include "test_shellkeelactions.moc"
