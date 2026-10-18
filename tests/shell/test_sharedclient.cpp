#include <QSignalSpy>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "taskmodel.h"

// Waydroid: one client maps a toplevel per Android app, and each app is
// launched by a separate, short-lived `waydroid app launch` process.
class FakeCompositor : public QObject {
    Q_OBJECT
  public:
    QList<int>       closed;
    QStringList      spawned;
    Q_INVOKABLE void launchApp(const QString &command) { spawned << command; }
    Q_INVOKABLE void closeWindow(int surfaceId) { closed << surfaceId; }
};

class FakeShell : public QObject {
    Q_OBJECT
  public:
    QStringList      shown;
    Q_INVOKABLE void show(const QVariant &id, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &surfaceId) {
        if (surfaceId.toInt() >= 0)
            shown << id.toString();
    }
    Q_INVOKABLE void openApp(const QVariant &, const QVariant &, const QVariant &) {}
    // UIStore's: an app is on screen.
    Q_PROPERTY(bool appWindowOpen MEMBER appWindowOpen)
    bool appWindowOpen = false;
};

class TestSharedClient : public QObject {
    Q_OBJECT

    // Above pid_max, so no such process exists to be signalled.
    static constexpr qint64 kClient  = 4194320;
    static constexpr qint64 kLaunchA = 4194321;
    static constexpr qint64 kLaunchB = 4194322;

    TaskModel           *tasks     = nullptr;
    AppLaunchService    *launcher  = nullptr;
    AppLifecycleManager *lifecycle = nullptr;
    FakeCompositor      *comp      = nullptr;
    FakeShell           *shell     = nullptr;
    QObject              surfaceA;
    QObject              surfaceB;
    QObject              windowA;
    QObject              windowB;

    static QString id(const QString &pkg) { return QStringLiteral("waydroid.") + pkg; }
    static QString exec(const QString &pkg) { return QStringLiteral("waydroid app launch ") + pkg; }
    static QVariantMap app(const QString &pkg) {
        return {{"id", id(pkg)}, {"name", pkg.toUpper()}, {"icon", pkg + ".png"},
                {"type", "native"}, {"exec", exec(pkg)}};
    }

    void launch(const QString &pkg, qint64 launcherPid) {
        QVERIFY(launcher->launchApp(app(pkg)));
        launcher->onCompositorAppLaunched(exec(pkg), launcherPid);
    }
    bool map(const QString &pkg, int surfaceId, QObject *surface) {
        return launcher->mapWindow(kClient, id(pkg), pkg + " (Android title)", QString(),
                                   surfaceId, surface);
    }
    // MarathonAppWindow registers each shown native window like this.
    void show(const QString &pkg, int surfaceId, QObject *window) {
        window->setProperty("surfaceId", surfaceId);
        window->setProperty("isNative", true);
        lifecycle->registerApp(id(pkg), window);
        lifecycle->bringToForeground(id(pkg));
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
        launcher->setAppLifecycleManager(lifecycle);
    }

    void cleanup() {
        delete lifecycle;
        delete launcher;
        delete tasks;
        delete comp;
        delete shell;
    }

    void eachToplevelIsItsLaunchsTask() {
        launch("a", kLaunchA);
        launch("b", kLaunchB);
        map("a", 11, &surfaceA);
        map("b", 12, &surfaceB);

        QCOMPARE(tasks->taskCount(), 2);
        QCOMPARE(tasks->getTaskByAppId(id("a"))->surfaceId(), 11);
        QCOMPARE(tasks->getTaskByAppId(id("b"))->surfaceId(), 12);
        QCOMPARE(tasks->getTaskByAppId(id("a"))->title(), QStringLiteral("A"));
        QCOMPARE(tasks->getTaskByAppId(id("b"))->title(), QStringLiteral("B"));
        QCOMPARE(shell->shown, (QStringList{id("a"), id("b")}));
    }

    void neitherProcessIsTheApps() {
        launch("a", kLaunchA);
        launch("b", kLaunchB);
        map("a", 11, &surfaceA);
        map("b", 12, &surfaceB);

        for (const QString &pkg : {QStringLiteral("a"), QStringLiteral("b")}) {
            QCOMPARE(launcher->pidForAppId(id(pkg)), -1);
            QCOMPARE(launcher->terminationPidForAppId(id(pkg)), -1);
        }
        QVERIFY(launcher->appIdForPid(kClient).isEmpty());
        QVERIFY(launcher->appIdForPid(kLaunchA).isEmpty());
        QVERIFY(launcher->appIdForPid(kLaunchB).isEmpty());
    }

    void theLauncherExitingLeavesTheWindow() {
        launch("a", kLaunchA);
        map("a", 11, &surfaceA);
        show("a", 11, &windowA);
        launcher->onCompositorAppClosed(kLaunchA);

        QVERIFY(tasks->getTaskByAppId(id("a")));
        QCOMPARE(lifecycle->lifecycleState(id("a")), int(AppLifecycleManager::Foreground));
    }

    void aSecondTapsLauncherToo() {
        launch("a", kLaunchA);
        launch("a", kLaunchB);
        map("a", 11, &surfaceA);
        launcher->onCompositorAppClosed(kLaunchB);
        launcher->onCompositorAppClosed(kLaunchA);

        QVERIFY(tasks->getTaskByAppId(id("a")));
    }

    void aBackgroundLaunchStaysBehind() {
        QVERIFY(launcher->startAppInBackground(app("a")));
        launcher->onCompositorAppLaunched(exec("a"), kLaunchA);
        map("a", 11, &surfaceA);

        QVERIFY(tasks->getTaskByAppId(id("a")));
        QVERIFY(shell->shown.isEmpty());
        QVERIFY(!launcher->isBackgroundLaunch(id("a")));
    }

    void closingOneClosesOnlyItsWindow() {
        launch("a", kLaunchA);
        launch("b", kLaunchB);
        map("a", 11, &surfaceA);
        map("b", 12, &surfaceB);
        show("a", 11, &windowA);
        show("b", 12, &windowB);

        lifecycle->closeApp(id("a"));

        QCOMPARE(comp->closed, QList<int>{11});
        QVERIFY(!tasks->getTaskByAppId(id("a")));
        QVERIFY(tasks->getTaskByAppId(id("b")));
        QCOMPARE(lifecycle->lifecycleState(id("b")), int(AppLifecycleManager::Foreground));
    }

    // Android started it (another app's link, `waydroid app launch` from a
    // terminal): it is a card, not the screen, while Home is shown.
    void anUnlaunchedWindowStaysBehindHome() {
        QVERIFY(!map("c", 31, &surfaceA));
        QVERIFY(tasks->getTaskByAppId(id("c")));
        QVERIFY(shell->shown.isEmpty());
    }

    // Not over another app either: Waydroid re-creates a task's window
    // whenever Android redraws it, and that must not take the front.
    void anUnlaunchedWindowNeverTakesTheFront() {
        shell->appWindowOpen = true;
        QVERIFY(!map("c", 31, &surfaceA));
        QVERIFY(shell->shown.isEmpty());
    }

    void aShownLaunchIsShown() {
        launch("a", kLaunchA);
        QVERIFY(map("a", 11, &surfaceA));
    }

    // `waydroid app launch` hands the launch to Android and exits; the
    // window comes after.
    void aLauncherExitingFirstIsNotTheAppsExit() {
        QSignalSpy exited(launcher, &AppLaunchService::appExited);
        launch("a", kLaunchA);
        launcher->onCompositorAppClosed(kLaunchA);
        QCOMPARE(exited.count(), 0);
        QVERIFY(map("a", 11, &surfaceA));
        QCOMPARE(tasks->getTaskByAppId(id("a"))->title(), QStringLiteral("A"));
    }

    void aBackgroundLaunchStaysBehindAfterItsLauncherExits() {
        QVERIFY(launcher->startAppInBackground(app("a")));
        launcher->onCompositorAppLaunched(exec("a"), kLaunchA);
        launcher->onCompositorAppClosed(kLaunchA);
        QVERIFY(!map("a", 11, &surfaceA));
        QVERIFY(shell->shown.isEmpty());
        QVERIFY(!launcher->isBackgroundLaunch(id("a")));
    }

    // No window came: the launch failed after all.
    void aLaunchWithNoWindowIsForgotten() {
        launcher->m_exitedLaunchGraceMs = 10;
        QSignalSpy exited(launcher, &AppLaunchService::appExited);
        QVERIFY(launcher->startAppInBackground(app("a")));
        launcher->onCompositorAppLaunched(exec("a"), kLaunchA);
        launcher->onCompositorAppClosed(kLaunchA);
        QTRY_COMPARE(exited.count(), 1);
        QVERIFY(!launcher->isBackgroundLaunch(id("a")));
        shell->appWindowOpen = false;
        QVERIFY(!map("a", 11, &surfaceA));
        QCOMPARE(tasks->getTaskByAppId(id("a"))->title(), QStringLiteral("a (Android title)"));
    }

    // The window can map before the shell has seen its launcher start.
    void aWindowBeforeItsLauncherStartedIsItsLaunchs() {
        QVERIFY(launcher->launchApp(app("a")));
        QVERIFY(map("a", 11, &surfaceA));
        QCOMPARE(tasks->getTaskByAppId(id("a"))->title(), QStringLiteral("A"));
        launcher->onCompositorAppLaunched(exec("a"), kLaunchA);
        QCOMPARE(launcher->pidForAppId(id("a")), -1);
    }

    // Two Android tasks of one package share an app_id.
    void theCardStaysWhileAWindowOfItsAppDoes() {
        QVERIFY(!map("b", 21, &surfaceA));
        QVERIFY(!map("b", 22, &surfaceB));
        QCOMPARE(tasks->taskCount(), 1);
        QCOMPARE(tasks->getTaskByAppId(id("b"))->surfaceId(), 22);

        launcher->onWindowDestroyed(22);
        QVERIFY(tasks->getTaskByAppId(id("b")));
        QCOMPARE(tasks->getTaskByAppId(id("b"))->surfaceId(), 21);
        QCOMPARE(tasks->getTaskByAppId(id("b"))->waylandSurface(), &surfaceA);

        launcher->m_windowGraceMs = 10;
        launcher->onWindowDestroyed(21);
        QVERIFY(tasks->getTaskByAppId(id("b")));
        QTRY_VERIFY(!tasks->getTaskByAppId(id("b")));
    }

    // Waydroid re-creates a window: the card keeps its place and takes the
    // new window, and nothing comes to the front.
    void aRecreatedWindowKeepsItsCard() {
        launch("a", kLaunchA);
        QVERIFY(map("a", 11, &surfaceA));
        QCOMPARE(shell->shown, QStringList{id("a")});
        launcher->onWindowDestroyed(11);
        QVERIFY(!map("a", 12, &surfaceB));
        QCOMPARE(tasks->getTaskByAppId(id("a"))->surfaceId(), 12);
        QCOMPARE(tasks->getTaskByAppId(id("a"))->title(), QStringLiteral("A"));
        QCOMPARE(shell->shown, QStringList{id("a")});
        QTest::qWait(50);
        QVERIFY(tasks->getTaskByAppId(id("a")));
    }

    void anOlderWindowGoingLeavesTheCardAlone() {
        QVERIFY(!map("b", 21, &surfaceA));
        QVERIFY(!map("b", 22, &surfaceB));
        launcher->onWindowDestroyed(21);
        QCOMPARE(tasks->getTaskByAppId(id("b"))->surfaceId(), 22);
    }

    // Its process may map another; the app window decides (NativeAppWindow).
    void anAppWithItsOwnProcessKeepsItsCard() {
        tasks->launchTask("plain", "Plain", "plain", "native", 20, &surfaceB);
        launcher->registerPidForAppId(4194330, "plain");
        launcher->mapWindow(4194330, "plain", "Plain", QString(), 20, &surfaceB);
        launcher->onWindowDestroyed(20);
        QVERIFY(tasks->getTaskByAppId("plain"));
    }

    // Waydroid hides Android's own apps (NoDisplay) from the grid; they
    // still launch by id (Navigation1.LaunchApp, a notification).
    void aHiddenDesktopEntryLaunchesById() {
        QTemporaryDir   data;
        const QByteArray old = qgetenv("XDG_DATA_HOME");
        qputenv("XDG_DATA_HOME", data.path().toUtf8());
        QVERIFY(QDir().mkpath(data.filePath("applications")));
        QFile entry(data.filePath("applications/waydroid.com.android.deskclock.desktop"));
        QVERIFY(entry.open(QIODevice::WriteOnly));
        entry.write("[Desktop Entry]\nType=Application\nName=Clock\n"
                    "Exec=waydroid app launch com.android.deskclock\nNoDisplay=true\n");
        entry.close();

        QVERIFY(launcher->launchApp(QVariant(id("com.android.deskclock"))));
        QTRY_COMPARE(comp->spawned, QStringList{exec("com.android.deskclock")});
        QVERIFY(!launcher->launchApp(QVariant(id("org.example.missing"))));
        qputenv("XDG_DATA_HOME", old);
    }

    // Freezing has nothing of the app's own to stop; a no-op Frozen app
    // would also be the one killOldestFrozenApp picks, and kill nothing.
    void anAppWithoutItsOwnProcessIsNotFrozen() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launch("a", kLaunchA);
        map("a", 11, &surfaceA);
        show("a", 11, &windowA);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(lifecycle->lifecycleState(id("a")), int(AppLifecycleManager::BackgroundIdle));

        QTest::qWait(5);
        constexpr qint64 kPlain = 4194330;
        tasks->launchTask("plain", "Plain", "plain", "native", 20, &surfaceB);
        launcher->registerPidForAppId(kPlain, "plain");
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(lifecycle->lifecycleState("plain"), int(AppLifecycleManager::Frozen));

        QCOMPARE(lifecycle->killOldestFrozenApp(), int(kPlain));
        QCOMPARE(lifecycle->lifecycleState(id("a")), int(AppLifecycleManager::BackgroundIdle));
    }
};

QTEST_GUILESS_MAIN(TestSharedClient)
#include "test_sharedclient.moc"
