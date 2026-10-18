#include <QDBusConnection>
#include <QDBusContext>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QThread>
#include <QTest>

#include "ipc/shellipcclients.h"
#include "marathonappinstaller.h"
#include "marathonapppaths.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"

// The shell's AppStore1 uninstall methods over the shell's real installer;
// `refused` stands in for a caller without the system permission.
class FakeAppStore : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.AppStore1")

  public:
    explicit FakeAppStore(MarathonAppInstaller *installer)
        : m_installer(installer) {
        connect(installer, &MarathonAppInstaller::uninstallComplete, this,
                &FakeAppStore::UninstallComplete);
        connect(installer, &MarathonAppInstaller::uninstallFailed, this,
                &FakeAppStore::UninstallFailed);
    }

    QAtomicInt refused = 0;

  public slots:
    bool CanUninstall(const QString &appId) {
        return !refuse() && m_installer->canUninstall(appId);
    }
    void Uninstall(const QString &appId) {
        if (!refuse())
            m_installer->uninstallApp(appId);
    }
    void announce(const QString &appId) {
        emit UninstallComplete(appId);
    }

  signals:
    void UninstallComplete(const QString &appId);
    void UninstallFailed(const QString &appId, const QString &error);

  private:
    bool refuse() {
        if (!refused.loadRelaxed())
            return false;
        sendErrorReply(QDBusError::AccessDenied, QStringLiteral("Missing permission: system"));
        return true;
    }

    MarathonAppInstaller *m_installer;
};

class TestAppInstallerClient : public QObject {
    Q_OBJECT

    QTemporaryDir        home;
    QProcess             daemon;
    QThread              serviceThread;
    MarathonAppRegistry  registry;
    MarathonAppScanner   scanner{&registry};
    MarathonAppInstaller installer{&registry, &scanner};
    FakeAppStore         store{&installer};

    static bool          writeFile(const QString &path, const QByteArray &data) {
        QDir().mkpath(QFileInfo(path).path());
        QFile f(path);
        return f.open(QIODevice::WriteOnly) && f.write(data) == data.size();
    }

    bool installUserApp(const QString &id) {
        QTemporaryDir src;
        return writeFile(src.path() + "/manifest.json",
                         QStringLiteral(R"({"id":"%1","name":"Crafted","entryPoint":"Main.qml"})")
                             .arg(id)
                             .toUtf8()) &&
            writeFile(src.path() + "/Main.qml", "Item{}") &&
            installer.installFromDirectory(src.path());
    }

  private slots:
    void initTestCase() {
        QVERIFY(home.isValid());
        qputenv("HOME", home.path().toUtf8());
        qunsetenv("XDG_DATA_HOME");
        qunsetenv("XDG_CONFIG_HOME");
        qunsetenv("XDG_CACHE_HOME");
        qputenv("MARATHON_APPS_DIR", (home.path() + "/system-apps").toUtf8());
        qputenv("MARATHON_ALLOW_UNSIGNED", "1");

        QVERIFY(writeFile(MarathonAppPaths::systemApps() + "/testapp/manifest.json",
                          R"({"id":"testapp","name":"Test Suite","entryPoint":"Main.qml"})"));
        QVERIFY(installUserApp("com.example.crafted"));
        QVERIFY(installUserApp("com.example.other"));
        QVERIFY(registry.hasApp("testapp"));

        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        QVERIFY(shell.registerObject("/org/marathonos/Shell/AppStore", &store,
                                     QDBusConnection::ExportAllSlots |
                                         QDBusConnection::ExportAllSignals));
        for (QObject *o : std::initializer_list<QObject *>{&registry, &scanner, &installer, &store})
            o->moveToThread(&serviceThread);
        serviceThread.start();
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }
    void cleanupTestCase() {
        serviceThread.quit();
        serviceThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }
    void cleanup() {
        store.refused = 0;
    }

    void onlyUserInstallsCanBeUninstalled() {
        AppInstallerClient client;
        QVERIFY(client.canUninstall("com.example.crafted"));
        QVERIFY(!client.canUninstall("testapp"));
        QVERIFY(!client.canUninstall("com.example.missing"));
    }

    void refusedCallersAreToldWhy() {
        store.refused = 1;
        AppInstallerClient client;
        QVERIFY(!client.canUninstall("com.example.crafted"));
        QSignalSpy failed(&client, &AppInstallerClient::uninstallFailed);
        client.uninstallApp("com.example.crafted");
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(failed.first().at(1).toString(), QString("Missing permission: system"));
        QVERIFY(QDir(MarathonAppPaths::installDir("com.example.crafted")).exists());
    }

    void systemAppsStayInstalled() {
        AppInstallerClient client;
        QSignalSpy         failed(&client, &AppInstallerClient::uninstallFailed);
        client.uninstallApp("testapp");
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(failed.first().at(0).toString(), QString("testapp"));
        QVERIFY(QFile::exists(MarathonAppPaths::systemApps() + "/testapp/manifest.json"));
    }

    void theShellRemovesTheAppAndItsData() {
        const QString id = "com.example.crafted";
        QVERIFY(writeFile(MarathonAppPaths::dataDir(id) + "/notes.db", "data"));
        QVERIFY(writeFile(MarathonAppPaths::cacheDir(id) + "/tile.png", "cache"));
        const QString userFile = home.path() + "/Documents/crafted.txt";
        QVERIFY(writeFile(userFile, "the user's"));

        AppInstallerClient client;
        QVERIFY(client.canUninstall(id));
        QSignalSpy done(&client, &AppInstallerClient::uninstallComplete);
        QSignalSpy removed(&client, &AppInstallerClient::appRemoved);
        client.uninstallApp(id);
        QTRY_COMPARE(done.count(), 1);
        QCOMPARE(removed.count(), 1);
        QVERIFY(!QDir(MarathonAppPaths::installDir(id)).exists());
        QVERIFY(!QDir(MarathonAppPaths::dataDir(id)).exists());
        QVERIFY(!QDir(MarathonAppPaths::cacheDir(id)).exists());
        QVERIFY(QFile::exists(userFile));
        QVERIFY(!client.canUninstall(id));
    }

    // Another app (the home screen's menu) uninstalled it: the list drops it,
    // but this client asked for nothing.
    void othersUninstallsOnlyUpdateTheList() {
        AppInstallerClient client;
        QSignalSpy         done(&client, &AppInstallerClient::uninstallComplete);
        QSignalSpy         removed(&client, &AppInstallerClient::appRemoved);
        QMetaObject::invokeMethod(&store, "announce", Q_ARG(QString, "com.example.other"));
        QTRY_COMPARE(removed.count(), 1);
        QCOMPARE(removed.first().at(0).toString(), QString("com.example.other"));
        QCOMPARE(done.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestAppInstallerClient)
#include "test_appinstallerclient.moc"
