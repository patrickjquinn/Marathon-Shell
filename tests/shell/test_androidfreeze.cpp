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

// Android has no process of its own per app, so its apps never freeze one by
// one; the container freezes when no Android app is in front, or the phone
// dozes.
class TestAndroidFreeze : public QObject {
    Q_OBJECT

    TaskModel           *tasks     = nullptr;
    AppLaunchService    *launcher  = nullptr;
    AppLifecycleManager *lifecycle = nullptr;
    FakeContainer        container;
    QObject              windowA;
    QObject              windowB;
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
        lifecycle->setIdleFreezeDebounceMs(20);
    }

    void cleanup() {
        delete lifecycle;
        delete launcher;
        delete tasks;
    }

    void freezesWhenNoAndroidAppIsInFront() {
        show("waydroid.a", &windowA, 11);
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
    }

    void thawsBeforeAnAndroidAppComesBack() {
        show("waydroid.a", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
        lifecycle->bringToForeground("waydroid.a");
        QTRY_COMPARE(container.calls, (QStringList{"Freeze", "Unfreeze"}));
    }

    void anotherAndroidAppInFrontKeepsItRunning() {
        show("waydroid.a", &windowA, 11);
        show("waydroid.b", &windowB, 12);
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
    }

    void freezesWhileDozingEvenInFront() {
        show("waydroid.a", &windowA, 11);
        lifecycle->setDozing(true);
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
        lifecycle->setDozing(false);
        QTRY_COMPARE(container.calls, (QStringList{"Freeze", "Unfreeze"}));
    }

    void playingAudioKeepsItRunning() {
        show("waydroid.a", &windowA, 11);
        lifecycle->addCapability("waydroid.a", QStringLiteral("audio-playback"));
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
    }

    // An Android launch thaws it, so `waydroid app launch` finds it running.
    void anAndroidLaunchThawsIt() {
        show("waydroid.a", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
        lifecycle->wakeApp("waydroid.b");
        QTRY_COMPARE(container.calls.mid(0, 2), (QStringList{"Freeze", "Unfreeze"}));
    }

    void withoutAndroidNothingIsCalled() {
        show("plain", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        lifecycle->setDozing(true);
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
        lifecycle->setDozing(false);
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
