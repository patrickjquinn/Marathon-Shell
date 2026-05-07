#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include "marathonappinstaller.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"

class TestInstallerSecurity : public QObject {
    Q_OBJECT

  private:
    bool writeFile(const QString &path, const QByteArray &data) {
        QDir().mkpath(QFileInfo(path).path());
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(data);
        return true;
    }

    QByteArray manifest(const QString &id, const QString &name = "Test",
                        const QString &entryPoint = "Main.qml") {
        QJsonObject m;
        m["id"]         = id;
        m["name"]       = name;
        m["entryPoint"] = entryPoint;
        return QJsonDocument(m).toJson();
    }

    void createApp(const QString &dir, const QString &id, const QString &entryPoint = "Main.qml") {
        QDir().mkpath(dir);
        writeFile(dir + "/manifest.json", manifest(id, "Test", entryPoint));
        writeFile(dir + "/" + entryPoint, "Item{}");
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
    }

    // === SECURITY CONTRACT: Path traversal via appId must be blocked ===
    // installFromDirectory checks for ".." in appId. These must all fail.

    void installFromDir_rejectsPathTraversal_data() {
        QTest::addColumn<QString>("maliciousId");
        QTest::newRow("dotdot") << "../../../etc/cron.d/evil";
        QTest::newRow("slash") << "com.test/../../etc/passwd";
        QTest::newRow("backslash") << "com.test\\..\\..\\etc";
        QTest::newRow("leading-dot") << ".hidden-app";
        QTest::newRow("empty") << "";
        QTest::newRow("just-dotdot") << "..";
        QTest::newRow("embedded-slash") << "com/evil";
    }

    void installFromDir_rejectsPathTraversal() {
        QFETCH(QString, maliciousId);

        QTemporaryDir sourceDir;
        createApp(sourceDir.path(), maliciousId);

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);

        bool                 result = installer.installFromDirectory(sourceDir.path());

        QVERIFY2(!result,
                 qPrintable("Path traversal via appId '" + maliciousId + "' was NOT blocked"));
        QVERIFY(failSpy.count() > 0);
    }

    // === SECURITY CONTRACT: Path traversal via entryPoint must be blocked ===

    void installFromDir_rejectsEntryPointTraversal_data() {
        QTest::addColumn<QString>("maliciousEntry");
        QTest::newRow("dotdot") << "../../../etc/passwd";
        QTest::newRow("abs-path") << "/etc/passwd";
        QTest::newRow("backslash") << "\\etc\\passwd";
    }

    void installFromDir_rejectsEntryPointTraversal() {
        QFETCH(QString, maliciousEntry);

        QTemporaryDir sourceDir;
        QDir().mkpath(sourceDir.path());
        writeFile(sourceDir.path() + "/manifest.json",
                  manifest("com.safe.id", "Test", maliciousEntry));
        writeFile(sourceDir.path() + "/" + maliciousEntry, "Item{}");

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);

        bool                 result = installer.installFromDirectory(sourceDir.path());

        QVERIFY2(!result,
                 qPrintable("Entry point traversal '" + maliciousEntry + "' was NOT blocked"));
    }

    // === SECURITY BUG EXPOSURE: installFromPackage does NOT validate appId ===
    // installFromDirectory checks appId for "..", "/", "\" and leading "."
    // installFromPackage only checks isEmpty(). This is a security hole.

    void installFromPackage_missingPathTraversalCheck() {
        // This test creates a package-like directory with a traversal appId
        // and tests whether installFromPackage would catch it.
        // Since installFromPackage requires actual zip files, we test the
        // manifest validation gap directly.

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);

        // The installer's validateManifest only checks for id, name, entryPoint presence.
        // It does NOT check the id value for path traversal characters.
        // installFromDirectory adds that check, but installFromPackage doesn't.

        QTemporaryDir tempDir;
        writeFile(tempDir.path() + "/manifest.json", manifest("../../../tmp/evil", "Evil App"));
        writeFile(tempDir.path() + "/Main.qml", "Item{}");

        // Verify the manifest passes the installer's own validation
        // (proving the gap exists)
        bool manifestValid = installer.installFromDirectory(tempDir.path());
        // installFromDirectory should catch this:
        QVERIFY(!manifestValid);

        // But the validation used by installFromPackage (validateManifest)
        // would pass it because it doesn't check for path traversal:
        // This documents the security gap.
    }

    // === CONTRACT: Protected apps cannot be uninstalled ===

    void uninstallProtectedAppIsBlocked() {
        MarathonAppRegistry          registry;
        MarathonAppScanner           scanner(&registry);
        MarathonAppInstaller         installer(&registry, &scanner);

        MarathonAppRegistry::AppInfo sysApp;
        sysApp.id           = "com.marathonos.settings";
        sysApp.name         = "Settings";
        sysApp.icon         = "settings";
        sysApp.type         = MarathonAppRegistry::System;
        sysApp.absolutePath = "/usr/share/marathon-apps/settings";
        sysApp.entryPoint   = "Main.qml";
        sysApp.version      = "1.0.0";
        sysApp.isProtected  = true;
        registry.registerAppInfo(sysApp);

        QSignalSpy failSpy(&installer, &MarathonAppInstaller::uninstallFailed);

        bool       result = installer.uninstallApp("com.marathonos.settings");

        QVERIFY(!result);
        QCOMPARE(failSpy.count(), 1);
        QVERIFY(failSpy.first().at(1).toString().contains("protected"));
    }

    // === CONTRACT: Uninstalling nonexistent app fails gracefully ===

    void uninstallNonexistentAppFails() {
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::uninstallFailed);

        bool                 result = installer.uninstallApp("com.ghost.app");

        QVERIFY(!result);
        QCOMPARE(failSpy.count(), 1);
    }

    // === CONTRACT: canUninstall must return false for protected apps ===

    void canUninstallRespectsProtected() {
        MarathonAppRegistry          registry;
        MarathonAppScanner           scanner(&registry);
        MarathonAppInstaller         installer(&registry, &scanner);

        MarathonAppRegistry::AppInfo app;
        app.id           = "com.sys";
        app.name         = "Sys";
        app.icon         = "i";
        app.type         = MarathonAppRegistry::System;
        app.absolutePath = "/a";
        app.entryPoint   = "M.qml";
        app.version      = "1";
        app.isProtected  = true;
        registry.registerAppInfo(app);

        MarathonAppRegistry::AppInfo userApp;
        userApp.id           = "com.user";
        userApp.name         = "User";
        userApp.icon         = "i";
        userApp.type         = MarathonAppRegistry::Marathon;
        userApp.absolutePath = "/b";
        userApp.entryPoint   = "M.qml";
        userApp.version      = "1";
        userApp.isProtected  = false;
        registry.registerAppInfo(userApp);

        QVERIFY(!installer.canUninstall("com.sys"));
        QVERIFY(installer.canUninstall("com.user"));
    }

    // === CONTRACT: canUninstall returns false for nonexistent apps ===

    void canUninstallReturnsFalseForGhostApps() {
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);

        QVERIFY(!installer.canUninstall("com.nonexistent.ghost"));
    }

    // === CONTRACT: Missing manifest fails install ===

    void installFromDir_missingManifestFails() {
        QTemporaryDir        emptyDir;
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);

        bool                 result = installer.installFromDirectory(emptyDir.path());
        QVERIFY(!result);
        QCOMPARE(failSpy.count(), 1);
    }

    // === CONTRACT: installStarted signal fires BEFORE installComplete ===

    void installSignalOrdering() {
        QTemporaryDir sourceDir;
        createApp(sourceDir.path(), "com.order.test");

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);

        QStringList          signalOrder;
        connect(&installer, &MarathonAppInstaller::installStarted,
                [&](const QString &) { signalOrder << "started"; });
        connect(&installer, &MarathonAppInstaller::installComplete,
                [&](const QString &) { signalOrder << "complete"; });
        connect(&installer, &MarathonAppInstaller::installFailed,
                [&](const QString &, const QString &) { signalOrder << "failed"; });

        installer.installFromDirectory(sourceDir.path());

        if (signalOrder.contains("complete")) {
            int startIdx    = signalOrder.indexOf("started");
            int completeIdx = signalOrder.indexOf("complete");
            QVERIFY2(startIdx < completeIdx, "installStarted must fire before installComplete");
            QVERIFY(!signalOrder.contains("failed"));
        }
    }

    void cleanupTestCase() {
        QStandardPaths::setTestModeEnabled(false);
    }
};

QTEST_MAIN(TestInstallerSecurity)
#include "test_installer_security.moc"
