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
// one; the container freezes once an Android app has been in front and none
// is any more, or the phone dozes after one has. Not while Android starts or
// a launch is on its way.
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

    void usedThenLeft() {
        show("waydroid.a", &windowA, 11);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
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
        lifecycle->m_androidMinFreezeDelayMs = 20;
    }

    void cleanup() {
        delete lifecycle;
        delete launcher;
        delete tasks;
        QDBusConnection::disconnectFromBus(QStringLiteral("session"));
    }

    // Booting, Waydroid maps and drops windows and its CLI thaws the
    // container; freezing then stalled Android's boot.
    void androidStartingIsLeftAlone() {
        tasks->launchTask("waydroid.a", "A", "a", "native", 11, &surface);
        tasks->launchTask("waydroid.b", "B", "b", "native", 12, &surface);
        lifecycle->setDozing(true);
        QTest::qWait(80);
        QVERIFY(container.calls.isEmpty());
        lifecycle->setDozing(false);
    }

    void freezesAfterAnAndroidAppLeavesTheFront() {
        show("waydroid.a", &windowA, 11);
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, QStringList{"Freeze"});
    }

    void thawsBeforeAnAndroidAppComesBack() {
        usedThenLeft();
        lifecycle->bringToForeground("waydroid.a");
        QTRY_COMPARE(container.calls, (QStringList{"Freeze", "Unfreeze"}));
    }

    void anotherAndroidAppInFrontKeepsItRunning() {
        show("waydroid.a", &windowA, 11);
        show("waydroid.b", &windowB, 12);
        QTest::qWait(60);
        QVERIFY(container.calls.isEmpty());
    }

    // Windows coming and going do not move it either way.
    void windowsAloneDoNotFreezeOrThawIt() {
        usedThenLeft();
        tasks->launchTask("waydroid.c", "C", "c", "native", 13, &surface);
        tasks->closeTask(tasks->getTaskByAppId("waydroid.c")->id());
        QTest::qWait(80);
        QCOMPARE(container.calls, QStringList{"Freeze"});
    }

    void dozeFreezesItAtOnceEvenInFront() {
        show("waydroid.a", &windowA, 11);
        lifecycle->m_androidMinFreezeDelayMs = 60000;
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

    // An Android launch thaws it, so `waydroid app launch` finds it running,
    // and nothing freezes it until the launch's window has come.
    void aPendingLaunchKeepsItRunning() {
        usedThenLeft();
        lifecycle->wakeApp("waydroid.b");
        QTRY_COMPARE(container.calls, (QStringList{"Freeze", "Unfreeze"}));
        lifecycle->setDozing(true);
        QTest::qWait(80);
        QCOMPARE(container.calls, (QStringList{"Freeze", "Unfreeze"}));
        lifecycle->setDozing(false);
        show("waydroid.b", &windowB, 12);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(container.calls, (QStringList{"Freeze", "Unfreeze", "Freeze"}));
    }

    // A new session is a new boot: it waits for an Android app in front again.
    void aNewSessionStartsOver() {
        usedThenLeft();
        QVERIFY(QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("session"))
                    .registerService(QStringLiteral("id.waydro.Session")));
        QTest::qWait(50);
        lifecycle->setDozing(true);
        QTest::qWait(80);
        QCOMPARE(container.calls, QStringList{"Freeze"});
        lifecycle->setDozing(false);
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
