#include <QtTest>
#include <QDBusConnection>

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "appscope.h"
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
    void neverFreezesTheShellsScope() {
        QFile self(QStringLiteral("/proc/self/cgroup"));
        QVERIFY(self.open(QIODevice::ReadOnly));
        open(AppScope::cgroupFromProcFile(self.readAll()));
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(state(), int(AppLifecycleManager::Frozen));
        QTest::qWait(50);
        QVERIFY(systemd->calls.isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestNativeLifecycle)
#include "test_nativelifecycle.moc"
