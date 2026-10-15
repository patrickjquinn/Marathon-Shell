#include <QtTest>

#include "applaunchservice.h"
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
};

QTEST_GUILESS_MAIN(TestBackgroundLaunch)
#include "test_backgroundlaunch.moc"
