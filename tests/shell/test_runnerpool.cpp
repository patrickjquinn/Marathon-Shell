#include <QtTest>

#include "applaunchservice.h"
#include "taskmodel.h"

class FakeCompositor : public QObject {
    Q_OBJECT
  public:
    QStringList      spawned;
    QString          socketDir;
    Q_INVOKABLE void launchApp(const QString &command, const QVariantMap &) {
        spawned << command;
    }
    Q_INVOKABLE QString openSandboxSocket(const QString &, const QString &instanceId) const {
        return socketDir + QLatin1Char('/') + instanceId;
    }
    Q_INVOKABLE void closeSandboxSocket(const QString &) {}
    Q_INVOKABLE void assignSandboxApp(const QString &, const QString &) {}
};

class FakeShell : public QObject {
    Q_OBJECT
  public:
    Q_INVOKABLE void show(const QVariant &, const QVariant &, const QVariant &, const QVariant &,
                          const QVariant &, const QVariant &) {}
    Q_INVOKABLE void openApp(const QVariant &, const QVariant &, const QVariant &) {}
};

// The warm spares: bwrap is a script that records its arguments and the
// adopt message the shell writes to it.
class TestRunnerPool : public QObject {
    Q_OBJECT

    using Shape = AppLaunchService::SpareShape;

    QTemporaryDir      bin;
    QTemporaryDir      runtime;
    QTemporaryDir      log;
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

    QString logged(qint64 pid, const char *suffix) const {
        QFile f(log.path() + QStringLiteral("/%1.%2").arg(pid).arg(QLatin1String(suffix)));
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
    }

    QStringList spareArgs(qint64 pid) const {
        return logged(pid, "args").split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    }

    // The adopt message the spare was sent, or an empty object.
    QJsonObject adoptMessage(qint64 pid) const {
        return QJsonDocument::fromJson(logged(pid, "in").toUtf8()).object();
    }

    qint64 warm(Shape shape) {
        launcher->refillSpares();
        if (!QTest::qWaitFor([&] { return launcher->m_spares[shape].adoptable; }))
            return -1;
        const qint64 pid = launcher->m_spares[shape].pid;
        return QTest::qWaitFor([&] { return !spareArgs(pid).isEmpty(); }) ? pid : -1;
    }

    QString pictures() const {
        return QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    }

  private slots:
    void initTestCase() {
        QFile fake(bin.path() + QStringLiteral("/bwrap"));
        QVERIFY(fake.open(QIODevice::WriteOnly));
        fake.write("#!/bin/sh\n"
                   "printf '%s\\n' \"$@\" > \"$POOL_LOG/$$.args\"\n"
                   "exec /bin/cat > \"$POOL_LOG/$$.in\"\n");
        fake.close();
        fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv("PATH", bin.path().toLocal8Bit());
        qputenv("POOL_LOG", log.path().toLocal8Bit());
        qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
        qputenv("HOME", runtime.path().toLocal8Bit());
        qunsetenv("XDG_DATA_HOME");
        qunsetenv("XDG_CACHE_HOME");
        qunsetenv("XDG_CONFIG_HOME");
        qunsetenv("MARATHON_DISABLE_SANDBOX");
        QVERIFY(pictures().startsWith(runtime.path()));
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

    void eachAppAdoptsTheSpareOfItsShape() {
        launcher->m_spareCount = 2;
        const qint64 storage   = warm(AppLaunchService::StorageSpare);
        const qint64 plain     = warm(AppLaunchService::PlainSpare);
        QVERIFY(storage > 0 && plain > 0);
        QVERIFY(spareArgs(storage).contains(pictures()));
        QVERIFY(!spareArgs(plain).contains(pictures()));
        QVERIFY(!spareArgs(plain).contains(runtime.path() + QStringLiteral("/DCIM")));

        QVERIFY(launcher->launchApp(app("notes", {"storage"})));
        QVERIFY(launcher->launchApp(app("calculator", {})));
        QVERIFY(comp->spawned.isEmpty());
        QTRY_COMPARE(adoptMessage(storage).value("appId").toString(), QStringLiteral("notes"));
        QTRY_COMPARE(adoptMessage(plain).value("appId").toString(), QStringLiteral("calculator"));
    }

    void aPlainAppNeverGetsTheMediaFolders() {
        launcher->m_spareCount = 1;
        const qint64 storage   = warm(AppLaunchService::StorageSpare);
        QVERIFY(storage > 0);

        QVERIFY(launcher->launchApp(app("calculator", {})));
        QCOMPARE(comp->spawned.size(), 1);
        QVERIFY(!QProcess::splitCommand(comp->spawned.first()).contains(pictures()));
        QVERIFY(adoptMessage(storage).isEmpty());
    }

    // One spare takes the shape most recent launches needed.
    void aLoneSpareFollowsTheLaunches() {
        launcher->m_spareCount = 1;
        const qint64 storage   = warm(AppLaunchService::StorageSpare);
        QVERIFY(storage > 0);

        QVERIFY(launcher->launchApp(app("calculator", {})));
        QVERIFY(!launcher->m_spares[AppLaunchService::StorageSpare].process);
        const qint64 plain = warm(AppLaunchService::PlainSpare);
        QVERIFY(plain > 0);
        QVERIFY(!spareArgs(plain).contains(pictures()));

        QVERIFY(launcher->launchApp(app("phone", {"telephony"})));
        QTRY_COMPARE(adoptMessage(plain).value("appId").toString(), QStringLiteral("phone"));
        const qint64 next = warm(AppLaunchService::PlainSpare);
        QVERIFY(next > 0);

        // Two plain launches to one storage one: the plain spare stays.
        QVERIFY(launcher->launchApp(app("notes", {"storage"})));
        QCOMPARE(launcher->m_spares[AppLaunchService::PlainSpare].pid, next);
        QVERIFY(adoptMessage(next).isEmpty());
    }

    // marathon-mail-oauth refuses the keyring without its grant in the env.
    void forwardsTheAppsGrants() {
        launcher->m_spareCount = 1;
        const qint64 storage   = warm(AppLaunchService::StorageSpare);
        QVERIFY(storage > 0);

        QVERIFY(launcher->launchApp(app("email", {"network", "storage", "secret-service"})));
        QTRY_VERIFY(!adoptMessage(storage).isEmpty());
        const QJsonObject env = adoptMessage(storage).value("env").toObject();
        QCOMPARE(env.value("MARATHON_PERM_SECRET_SERVICE").toString(), QStringLiteral("1"));
        QCOMPARE(env.value("MARATHON_PERM_STORAGE").toString(), QStringLiteral("1"));
    }

    void webEngineAppsStartCold() {
        launcher->m_spareCount = 1;
        const qint64 storage   = warm(AppLaunchService::StorageSpare);
        QVERIFY(storage > 0);

        QVERIFY(launcher->launchApp(app("browser", {"network", "storage"}, {"webengine"})));
        QCOMPARE(comp->spawned.size(), 1);
        QVERIFY(adoptMessage(storage).isEmpty());
    }

    void noSparesWhenThePoolIsOff() {
        launcher->m_spareCount = 0;
        launcher->refillSpares();
        QVERIFY(!launcher->m_spares[AppLaunchService::StorageSpare].process);
        QVERIFY(!launcher->m_spares[AppLaunchService::PlainSpare].process);
    }
};

QTEST_MAIN(TestRunnerPool)
#include "test_runnerpool.moc"
