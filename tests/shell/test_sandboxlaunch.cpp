#include <QTest>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>

#include "applaunchservice.h"
#include "taskmodel.h"

// The compositor as launchMarathonApp drives it.
class FakeCompositor : public QObject {
    Q_OBJECT
  public:
    QStringList      spawned;
    QStringList      opened;
    bool             socketsWork = true;
    QString          socketDir;
    Q_INVOKABLE void launchApp(const QString &command, const QVariantMap &) {
        spawned << command;
    }
    Q_INVOKABLE QString openSandboxSocket(const QString &appId, const QString &instanceId) {
        opened << appId;
        return socketsWork ? socketDir + QLatin1Char('/') + instanceId : QString();
    }
    Q_INVOKABLE void closeSandboxSocket(const QString &) {}
};

class FakeShell : public QObject {
    Q_OBJECT
  public:
    Q_INVOKABLE void show(const QVariant &, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &) {}
    Q_INVOKABLE void openApp(const QVariant &, const QVariant &, const QVariant &) {}
};

class TestSandboxLaunch : public QObject {
    Q_OBJECT

    QTemporaryDir      bin;
    QTemporaryDir      runtime;
    TaskModel         *tasks    = nullptr;
    AppLaunchService  *launcher = nullptr;
    FakeCompositor    *comp     = nullptr;
    FakeShell         *shell    = nullptr;

    static QVariantMap app(const QString &id, const QStringList &permissions,
                           const QStringList &modules = {}) {
        return {{"id", id},
                {"name", id},
                {"icon", id},
                {"type", "marathon"},
                {"exec", QString()},
                {"permissions", permissions},
                {"requiresQtModules", modules}};
    }

    QStringList launch(const QVariantMap &app) {
        if (!launcher->launchApp(app))
            return {};
        return QProcess::splitCommand(comp->spawned.value(0));
    }

    // The value after the first `--setenv name`, or a null string.
    static QString setenv(const QStringList &argv, const QString &name) {
        for (qsizetype i = 0; i + 2 < argv.size(); ++i) {
            if (argv[i] == QLatin1String("--setenv") && argv[i + 1] == name)
                return argv[i + 2];
        }
        return {};
    }

    static qsizetype indexOfTriple(const QStringList &argv, const QString &op, const QString &a,
                                   const QString &b = QString()) {
        for (qsizetype i = 0; i + 2 < argv.size(); ++i) {
            if (argv[i] == op && argv[i + 1] == a && (b.isNull() || argv[i + 2] == b))
                return i;
        }
        return -1;
    }

  private slots:
    void initTestCase() {
        QFile fake(bin.path() + QStringLiteral("/bwrap"));
        QVERIFY(fake.open(QIODevice::WriteOnly));
        fake.write("#!/bin/sh\n");
        fake.close();
        fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv("PATH", bin.path().toLocal8Bit());
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        qputenv("HOME", runtime.path().toLocal8Bit());
        qputenv("MARATHON_RUNNER_POOL", "0");
        qunsetenv("MARATHON_DISABLE_SANDBOX");
        qunsetenv("MARATHON_WL_SOCKET_NAME");
        qunsetenv("QTWEBENGINE_CHROMIUM_FLAGS");
    }

    void init() {
        tasks           = new TaskModel(this);
        launcher        = new AppLaunchService(nullptr, tasks, this);
        comp            = new FakeCompositor;
        comp->socketDir = runtime.path() + QStringLiteral("/marathon-sandbox");
        shell           = new FakeShell;
        launcher->setCompositor(comp);
        launcher->setAppWindow(shell);
        launcher->setUiStore(shell);
    }

    void cleanup() {
        delete launcher;
        delete tasks;
        delete comp;
        delete shell;
    }

    // The app reaches the compositor only through its own socket, mounted
    // over the shell's, with every sandbox's socket hidden.
    void connectsThroughItsSecurityContextSocket() {
        const QStringList argv = launch(app("notes", {}));
        QVERIFY(!argv.isEmpty());
        QCOMPARE(comp->opened, QStringList{"notes"});

        const QString   runtimeDir = runtime.path();
        const qsizetype runtimeBind =
            indexOfTriple(argv, QStringLiteral("--bind"), runtimeDir, runtimeDir);
        qsizetype socketAt = -1;
        for (qsizetype i = 0; i + 2 < argv.size(); ++i) {
            if (argv[i] == QLatin1String("--ro-bind") &&
                argv[i + 1].startsWith(comp->socketDir + QLatin1Char('/')))
                socketAt = i;
        }
        QVERIFY(runtimeBind >= 0);
        QVERIFY(socketAt > runtimeBind);
        QCOMPARE(argv[socketAt + 2], runtimeDir + QStringLiteral("/marathon-wayland-0"));
        QVERIFY(indexOfTriple(argv, QStringLiteral("--tmpfs"), comp->socketDir) > socketAt);
        QCOMPARE(setenv(argv, QStringLiteral("WAYLAND_DISPLAY")),
                 QStringLiteral("marathon-wayland-0"));
    }

    void refusesToLaunchWithoutASocket() {
        comp->socketsWork = false;
        QVERIFY(!launcher->launchApp(app("notes", {})));
        QVERIFY(comp->spawned.isEmpty());
    }

    void appsWithoutNetworkGetNoNetwork() {
        const QStringList argv = launch(app("notes", {}));
        QVERIFY(argv.contains(QStringLiteral("--unshare-net")));
        QVERIFY(argv.contains(QStringLiteral("--unshare-pid")));
    }

    // Chromium's sandbox nests inside bwrap, so WebEngine apps keep both.
    void webEngineAppsKeepBothSandboxes() {
        const QStringList argv =
            launch(app("browser", {QStringLiteral("network")}, {QStringLiteral("webengine")}));
        QVERIFY(!argv.isEmpty());
        QVERIFY(argv.contains(QStringLiteral("--unshare-pid")));
        QVERIFY(argv.contains(QStringLiteral("--unshare-user-try")));
        QVERIFY(argv.contains(QStringLiteral("--unshare-ipc")));
        QVERIFY(!argv.contains(QStringLiteral("--unshare-net")));
        const QString flags = setenv(argv, QStringLiteral("QTWEBENGINE_CHROMIUM_FLAGS"));
        QVERIFY(!flags.isEmpty());
        QVERIFY(!flags.contains(QStringLiteral("--no-sandbox")));
        QVERIFY(setenv(argv, QStringLiteral("QTWEBENGINE_DISABLE_SANDBOX")).isNull());
    }
};

QTEST_MAIN(TestSandboxLaunch)
#include "test_sandboxlaunch.moc"
