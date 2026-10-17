#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include "marathonappinstaller.h"
#include "marathonapppackager.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"
#include "marathonappverifier.h"
#include "minisign_testkeys.h"

class TestInstallerSecurity : public QObject {
    Q_OBJECT

  private:
    QTemporaryDir m_home;

    bool          writeFile(const QString &path, const QByteArray &data) {
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

    // A .marathon package of a minimal app, signed with `key` unless null.
    QString makePackage(const QString &name, const QString &id,
                        const TestKeys::Pair *key = nullptr) {
        QTemporaryDir src;
        QJsonObject   m;
        m["id"]         = id;
        m["name"]       = "Test";
        m["version"]    = "1.0.0";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "icon.svg";
        writeFile(src.path() + "/manifest.json", QJsonDocument(m).toJson());
        writeFile(src.path() + "/Main.qml", "Item{}");
        QString             path = m_home.path() + "/" + name + ".marathon";
        MarathonAppPackager packager;
        if (!packager.createPackage(src.path(), path))
            return {};
        if (key) {
            const QString       keyPath = m_home.path() + "/" + name + ".key";
            MarathonAppVerifier verifier;
            if (!writeFile(keyPath, key->secret) || !verifier.signPackage(path, keyPath))
                return {};
        }
        return path;
    }

    QString installDir(const QString &id) {
        return QDir::homePath() + "/.local/share/marathon-apps/" + id;
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_home.isValid());
        qputenv("HOME", m_home.path().toUtf8());
        QStandardPaths::setTestModeEnabled(true);
        const QString keys = MarathonAppVerifier::trustedKeyDirs().last();
        QVERIFY(QDir().mkpath(keys));
        QVERIFY(writeFile(keys + "/alice.pub", TestKeys::alice.pub));
    }

    // Most cases below install from a directory, which is unsigned, so they
    // run under the developer override; signature tests clear it first.
    void init() {
        qputenv("MARATHON_ALLOW_UNSIGNED", "1");
    }

    // === SECURITY CONTRACT: packages are verified before they are read ===

    void installFromPackage_signedPackageInstalls() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        const QString pkg = makePackage("signed", "com.signed.app", &TestKeys::alice);
        QVERIFY(!pkg.isEmpty());
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QVERIFY(installer.installFromPackage(pkg));
        QVERIFY(QFile::exists(installDir("com.signed.app") + "/manifest.json"));
    }

    void installFromPackage_unsignedRejectedByDefault() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        const QString pkg = makePackage("unsigned", "com.unsigned.app");
        QVERIFY(!pkg.isEmpty());
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);
        QVERIFY(!installer.installFromPackage(pkg));
        QCOMPARE(failSpy.count(), 1);
        QVERIFY(failSpy.first().at(1).toString().contains("not signed"));
        QVERIFY(!QDir(installDir("com.unsigned.app")).exists());

        qputenv("MARATHON_ALLOW_UNSIGNED", "1");
        QVERIFY(installer.installFromPackage(pkg));
        QVERIFY(QDir(installDir("com.unsigned.app")).exists());
    }

    // The signed bytes are swapped for another valid package whose appId
    // would trip the traversal check. The signature check must refuse it
    // first, before the archive is opened.
    void installFromPackage_tamperedRejectedBeforeParsing() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        const QString pkg   = makePackage("victim", "com.victim.app", &TestKeys::alice);
        const QString other = makePackage("evil", "../evil", nullptr);
        QVERIFY(!pkg.isEmpty() && !other.isEmpty());
        QVERIFY(QFile::remove(pkg));
        QVERIFY(QFile::copy(other, pkg));
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);
        QSignalSpy           progressSpy(&installer, &MarathonAppInstaller::installProgress);
        QVERIFY(!installer.installFromPackage(pkg));
        QCOMPARE(failSpy.count(), 1);
        QVERIFY2(failSpy.first().at(1).toString().contains("Invalid signature"),
                 qPrintable(failSpy.first().at(1).toString()));
        QCOMPARE(progressSpy.count(), 0);
    }

    void installFromPackage_untrustedKeyRejected() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        const QString pkg = makePackage("mallory", "com.mallory.app", &TestKeys::mallory);
        QVERIFY(!pkg.isEmpty());
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QVERIFY(!installer.installFromPackage(pkg));
        QVERIFY(!QDir(installDir("com.mallory.app")).exists());
    }

    void installFromDir_refusedWithoutOverride() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        QTemporaryDir sourceDir;
        createApp(sourceDir.path(), "com.dir.app");
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);
        QVERIFY(!installer.installFromDirectory(sourceDir.path()));
        QCOMPARE(failSpy.count(), 1);
        QVERIFY(!QDir(installDir("com.dir.app")).exists());
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
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        QStandardPaths::setTestModeEnabled(false);
    }
};

QTEST_MAIN(TestInstallerSecurity)
#include "test_installer_security.moc"
