#include <QDBusConnection>
#include <QTest>

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "taskmodel.h"

// Waydroid's container service, as the shell calls it on the system bus.
class FakeContainer : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "id.waydro.ContainerManager")

  public:
    QStringList calls;

  public slots:
    void Freeze() {
        calls << QStringLiteral("Freeze");
    }
    void Unfreeze() {
        calls << QStringLiteral("Unfreeze");
    }
};

// Android freezes its own cached apps and dozes with the phone; a frozen
// container delivers no notifications, alarms or audio. The shell leaves it
// running whatever is in front, in Doze too.
class TestAndroidFreeze : public QObject {
    Q_OBJECT

    TaskModel           *tasks     = nullptr;
    AppLaunchService    *launcher  = nullptr;
    AppLifecycleManager *lifecycle = nullptr;
    FakeContainer        container;
    QObject              windowA;
    QObject              surface;

    void show(const QString &appId, QObject *window, int surfaceId) {
        tasks->launchTask(appId, appId, appId, "native", surfaceId, &surface);
        window->setProperty("surfaceId", surfaceId);
        window->setProperty("isNative", true);
        lifecycle->registerApp(appId, window);
        lifecycle->bringToForeground(appId);
    }

  private slots:
    void initTestCase() {
        QDBusConnection bus = QDBusConnection::systemBus();
        QVERIFY(bus.registerObject(QStringLiteral("/ContainerManager"), &container,
                                   QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerService(QStringLiteral("id.waydro.Container")));
    }

    void init() {
        container.calls.clear();
        tasks     = new TaskModel(this);
        launcher  = new AppLaunchService(nullptr, tasks, this);
        lifecycle = new AppLifecycleManager(tasks, launcher, this);
        lifecycle->setIdleFreezeDebounceMs(0);
    }

    void cleanup() {
        delete lifecycle;
        delete launcher;
        delete tasks;
    }

    void androidRunsWhenItsAppLeavesTheFront() {
        show("waydroid.a", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        // Past the 10 s the shell used to wait before freezing it.
        QTest::qWait(10500);
        QVERIFY(container.calls.isEmpty());
        QCOMPARE(lifecycle->lifecycleState("waydroid.a"),
                 int(AppLifecycleManager::BackgroundIdle));
    }

    // Doze sets the idle debounce to 0.
    void androidRunsInDoze() {
        show("waydroid.a", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        lifecycle->wakeApp("waydroid.b");
        QTest::qWait(80);
        QVERIFY(container.calls.isEmpty());
    }
};

int main(int argc, char **argv) {
    // The system bus is this test's private bus, where the fake container is.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", qgetenv("DBUS_SESSION_BUS_ADDRESS"));
    QCoreApplication  app(argc, argv);
    TestAndroidFreeze test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_androidfreeze.moc"
