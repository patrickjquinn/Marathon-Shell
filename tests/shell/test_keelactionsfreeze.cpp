#include <QtTest>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QTemporaryDir>

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "taskmodel.h"

// The runner's Lifecycle1 as the shell calls it. PrepareFreeze answers only
// when the test says so.
class FakeRunner : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.AppRunner.Lifecycle1")

  public:
    QStringList  calls;
    QDBusMessage pendingFreeze;

    void         answerFreeze() {
        QDBusConnection(QStringLiteral("runner")).send(pendingFreeze.createReply());
        pendingFreeze = {};
    }

  public slots:
    void PrepareFreeze() {
        calls << QStringLiteral("PrepareFreeze");
        setDelayedReply(true);
        pendingFreeze = message();
    }
    void Thawed() {
        calls << QStringLiteral("Thawed");
    }
};

class TestKeelActionsFreeze : public QObject {
    Q_OBJECT

    QTemporaryDir        data;
    TaskModel           *tasks     = nullptr;
    AppLaunchService    *launcher  = nullptr;
    AppLifecycleManager *lifecycle = nullptr;
    FakeRunner          *runner    = nullptr;

    static QVariantMap   app(const QString &id) {
        return {{"id", id}, {"name", id}, {"icon", id}, {"type", "marathon"}};
    }

    // In front with a mapped window, then sent home: the freeze debounce runs.
    void sendHome(const QString &id, qint64 pid) {
        launcher->registerPidForAppId(pid, id);
        tasks->launchTask(id, id, QString(), QStringLiteral("marathon"), 7);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(lifecycle->lifecycleState(id), int(AppLifecycleManager::BackgroundIdle));
    }

    int state(const QString &id) const {
        return lifecycle->lifecycleState(id);
    }

  private slots:
    void initTestCase() {
        QVERIFY(QDBusConnection::sessionBus().isConnected());
        QVERIFY(QDir(data.path()).mkpath("keel/actions"));
        QFile manifest(data.filePath("keel/actions/org.marathonos.notes.json"));
        QVERIFY(manifest.open(QIODevice::WriteOnly));
        manifest.write("{}");
        manifest.close();
        QVERIFY(QFile::copy(manifest.fileName(),
                            data.filePath("keel/actions/org.marathonos.gone.json")));
        qputenv("XDG_DATA_DIRS", data.path().toUtf8());
    }

    void init() {
        tasks     = new TaskModel(this);
        launcher  = new AppLaunchService(nullptr, tasks, this);
        lifecycle = new AppLifecycleManager(tasks, launcher, this);
        launcher->setAppLifecycleManager(lifecycle);
        lifecycle->setIdleFreezeDebounceMs(10);

        runner = new FakeRunner;
        QDBusConnection bus =
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("runner"));
        QVERIFY(bus.registerObject(QStringLiteral("/org/marathonos/AppRunner/Lifecycle"), runner,
                                   QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerService(QStringLiteral("org.marathonos.AppRunner.notes")));
        QVERIFY(bus.registerService(QStringLiteral("org.marathonos.AppRunner.plain")));
    }

    void cleanup() {
        QDBusConnection::disconnectFromBus(QStringLiteral("runner"));
        delete lifecycle;
        delete launcher;
        delete tasks;
        delete runner;
    }

    void releasesTheNameBeforeFreezing() {
        sendHome("notes", 4194301);
        QTRY_COMPARE(runner->calls, QStringList{"PrepareFreeze"});
        QTest::qWait(50);
        QCOMPARE(state("notes"), int(AppLifecycleManager::BackgroundIdle));

        runner->answerFreeze();
        QTRY_COMPARE(state("notes"), int(AppLifecycleManager::Frozen));
    }

    void wakesAFrozenAppAndRetakesTheName() {
        sendHome("notes", 4194301);
        QTRY_VERIFY(runner->pendingFreeze.type() == QDBusMessage::MethodCallMessage);
        runner->answerFreeze();
        QTRY_COMPARE(state("notes"), int(AppLifecycleManager::Frozen));

        lifecycle->setIdleFreezeDebounceMs(60000);
        QVERIFY(launcher->startAppInBackground(app("notes")));
        QCOMPARE(state("notes"), int(AppLifecycleManager::BackgroundIdle));
        QTRY_COMPARE(runner->calls, (QStringList{"PrepareFreeze", "Thawed"}));
    }

    void wakingCancelsAFreezeInFlight() {
        sendHome("notes", 4194301);
        QTRY_VERIFY(runner->pendingFreeze.type() == QDBusMessage::MethodCallMessage);
        lifecycle->setIdleFreezeDebounceMs(60000);
        QVERIFY(launcher->startAppInBackground(app("notes")));
        runner->answerFreeze();

        QTRY_COMPARE(runner->calls, (QStringList{"PrepareFreeze", "Thawed"}));
        QCOMPARE(state("notes"), int(AppLifecycleManager::BackgroundIdle));
    }

    void foregroundingCancelsAFreezeInFlight() {
        sendHome("notes", 4194301);
        QTRY_VERIFY(runner->pendingFreeze.type() == QDBusMessage::MethodCallMessage);
        QObject window;
        lifecycle->registerApp("notes", &window);
        lifecycle->bringToForeground("notes");
        runner->answerFreeze();

        QTRY_COMPARE(runner->calls, (QStringList{"PrepareFreeze", "Thawed"}));
        QCOMPARE(state("notes"), int(AppLifecycleManager::Foreground));
        lifecycle->unregisterApp("notes");
    }

    void freezesWhenTheRunnerCannotAnswer() {
        sendHome("gone", 4194302);
        QTRY_COMPARE(state("gone"), int(AppLifecycleManager::Frozen));
    }

    void appWithoutActionsFreezesWithoutAsking() {
        sendHome("plain", 4194303);
        QTRY_COMPARE(state("plain"), int(AppLifecycleManager::Frozen));
        QVERIFY(runner->calls.isEmpty());

        QVERIFY(launcher->startAppInBackground(app("plain")));
        QCOMPARE(state("plain"), int(AppLifecycleManager::BackgroundIdle));
        QTest::qWait(50);
        QVERIFY(runner->calls.isEmpty());
    }

    // Doze sets the debounce to 0.
    void zeroDebounceFreezesAtOnce() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launcher->registerPidForAppId(4194303, "plain");
        tasks->launchTask("plain", "plain", QString(), QStringLiteral("marathon"), 7);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(state("plain"), int(AppLifecycleManager::Frozen));
    }

    void zeroDebounceStillReleasesTheName() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launcher->registerPidForAppId(4194301, "notes");
        tasks->launchTask("notes", "notes", QString(), QStringLiteral("marathon"), 7);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTRY_COMPARE(runner->calls, QStringList{"PrepareFreeze"});
        QCOMPARE(state("notes"), int(AppLifecycleManager::BackgroundIdle));
        runner->answerFreeze();
        QTRY_COMPARE(state("notes"), int(AppLifecycleManager::Frozen));
    }

    void zeroDebounceSparesAnAppPlayingAudio() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launcher->registerPidForAppId(4194303, "plain");
        tasks->launchTask("plain", "plain", QString(), QStringLiteral("marathon"), 7);
        lifecycle->addCapability("plain", "audio-playback");
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(state("plain"), int(AppLifecycleManager::BackgroundActive));
        lifecycle->removeCapability("plain", "audio-playback");
        QCOMPARE(state("plain"), int(AppLifecycleManager::Frozen));
    }

    void zeroDebounceWaitsForTheFirstSurface() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launcher->registerPidForAppId(4194303, "plain");
        tasks->launchTask("plain", "plain", QString(), QStringLiteral("marathon"), -1);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QTest::qWait(50);
        QCOMPARE(state("plain"), int(AppLifecycleManager::BackgroundIdle));
    }

    void zeroDebounceLetsAWokenAppWork() {
        lifecycle->setIdleFreezeDebounceMs(0);
        launcher->registerPidForAppId(4194303, "plain");
        tasks->launchTask("plain", "plain", QString(), QStringLiteral("marathon"), 7);
        QVERIFY(lifecycle->minimizeForegroundApp());
        QCOMPARE(state("plain"), int(AppLifecycleManager::Frozen));
        QVERIFY(launcher->startAppInBackground(app("plain")));
        QTest::qWait(50);
        QCOMPARE(state("plain"), int(AppLifecycleManager::BackgroundIdle));
    }
};

QTEST_GUILESS_MAIN(TestKeelActionsFreeze)
#include "test_keelactionsfreeze.moc"
