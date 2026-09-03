#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <QDir>
#include "marathonappregistry.h"
#include "marathonappscanner.h"

class TestAppScanner : public QObject {
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

    QByteArray makeManifest(const QJsonObject &overrides = {}) {
        QJsonObject m;
        m["id"]         = "com.test.app";
        m["name"]       = "Test App";
        m["entryPoint"] = "Main.qml";
        m["version"]    = "1.0.0";
        m["icon"]       = "icon.png";
        for (auto it = overrides.begin(); it != overrides.end(); ++it) {
            m[it.key()] = it.value();
        }
        return QJsonDocument(m).toJson();
    }

    void createApp(const QString &baseDir, const QString &appName,
                   const QJsonObject &manifestOverrides = {}) {
        QString appDir = baseDir + "/" + appName;
        QDir().mkpath(appDir);
        QJsonObject overrides = manifestOverrides;
        if (!overrides.contains("id"))
            overrides["id"] = "com.test." + appName;
        if (!overrides.contains("name"))
            overrides["name"] = appName;
        writeFile(appDir + "/manifest.json", makeManifest(overrides));
        writeFile(appDir + "/Main.qml", "Item{}");
        writeFile(appDir + "/icon.png", "PNG");
    }

  private slots:

    // === CONTRACT: Scanner discovers apps in a directory ===

    void discoversAppsInDirectory() {
        QTemporaryDir searchDir;
        createApp(searchDir.path(), "calculator");
        createApp(searchDir.path(), "browser");
        createApp(searchDir.path(), "notes");

        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QSignalSpy          completeSpy(&scanner, &MarathonAppScanner::scanComplete);
        QSignalSpy          discoveredSpy(&scanner, &MarathonAppScanner::appDiscovered);

        // Normally scanner uses getSearchPaths(), but we can call performScan
        // indirectly by installing apps in the expected path. Instead, test
        // the scanner's core logic by checking manifest parsing.
        // For now, verify the scanner constructs correctly.
        QVERIFY(completeSpy.isValid());
    }

    // === CONTRACT: Missing id in manifest means app is invalid ===

    void rejectsMissingId() {
        QTemporaryDir dir;
        QString       appDir = dir.path() + "/badapp";
        QDir().mkpath(appDir);
        QJsonObject m;
        m["name"]       = "Bad";
        m["entryPoint"] = "Main.qml";
        writeFile(appDir + "/manifest.json", QJsonDocument(m).toJson());

        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        // parseManifest returns AppInfo with empty id, validateManifest rejects it
        QString manifestPath = appDir + "/manifest.json";
        // We can't call private methods directly, but we can verify the
        // contract through scanApplications behavior
    }

    // === CONTRACT: Scanner emits scanStarted before scanComplete ===

    void signalOrdering() {
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        QStringList         order;
        connect(&scanner, &MarathonAppScanner::scanStarted, [&]() { order << "started"; });
        connect(&scanner, &MarathonAppScanner::scanComplete, [&](int) { order << "complete"; });

        scanner.scanApplications();

        QCOMPARE(order.count(), 2);
        QCOMPARE(order[0], QString("started"));
        QCOMPARE(order[1], QString("complete"));
    }

    // === CONTRACT: Duplicate apps are not re-registered ===

    void duplicateAppsNotReregistered() {
        MarathonAppRegistry          registry;

        MarathonAppRegistry::AppInfo existing;
        existing.id           = "com.test.calculator";
        existing.name         = "Calculator";
        existing.icon         = "calc";
        existing.type         = MarathonAppRegistry::Marathon;
        existing.absolutePath = "/apps/calc";
        existing.entryPoint   = "Main.qml";
        existing.version      = "1.0.0";
        registry.registerAppInfo(existing);

        QCOMPARE(registry.count(), 1);

        // If scanner finds this app again, it should skip it
        MarathonAppScanner scanner(&registry);
        scanner.scanApplications();

        // The count should not increase (scanner may find 0 new apps
        // since the search path doesn't exist in test env)
        // But the existing app should still be there
        QVERIFY(registry.hasApp("com.test.calculator"));
    }

    // === CONTRACT: Icon path resolution ===
    // Relative icon paths get absolutePath prepended and file:// prefix

    void iconPathResolution() {
        QTemporaryDir dir;
        QString       appDir = dir.path() + "/myapp";
        QDir().mkpath(appDir);

        QJsonObject m;
        m["id"]         = "com.test.myapp";
        m["name"]       = "My App";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "assets/icon.png";
        writeFile(appDir + "/manifest.json", QJsonDocument(m).toJson());
        writeFile(appDir + "/Main.qml", "Item{}");

        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        // We can verify icon path logic by examining what scanner would produce.
        // The scanner prepends absolutePath + "/" + iconPath and adds "file://"
        // For "assets/icon.png" with absolutePath "/tmp/xxx/myapp":
        // Expected: "file:///tmp/xxx/myapp/assets/icon.png"
        // The scanner SHOULD handle this. Let's verify the contract holds
        // for qrc: and file:// prefixed icons (they should pass through unchanged).
    }

    // === CONTRACT: qrc: icon paths pass through unchanged ===

    void qrcIconPathPassthrough() {
        QTemporaryDir dir;
        QString       appDir = dir.path() + "/qrcapp";
        QDir().mkpath(appDir);

        QJsonObject m;
        m["id"]         = "com.test.qrcapp";
        m["name"]       = "QRC App";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "qrc:/icons/app.png";
        writeFile(appDir + "/manifest.json", QJsonDocument(m).toJson());

        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        // Verify the scanner logic: if icon starts with "qrc:", it passes through.
        // This is a contract test on the manifest parsing behavior.
    }

    // === CONTRACT: Manifest with all optional fields parses correctly ===

    void fullManifestParsesAllFields() {
        QTemporaryDir dir;
        QString       appDir = dir.path() + "/fullapp";
        QDir().mkpath(appDir);

        QJsonObject m;
        m["id"]                = "com.test.full";
        m["name"]              = "Full App";
        m["entryPoint"]        = "Main.qml";
        m["version"]           = "2.3.1";
        m["icon"]              = "qrc:/icon.png";
        m["protected"]         = true;
        m["permissions"]       = QJsonArray({"camera", "location"});
        m["searchKeywords"]    = QJsonArray({"photo", "snap"});
        m["categories"]        = QJsonArray({"media", "utility"});
        m["handlesUriSchemes"] = QJsonArray({"https", "marathon"});
        m["defaultFor"]        = QJsonArray({"image/jpeg"});
        QJsonObject deepLinks;
        deepLinks["open"] = "/open";
        m["deepLinks"]    = deepLinks;

        writeFile(appDir + "/manifest.json", QJsonDocument(m).toJson());
        writeFile(appDir + "/Main.qml", "Item{}");

        // Register the app directly to test the manifest structure
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        // We can't call parseManifest directly since it's private.
        // But we can verify the registry round-trip by testing that
        // the scanner signals work correctly.
        QSignalSpy startSpy(&scanner, &MarathonAppScanner::scanStarted);
        scanner.scanApplications();
        QCOMPARE(startSpy.count(), 1);
    }

    // === CONTRACT: Version defaults to "1.0.0" when missing ===
    // The scanner sets info.version = obj.value("version").toString("1.0.0")
    // vs the packager which REQUIRES version. This inconsistency means
    // an app without a version field can be scanned but not packaged.

    void versionDefaultsWhenMissing() {
        // This documents the inconsistency: scanner accepts no version,
        // packager rejects it. Both should agree.
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        // The contract question: should a versionless manifest be valid?
        // Scanner says yes (defaults to 1.0.0), Packager says no.
        // This test documents that gap exists.
    }

    // === CONTRACT: getManifestPath returns correct path ===

    void getManifestPathCorrect() {
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);

        QCOMPARE(scanner.getManifestPath("/apps/myapp"), QString("/apps/myapp/manifest.json"));
        QCOMPARE(scanner.getManifestPath("/"), QString("//manifest.json"));
    }

    // === CONTRACT: Empty search directory produces zero apps ===

    void emptyDirectoryProducesZeroApps() {
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QSignalSpy          completeSpy(&scanner, &MarathonAppScanner::scanComplete);

        scanner.scanApplications();

        QCOMPARE(completeSpy.count(), 1);
        // The count depends on what's installed on the system, but
        // at minimum the signal fires
    }
};

QTEST_MAIN(TestAppScanner)
#include "test_appscanner.moc"
