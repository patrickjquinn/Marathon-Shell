#include <QTest>
#include <QSignalSpy>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QTimer>

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "taskmodel.h"

// The user manager's Manager interface, as the shell calls it.
class FakeSystemd : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.systemd1.Manager")

  public:
    QStringList calls;

  public slots:
    void FreezeUnit(const QString &unit) {
        calls << "Freeze " + unit;
    }
    void ThawUnit(const QString &unit) {
        calls << "Thaw " + unit;
    }
    // Waydroid's session unit owns id.waydro.Session once it runs.
    QDBusObjectPath StartUnit(const QString &unit, const QString &mode) {
        calls << "Start " + unit + " " + mode;
        if (unit == QLatin1String("marathon-waydroid.service"))
            QTimer::singleShot(100, this, []() {
                QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                              QStringLiteral("waydroid"))
                    .registerService(QStringLiteral("id.waydro.Session"));
            });
        return QDBusObjectPath(QStringLiteral("/org/freedesktop/systemd1/job/1"));
    }
};

// WaylandCompositor's native back and forward, as the lifecycle calls them.
class FakeCompositor : public QObject {
    Q_OBJECT

  public:
    QStringList      sent;
    QStringList      spawned;
    Q_INVOKABLE void launchApp(const QString &command) {
        spawned << command;
    }
    Q_INVOKABLE void sendNativeBack(int surfaceId, bool keelHosted) {
        sent << QStringLiteral("back %1 %2").arg(surfaceId).arg(keelHosted);
    }
    Q_INVOKABLE void sendNativeForward(int surfaceId, bool keelHosted) {
        sent << QStringLiteral("forward %1 %2").arg(surfaceId).arg(keelHosted);
    }
};

// The app window and UIStore, as AppLaunchService calls them.
class FakeShell : public QObject {
    Q_OBJECT

  public:
    QStringList      shown;
    Q_INVOKABLE void show(const QVariant &id, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &) {
        shown << id.toString();
    }
    Q_INVOKABLE void openApp(const QVariant &, const QVariant &, const QVariant &) {}
};

// A running GApplication with no window.
class FakeApplication : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")

  public:
    int activated = 0;

  public slots:
    void Activate(const QVariantMap &) {
        ++activated;
    }
};

class ScopedLifecycle : public AppLifecycleManager {
  public:
    using AppLifecycleManager::AppLifecycleManager;
    QHash<qint64, QString> cgroups;

  protected:
    QString cgroupOfPid(qint64 pid) const override {
        return cgroups.value(pid);
    }
};

class TestNativeLifecycle : public QObject {
    Q_OBJECT

    TaskModel              *tasks     = nullptr;
    AppLaunchService       *launcher  = nullptr;
    ScopedLifecycle        *lifecycle = nullptr;
    FakeSystemd            *systemd   = nullptr;

    static constexpr qint64 kPid  = 4194301;
    const QString           radio = QStringLiteral("de.example.Radio");
    const QString           scope = QStringLiteral("app-flatpak-de.example.Radio-9.scope");
    const QString scoped = QStringLiteral("/user.slice/user-1000.slice/user@1000.service/app.slice/"
                                          "app-flatpak-de.example.Radio-9.scope");

    // In front with a mapped window, as a native app's first surface leaves it.
    void open(const QString &cgroup) {
        lifecycle->cgroups.insert(kPid, cgroup);
        launcher->registerPidForAppId(kPid, radio);
        tasks->launchTask(radio, radio, QString(), QStringLiteral("native"), 7);
    }

    // A native window in front, as MarathonAppWindow registers it.
    void showWindow(QObject *window, int surfaceId) {
        window->setProperty("isNative", true);
        window->setProperty("surfaceId", surfaceId);
        lifecycle->registerApp(radio, window);
        lifecycle->bringToForeground(radio);
    }

    int state() const {
        return lifecycle->lifecycleState(radio);
    }

  private slots:
    void init() {
        tasks     = new TaskModel(this);
        launcher  = new AppLaunchService(nullptr, tasks, this);
        lifecycle = new ScopedLifecycle(tasks, launcher, this);
        launcher->setAppLifecycleManager(lifecycle);
        lifecycle->setIdleFreezeDebounceMs(10);

        systemd = new FakeSystemd;
        QDBusConnection bus =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("systemd"));
        QVERIFY(bus.registerObject(QStringLiteral("/org/freedesktop/systemd1"), systemd,
                                   QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerService(QStringLiteral("org.freedesktop.systemd1")));
    }

    void cleanup() {
        QDBusConnection::disconnectFromBus(QStringLiteral("systemd"));
        delete lifecycle;
        delete launcher;
        delete tasks;
        delete systemd;
    }

    void freezesAnIdleAppsScope() {
        open(scoped);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(state(), int(AppLifecycleManager::Frozen));
        QTRY_COMPARE(systemd->calls, QStringList{"Freeze " + scope});
    }

    void thawsItInFront() {
        open(scoped);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(state(), int(AppLifecycleManager::Frozen));

        QObject window;
        window.setProperty("isNative", true);
        lifecycle->registerApp(radio, &window);
        lifecycle->bringToForeground(radio);
        QCOMPARE(state(), int(AppLifecycleManager::Foreground));
        QTRY_COMPARE(systemd->calls, (QStringList{"Freeze " + scope, "Thaw " + scope}));
        lifecycle->unregisterApp(radio);
    }

    void thawsItBeforeClosing() {
        open(scoped);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(state(), int(AppLifecycleManager::Frozen));
        lifecycle->closeApp(radio);
        QTRY_COMPARE(systemd->calls, (QStringList{"Freeze " + scope, "Thaw " + scope}));
    }

    void keepsAPlayingAppRunning() {
        open(scoped);
        lifecycle->addCapability(radio, QStringLiteral("audio-playback"));
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(state(), int(AppLifecycleManager::BackgroundActive));
        QTest::qWait(100);
        QCOMPARE(state(), int(AppLifecycleManager::BackgroundActive));
        QVERIFY(systemd->calls.isEmpty());
    }

    // A process the shell started itself shares the shell's cgroup; freezing
    // that through systemd would freeze the shell.
    void backGoesToTheWindow() {
        FakeCompositor comp;
        launcher->setCompositor(&comp);
        QObject window;
        showWindow(&window, 7);
        QVERIFY(lifecycle->handleSystemBack());
        QVERIFY(lifecycle->handleSystemForward());
        QCOMPARE(comp.sent, (QStringList{"back 7 0", "forward 7 0"}));
        lifecycle->unregisterApp(radio);
        launcher->setCompositor(nullptr);
    }

    void backWithoutAWindowIsUnhandled() {
        FakeCompositor comp;
        launcher->setCompositor(&comp);
        QObject window;
        showWindow(&window, -1);
        QVERIFY(!lifecycle->handleSystemBack());
        QVERIFY(comp.sent.isEmpty());
        lifecycle->unregisterApp(radio);
        launcher->setCompositor(nullptr);
    }

    // Only the window still in front leaves; the user may have moved on.
    void unhandledBackLeavesTheFrontApp() {
        QObject window;
        showWindow(&window, 7);
        QSignalSpy leave(lifecycle, &AppLifecycleManager::systemBackUnhandled);
        emit       launcher->nativeBackUnhandled(9);
        QCOMPARE(leave.count(), 0);
        emit launcher->nativeBackUnhandled(7);
        QCOMPARE(leave.count(), 1);
        QVERIFY(lifecycle->minimizeForegroundApp());
        emit launcher->nativeBackUnhandled(7);
        QCOMPARE(leave.count(), 1);
        lifecycle->unregisterApp(radio);
    }

    void activatesARunningAppWithoutAWindow() {
        FakeApplication app;
        QDBusConnection bus =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("app"));
        QVERIFY(bus.registerObject(QStringLiteral("/de/example/Radio"), &app,
                                   QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerService(radio));
        FakeCompositor comp;
        FakeShell      shell;
        launcher->setCompositor(&comp);
        launcher->setAppWindow(&shell);
        launcher->registerPidForAppId(kPid, radio);

        QVERIFY(launcher->launchApp(QVariantMap{
            {"id", radio}, {"name", "Radio"}, {"type", "flatpak"}, {"exec", "FLATPAK:radio"}}));
        QTRY_COMPARE(app.activated, 1);
        QTRY_COMPARE(shell.shown, QStringList{radio});
        QVERIFY(comp.spawned.isEmpty());
        QVERIFY(!launcher->isAppLaunching(radio));
        launcher->setCompositor(nullptr);
        QDBusConnection::disconnectFromBus(QStringLiteral("app"));
    }

    void startsItWhenNothingAnswers() {
        FakeCompositor comp;
        FakeShell      shell;
        launcher->setCompositor(&comp);
        launcher->setAppWindow(&shell);
        launcher->registerPidForAppId(kPid, radio);

        QVERIFY(launcher->launchApp(QVariantMap{
            {"id", radio}, {"name", "Radio"}, {"type", "flatpak"}, {"exec", "FLATPAK:radio"}}));
        QTRY_COMPARE(comp.spawned, QStringList{"FLATPAK:radio"});
        launcher->setCompositor(nullptr);
    }

    // `waydroid app launch` with no session would become the session, and
    // stopping it would stop Android: the session unit runs it instead.
    void anAndroidLaunchWaitsForTheSessionUnit() {
        FakeCompositor comp;
        FakeShell      shell;
        launcher->setCompositor(&comp);
        launcher->setAppWindow(&shell);
        QVERIFY(launcher->launchApp(QVariantMap{{"id", "waydroid.org.fdroid.fdroid"},
                                                {"name", "F-Droid"},
                                                {"type", "native"},
                                                {"exec", "waydroid app launch org.fdroid.fdroid"}}));
        QTRY_COMPARE(systemd->calls, QStringList{"Start marathon-waydroid.service replace"});
        QVERIFY(comp.spawned.isEmpty());
        QTRY_COMPARE(comp.spawned, QStringList{"waydroid app launch org.fdroid.fdroid"});

        // The session is up: the next launch runs at once.
        QVERIFY(launcher->launchApp(QVariantMap{{"id", "waydroid.org.lineageos.jelly"},
                                                {"name", "Browser"},
                                                {"type", "native"},
                                                {"exec", "waydroid app launch org.lineageos.jelly"}}));
        QCOMPARE(comp.spawned.size(), 2);
        QCOMPARE(systemd->calls.size(), 1);
        QDBusConnection::disconnectFromBus(QStringLiteral("waydroid"));
        launcher->setCompositor(nullptr);
    }

    void withoutTheUnitTheLauncherRuns() {
        QDBusConnection::disconnectFromBus(QStringLiteral("systemd"));
        FakeCompositor comp;
        FakeShell      shell;
        launcher->setCompositor(&comp);
        launcher->setAppWindow(&shell);
        QVERIFY(launcher->launchApp(QVariantMap{{"id", "waydroid.org.fdroid.fdroid"},
                                                {"name", "F-Droid"},
                                                {"type", "native"},
                                                {"exec", "waydroid app launch org.fdroid.fdroid"}}));
        QTRY_COMPARE(comp.spawned, QStringList{"waydroid app launch org.fdroid.fdroid"});
        launcher->setCompositor(nullptr);
    }

    void neverFreezesTheShellsScope() {
        open(marathon::cgroup::cgroup_of_pid(QCoreApplication::applicationPid()));
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(state(), int(AppLifecycleManager::Frozen));
        QTest::qWait(50);
        QVERIFY(systemd->calls.isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestNativeLifecycle)
#include "test_nativelifecycle.moc"
