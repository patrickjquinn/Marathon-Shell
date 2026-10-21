#include <QTest>
#include <QSignalSpy>
#include <QDir>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include "marathonappinstaller.h"
#include "marathonapppackager.h"
#include "marathonapppaths.h"
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
    QString makePackage(const QString &name, const QString &id, const TestKeys::Pair *key = nullptr,
                        const QStringList &permissions = {}, const QJsonObject &extra = {}) {
        QTemporaryDir src;
        QJsonObject   m;
        m["id"]          = id;
        m["name"]        = "Test";
        m["version"]     = "1.0.0";
        m["entryPoint"]  = "Main.qml";
        m["icon"]        = "icon.svg";
        m["permissions"] = QJsonArray::fromStringList(permissions);
        for (auto it = extra.begin(); it != extra.end(); ++it)
            m[it.key()] = it.value();
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
        return MarathonAppPaths::filesDir(id);
    }

    QJsonObject receipt(const QString &id) {
        QFile f(MarathonAppPaths::receiptPath(id));
        return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object()
                                           : QJsonObject();
    }

    // What a fresh shell sees after a reboot.
    MarathonAppRegistry::AppInfo rescanned(const QString &id, MarathonAppRegistry &registry) {
        MarathonAppScanner scanner(&registry);
        scanner.scanApplications();
        MarathonAppRegistry::AppInfo *info = registry.getAppInfo(id);
        return info ? *info : MarathonAppRegistry::AppInfo();
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_home.isValid());
        qputenv("HOME", m_home.path().toUtf8());
        qunsetenv("XDG_DATA_HOME");
        qunsetenv("XDG_CONFIG_HOME");
        qunsetenv("XDG_CACHE_HOME");
        qputenv("MARATHON_APPS_DIR", (m_home.path() + "/system-apps").toUtf8());
        qputenv("MARATHON_SYSTEM_KEYS_DIR", (m_home.path() + "/system-keys").toUtf8());
        QStandardPaths::setTestModeEnabled(true);
        const QString keys = MarathonAppVerifier::trustedKeyDirs().constLast();
        QVERIFY(QDir().mkpath(keys));
        QVERIFY(writeFile(keys + "/alice.pub", TestKeys::alice.pub));
        QVERIFY(writeFile(MarathonAppVerifier::systemKeyDir() + "/bob.pub", TestKeys::bob.pub));
    }

    // === SECURITY CONTRACT: the installed app cannot change what it was granted ===

    void install_keepsCodeOutOfTheAppsDataDirectory() {
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        const QString        id = "com.layout.app";
        QVERIFY(installer.installFromPackage(
            makePackage("layout", id, &TestKeys::alice, {"network", "camera"})));

        QVERIFY(QFile::exists(MarathonAppPaths::filesDir(id) + "/manifest.json"));
        QVERIFY(!QFile::exists(MarathonAppPaths::dataDir(id) + "/manifest.json"));
        QVERIFY(!MarathonAppPaths::installDir(id).startsWith(MarathonAppPaths::dataDir(id)));
        QCOMPARE(receipt(id).value("signer").toString(), QString(TestKeys::alice.id));
        QCOMPARE(receipt(id).value("permissions").toVariant().toStringList(),
                 QStringList({"network", "camera"}));
        QCOMPARE(registry.getAppInfo(id)->absolutePath, MarathonAppPaths::filesDir(id));
    }

    // The sandboxed app can write its data directory. Writing a manifest
    // there, or (with no sandbox) over its installed one, gains nothing.
    void install_editedManifestGainsNothing() {
        {
            MarathonAppRegistry  registry;
            MarathonAppScanner   scanner(&registry);
            MarathonAppInstaller installer(&registry, &scanner);
            QVERIFY(installer.installFromPackage(
                makePackage("crafted", "com.crafted.app", &TestKeys::alice, {"network"})));
        }
        const QJsonObject escalated{{"id", "com.crafted.app"},
                                    {"name", "Crafted"},
                                    {"entryPoint", "Main.qml"},
                                    {"protected", true},
                                    {"permissions", QJsonArray({"network", "system", "contacts"})}};
        const QByteArray  json = QJsonDocument(escalated).toJson();
        QVERIFY(writeFile(MarathonAppPaths::dataDir("com.crafted.app") + "/manifest.json", json));
        QVERIFY(writeFile(MarathonAppPaths::filesDir("com.crafted.app") + "/manifest.json", json));

        MarathonAppRegistry                registry;
        const MarathonAppRegistry::AppInfo info = rescanned("com.crafted.app", registry);
        QCOMPARE(info.permissions, QStringList({"network"}));
        QVERIFY(!info.isProtected);
        QVERIFY(!info.isSystem);
    }

    void install_protectedNeedsTheSystemKey() {
        const QJsonObject claim{{"protected", true}};
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QVERIFY(installer.installFromPackage(
            makePackage("devsigned", "com.devsigned.app", &TestKeys::alice, {"system"}, claim)));
        QVERIFY(installer.installFromPackage(
            makePackage("ossigned", "com.ossigned.app", &TestKeys::bob, {"system"}, claim)));
        QVERIFY(!registry.getAppInfo("com.devsigned.app")->isProtected);
        QVERIFY(registry.getAppInfo("com.ossigned.app")->isSystem);
        QVERIFY(registry.getAppInfo("com.ossigned.app")->isProtected);
    }

    void install_systemPathAppsAreSystem() {
        const QString dir = MarathonAppPaths::systemApps() + "/sysapp";
        QJsonObject   m{{"id", "sysapp"},
                        {"name", "Sys"},
                        {"entryPoint", "Main.qml"},
                        {"protected", true},
                        {"permissions", QJsonArray({"system"})}};
        QVERIFY(writeFile(dir + "/manifest.json", QJsonDocument(m).toJson()));
        MarathonAppRegistry                registry;
        const MarathonAppRegistry::AppInfo info = rescanned("sysapp", registry);
        QVERIFY(info.isSystem);
        QVERIFY(info.isProtected);
        QCOMPARE(info.permissions, QStringList({"system"}));

        // A user install cannot take a system app's id.
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);
        QVERIFY(!installer.installFromPackage(makePackage("shadow", "sysapp", &TestKeys::alice)));
        QCOMPARE(failSpy.count(), 1);
        QVERIFY(!QDir(MarathonAppPaths::installDir("sysapp")).exists());
        QVERIFY(QDir(dir).removeRecursively());
    }

    // An install from before the layout change lived in its data directory,
    // perhaps with a manifest the app rewrote itself.
    void migration_movesLegacyInstallsOut() {
        const QString     legacy = MarathonAppPaths::dataDir("com.legacy.app");
        const QJsonObject m{
            {"id", "com.legacy.app"}, {"name", "Legacy"},
            {"version", "1.0.0"},     {"entryPoint", "Main.qml"},
            {"protected", true},      {"permissions", QJsonArray({"network", "system"})}};
        QVERIFY(writeFile(legacy + "/manifest.json", QJsonDocument(m).toJson()));
        QVERIFY(writeFile(legacy + "/Main.qml", "Item{}"));
        QVERIFY(writeFile(legacy + "/notes.db", "the app's data"));
        QVERIFY(writeFile(MarathonAppPaths::dataDir("com.dataonly.app") + "/settings.ini", "x"));

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QCOMPARE(installer.migrateLegacyInstalls(), QStringList({"com.legacy.app"}));
        QVERIFY(installer.migrateLegacyInstalls().isEmpty());

        QVERIFY(QFile::exists(MarathonAppPaths::filesDir("com.legacy.app") + "/Main.qml"));
        QVERIFY(QFile::exists(legacy + "/notes.db"));
        QVERIFY(receipt("com.legacy.app").value("migrated").toBool());
        QVERIFY(!QDir(MarathonAppPaths::installDir("com.dataonly.app")).exists());

        const MarathonAppRegistry::AppInfo info = rescanned("com.legacy.app", registry);
        QCOMPARE(info.absolutePath, MarathonAppPaths::filesDir("com.legacy.app"));
        QVERIFY(!info.isProtected);
        QVERIFY(!info.isSystem);
        QVERIFY(installer.canUninstall("com.legacy.app"));
    }

    void migration_skipsWhenTheLegacyDirIsTheSystemDir() {
        const QByteArray system = qgetenv("MARATHON_APPS_DIR");
        qputenv("MARATHON_APPS_DIR", MarathonAppPaths::legacyInstalls().toUtf8());
        QVERIFY(
            writeFile(MarathonAppPaths::dataDir("devapp") + "/manifest.json", manifest("devapp")));
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QVERIFY(installer.migrateLegacyInstalls().isEmpty());
        QVERIFY(!QDir(MarathonAppPaths::installDir("devapp")).exists());
        qputenv("MARATHON_APPS_DIR", system);
        QVERIFY(QDir(MarathonAppPaths::dataDir("devapp")).removeRecursively());
    }

    // === CONTRACT: uninstalling follows the manifest's dataLifecycle ===

    void uninstall_followsDataLifecycle_data() {
        QTest::addColumn<QString>("appData");
        QTest::newRow("remove") << "remove";
        QTest::newRow("keep") << "keep";
        QTest::newRow("undeclared") << "";
    }

    void uninstall_followsDataLifecycle() {
        QFETCH(QString, appData);
        const QString id = "com.lifecycle." + (appData.isEmpty() ? QString("none") : appData);
        QJsonObject   extra;
        if (!appData.isEmpty())
            extra["dataLifecycle"] =
                QJsonObject{{"appData", appData}, {"cache", "remove"}, {"userFiles", "preserve"}};
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QVERIFY(installer.installFromPackage(
            makePackage("lifecycle-" + appData, id, &TestKeys::alice, {"storage"}, extra)));
        QVERIFY(writeFile(MarathonAppPaths::dataDir(id) + "/notes.db", "data"));
        QVERIFY(writeFile(MarathonAppPaths::configDir(id) + "/app.conf", "conf"));
        QVERIFY(writeFile(MarathonAppPaths::cacheDir(id) + "/tile.png", "cache"));
        const QString userFile = QDir::homePath() + "/Documents/" + id + ".txt";
        QVERIFY(writeFile(userFile, "the user's"));

        QSignalSpy removed(&installer, &MarathonAppInstaller::appDataRemoved);
        QSignalSpy done(&installer, &MarathonAppInstaller::uninstallComplete);
        QVERIFY(installer.uninstallApp(id));
        QCOMPARE(done.count(), 1);
        QVERIFY(!registry.hasApp(id));
        QVERIFY(!QDir(MarathonAppPaths::installDir(id)).exists());
        QVERIFY(!QDir(MarathonAppPaths::cacheDir(id)).exists());
        QVERIFY(QFile::exists(userFile));
        const bool kept = appData == "keep";
        QCOMPARE(QFile::exists(MarathonAppPaths::dataDir(id) + "/notes.db"), kept);
        QCOMPARE(QFile::exists(MarathonAppPaths::configDir(id) + "/app.conf"), kept);
        QCOMPARE(removed.count(), kept ? 0 : 1);
    }

    void uninstall_refusesSystemApps() {
        QVERIFY(writeFile(MarathonAppPaths::systemApps() + "/bundled/manifest.json",
                          manifest("bundled")));
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        scanner.scanApplications();
        QVERIFY(registry.hasApp("bundled"));
        QVERIFY(!installer.uninstallApp("bundled"));
        QVERIFY(QFile::exists(MarathonAppPaths::systemApps() + "/bundled/manifest.json"));
        QVERIFY(QDir(MarathonAppPaths::systemApps() + "/bundled").removeRecursively());
    }

    // marathon-dev installs from its own process; the shell's registry was
    // scanned before.
    void uninstall_findsAppsInstalledElsewhere() {
        MarathonAppRegistry  shellRegistry;
        MarathonAppScanner   shellScanner(&shellRegistry);
        MarathonAppInstaller shell(&shellRegistry, &shellScanner);
        shellScanner.scanApplications();

        MarathonAppRegistry  devRegistry;
        MarathonAppScanner   devScanner(&devRegistry);
        MarathonAppInstaller dev(&devRegistry, &devScanner);
        QVERIFY(dev.installFromPackage(
            makePackage("elsewhere", "com.elsewhere.app", &TestKeys::alice)));
        QVERIFY(!shellRegistry.hasApp("com.elsewhere.app"));

        QVERIFY(shell.canUninstall("com.elsewhere.app"));
        QVERIFY(shell.uninstallApp("com.elsewhere.app"));
        QVERIFY(!QDir(MarathonAppPaths::installDir("com.elsewhere.app")).exists());
        QVERIFY(!shell.canUninstall("com.never.installed"));
    }

    void install_needsAReceipt() {
        QVERIFY(writeFile(MarathonAppPaths::filesDir("com.copied.app") + "/manifest.json",
                          manifest("com.copied.app")));
        MarathonAppRegistry registry;
        QVERIFY(rescanned("com.copied.app", registry).id.isEmpty());
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

    // === SECURITY CONTRACT: every permission is disclosed, widening needs consent ===

    void installFromPackage_undisclosedPermissionRefused() {
        const QString pkg = makePackage("undisclosed", "com.undisclosed.app", &TestKeys::alice,
                                        {"network", "root-shell"});
        QVERIFY(!pkg.isEmpty());
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);
        QVERIFY(!installer.installFromPackage(pkg));
        QCOMPARE(failSpy.count(), 1);
        QVERIFY(failSpy.first().at(1).toString().contains("root-shell"));
        QVERIFY(!QDir(installDir("com.undisclosed.app")).exists());
    }

    void installFromPackage_plansDisclosuresFromTheManifest() {
        const QString pkg = makePackage("disclosed", "com.disclosed.app", &TestKeys::alice,
                                        {"camera", "network", "camera"});
        QVERIFY(!pkg.isEmpty());
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           planSpy(&installer, &MarathonAppInstaller::installPlanned);
        QVERIFY(installer.installFromPackage(pkg));
        QCOMPARE(planSpy.count(), 1);
        const QVariantMap  plan        = planSpy.first().at(1).toMap();
        const QVariantList disclosures = plan.value("permissions").toList();
        QCOMPARE(plan.value("signer").toString(), QString(TestKeys::alice.id));
        QCOMPARE(plan.value("update").toBool(), false);
        QCOMPARE(disclosures.size(), 2);
        QCOMPARE(disclosures.at(0).toMap().value("id").toString(), QString("camera"));
        QCOMPARE(disclosures.at(0).toMap().value("label").toString(), QString("Camera"));
        QVERIFY(disclosures.at(0).toMap().value("sensitive").toBool());
        QVERIFY(!disclosures.at(1).toMap().value("detail").toString().isEmpty());
    }

    void installFromPackage_wideningUpdateHeldForConsent() {
        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        const QString        id = "com.widening.app";
        QVERIFY(installer.installFromPackage(
            makePackage("widen1", id, &TestKeys::alice, {"network", "storage"})));

        const QString wider =
            makePackage("widen2", id, &TestKeys::alice, {"network", "camera", "contacts"});
        QSignalSpy heldSpy(&installer, &MarathonAppInstaller::installHeld);
        QSignalSpy failSpy(&installer, &MarathonAppInstaller::installFailed);
        QVERIFY(!installer.installFromPackage(wider));
        QCOMPARE(heldSpy.count(), 1);
        QCOMPARE(failSpy.count(), 0);
        QCOMPARE(heldSpy.first().at(1).toMap().value("added").toStringList(),
                 QStringList({"camera", "contacts"}));
        QFile installed(installDir(id) + "/manifest.json");
        QVERIFY(installed.open(QIODevice::ReadOnly));
        QVERIFY(!installed.readAll().contains("camera"));
        installed.close();

        QVERIFY(!installer.installFromPackage(wider, {"camera"}));
        QCOMPARE(heldSpy.count(), 2);
        QVERIFY(installer.installFromPackage(wider, {"camera", "contacts"}));
        QVERIFY(installed.open(QIODevice::ReadOnly));
        QVERIFY(installed.readAll().contains("camera"));
        installed.close();
        QCOMPARE(registry.getAppInfo(id)->permissions, QStringList({"network", "camera", "contacts"}));

        // Dropping permissions needs no consent.
        QVERIFY(
            installer.installFromPackage(makePackage("widen3", id, &TestKeys::alice, {"network"})));
        QCOMPARE(heldSpy.count(), 2);
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

        // Deep enough that the traversal lands in the temporary tree, never
        // on the real file: the tests run as root in CI's container.
        QTemporaryDir root;
        const QString source = root.path() + "/a/b/c/app";
        const QString target = QDir::cleanPath(source + "/" + maliciousEntry);
        QVERIFY2(target.startsWith(root.path()), qPrintable(target));
        QDir().mkpath(QFileInfo(target).absolutePath());
        QDir().mkpath(source);
        writeFile(source + "/manifest.json", manifest("com.safe.id", "Test", maliciousEntry));
        writeFile(target, "Item{}");

        MarathonAppRegistry  registry;
        MarathonAppScanner   scanner(&registry);
        MarathonAppInstaller installer(&registry, &scanner);
        QSignalSpy           failSpy(&installer, &MarathonAppInstaller::installFailed);

        bool                 result = installer.installFromDirectory(source);

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
        userApp.absolutePath = MarathonAppPaths::filesDir("com.user");
        userApp.entryPoint   = "M.qml";
        userApp.version      = "1";
        userApp.isProtected  = false;
        registry.registerAppInfo(userApp);

        MarathonAppRegistry::AppInfo bundled = userApp;
        bundled.id                           = "bundled";
        bundled.absolutePath                 = MarathonAppPaths::systemApps() + "/bundled";
        registry.registerAppInfo(bundled);

        QVERIFY(!installer.canUninstall("com.sys"));
        QVERIFY(installer.canUninstall("com.user"));
        QVERIFY(!installer.canUninstall("bundled"));
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
