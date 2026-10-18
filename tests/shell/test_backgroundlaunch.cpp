#include <QTest>

#include "applaunchservice.h"
#include "marathonapppaths.h"
#include "applifecyclemanager.h"
#include "taskmodel.h"

// The compositor, app window and UIStore as AppLaunchService calls them.
class FakeCompositor : public QObject {
    Q_OBJECT
  public:
    QStringList spawned;
    Q_INVOKABLE void launchApp(const QString &command) { spawned << command; }
};

class FakeShell : public QObject {
    Q_OBJECT
  public:
    QVariantList shown;
    QStringList  opened;
    Q_INVOKABLE void show(const QVariant &id, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &) {
        shown << id;
    }
    Q_INVOKABLE void openApp(const QVariant &id, const QVariant &, const QVariant &) {
        opened << id.toString();
    }
};

class TestBackgroundLaunch : public QObject {
    Q_OBJECT

    TaskModel           *tasks     = nullptr;
    AppLaunchService    *launcher  = nullptr;
    AppLifecycleManager *lifecycle = nullptr;
    FakeCompositor      *comp      = nullptr;
    FakeShell           *shell     = nullptr;

    static QVariantMap app(const QString &id) {
        return {{"id", id}, {"name", id}, {"icon", id}, {"type", "native"}, {"exec", id + "-bin"}};
    }

  private slots:
    void init() {
        tasks     = new TaskModel(this);
        launcher  = new AppLaunchService(nullptr, tasks, this);
        lifecycle = new AppLifecycleManager(tasks, launcher, this);
        comp      = new FakeCompositor;
        shell     = new FakeShell;
        launcher->setCompositor(comp);
        launcher->setAppWindow(shell);
        launcher->setUiStore(shell);
    }

    void cleanup() {
        delete lifecycle;
        delete launcher;
        delete tasks;
        delete comp;
        delete shell;
    }

    void startsWithoutShowing() {
        QVERIFY(launcher->startAppInBackground(app("pilot")));
        QCOMPARE(comp->spawned, QStringList{"pilot-bin"});
        QVERIFY(shell->shown.isEmpty());
        QVERIFY(shell->opened.isEmpty());
        QVERIFY(launcher->isBackgroundLaunch("pilot"));
    }

    void leavesTheFrontAppInFront() {
        QVERIFY(launcher->launchApp(app("front")));
        launcher->registerPidForAppId(4194301, "front");
        QCOMPARE(lifecycle->lifecycleState("front"), int(AppLifecycleManager::Foreground));

        QVERIFY(launcher->startAppInBackground(app("pilot")));
        launcher->registerPidForAppId(4194302, "pilot");
        QCOMPARE(lifecycle->lifecycleState("pilot"), int(AppLifecycleManager::BackgroundIdle));
        QCOMPARE(lifecycle->lifecycleState("front"), int(AppLifecycleManager::Foreground));
    }

    void launchWhileStartingShowsIt() {
        QVERIFY(launcher->startAppInBackground(app("pilot")));
        QVERIFY(launcher->launchApp(app("pilot")));
        QCOMPARE(comp->spawned.size(), 1);
        QCOMPARE(shell->shown, QVariantList{"pilot"});
        QCOMPARE(shell->opened, QStringList{"pilot"});
        QVERIFY(!launcher->isBackgroundLaunch("pilot"));
    }

    void leavesARunningAppAlone() {
        launcher->registerPidForAppId(4194303, "pilot");
        QVERIFY(launcher->startAppInBackground(app("pilot")));
        QVERIFY(comp->spawned.isEmpty());
        QVERIFY(!launcher->isBackgroundLaunch("pilot"));
    }

    // The window matched the sandbox's inner runner, so the app's pid was
    // that child's; when the sandbox exits the app must be gone, or the next
    // background start answers true and starts nothing.
    void sandboxExitForgetsItsChild() {
        QVERIFY(launcher->startAppInBackground(app("pilot")));
        launcher->onCompositorAppLaunched("pilot-bin", 4194310);
        launcher->registerPidForAppId(4194311, "pilot");
        launcher->onCompositorAppClosed(4194310);
        QCOMPARE(launcher->pidForAppId("pilot"), -1);
        QVERIFY(launcher->appIdForPid(4194311).isEmpty());
        QVERIFY(launcher->startAppInBackground(app("pilot")));
        QCOMPARE(comp->spawned.size(), 2);
    }

    // A user-installed app sees its code read-only, never through the
    // writable data directory; a system app that lists apps sees them all.
    void installedCodeIsBoundReadOnly() {
        QTemporaryDir   home;
        const QByteArray oldHome = qgetenv("HOME");
        qputenv("HOME", home.path().toUtf8());
        qunsetenv("XDG_DATA_HOME");
        qputenv("MARATHON_APPS_DIR", (home.path() + "/system").toUtf8());
        QVERIFY(QDir().mkpath(MarathonAppPaths::installDir("com.example.app")));
        QFile receipt(MarathonAppPaths::receiptPath("com.example.app"));
        QVERIFY(receipt.open(QIODevice::WriteOnly));
        receipt.close();
        QVERIFY(QDir().mkpath(home.path() + "/system/settings"));
        QFile manifest(home.path() + "/system/settings/manifest.json");
        QVERIFY(manifest.open(QIODevice::WriteOnly));
        manifest.close();

        const QString install = MarathonAppPaths::installDir("com.example.app");
        QVERIFY(AppLaunchService::isUserInstalled("com.example.app"));
        QCOMPARE(AppLaunchService::installBinds("com.example.app", {"system"}),
                 QStringList({"--ro-bind", install, install}));
        QVERIFY(!install.startsWith(MarathonAppPaths::dataDir("com.example.app")));

        const QString all = MarathonAppPaths::userInstalls();
        QVERIFY(!AppLaunchService::isUserInstalled("settings"));
        QCOMPARE(AppLaunchService::installBinds("settings", {"system"}),
                 QStringList({"--ro-bind-try", all, all}));
        QVERIFY(AppLaunchService::installBinds("calculator", {}).isEmpty());

        qputenv("HOME", oldHome);
        qunsetenv("MARATHON_APPS_DIR");
    }
};

QTEST_GUILESS_MAIN(TestBackgroundLaunch)
#include "test_backgroundlaunch.moc"
