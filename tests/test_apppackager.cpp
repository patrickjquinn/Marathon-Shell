#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include "../shell/src/marathonapppackager.h"

class TestAppPackager : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanupTestCase();
    void testCreatePackage();
    void testExtractPackage();
    void testInvalidAppDirectory();
    void testMissingManifest();
    void testInvalidManifest();

  private:
    QTemporaryDir       *tempDir;
    MarathonAppPackager *packager;
    QString              testAppPath;
    QString              packagePath;
};

void TestAppPackager::initTestCase() {
    tempDir = new QTemporaryDir();
    QVERIFY(tempDir->isValid());

    testAppPath = tempDir->path() + "/testapp";
    packagePath = tempDir->path() + "/testapp.marathon";

    packager = new MarathonAppPackager(this);

    // Create a valid test app
    QDir().mkpath(testAppPath);
    QDir().mkpath(testAppPath + "/assets");

    // Create manifest
    QFile manifest(testAppPath + "/manifest.json");
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({
        "id": "test.app",
        "name": "Test App",
        "version": "1.0.0",
        "entryPoint": "TestApp.qml",
        "icon": "assets/icon.svg",
        "author": "Test Author"
    })");
    manifest.close();

    // Create entry point
    QFile qml(testAppPath + "/TestApp.qml");
    QVERIFY(qml.open(QIODevice::WriteOnly));
    qml.write("import QtQuick\nItem { }");
    qml.close();

    // Create icon
    QFile icon(testAppPath + "/assets/icon.svg");
    QVERIFY(icon.open(QIODevice::WriteOnly));
    icon.write("<svg></svg>");
    icon.close();
}

void TestAppPackager::cleanupTestCase() {
    delete packager;
    delete tempDir;
}

void TestAppPackager::testCreatePackage() {
    bool result = packager->createPackage(testAppPath, packagePath);
    QVERIFY2(result, qPrintable(packager->lastError()));

    // Verify package file was created
    QVERIFY(QFile::exists(packagePath));

    // Verify package is not empty
    QFileInfo info(packagePath);
    QVERIFY(info.size() > 0);
}

void TestAppPackager::testExtractPackage() {
    // First create a package
    QVERIFY(packager->createPackage(testAppPath, packagePath));

    // Extract to new location
    QString extractPath = tempDir->path() + "/extracted";
    bool    result      = packager->extractPackage(packagePath, extractPath);
    QVERIFY2(result, qPrintable(packager->lastError()));

    // Verify extracted files exist
    QVERIFY(QFile::exists(extractPath + "/manifest.json"));
    QVERIFY(QFile::exists(extractPath + "/TestApp.qml"));
    QVERIFY(QFile::exists(extractPath + "/assets/icon.svg"));

    // Verify manifest content matches
    QFile originalManifest(testAppPath + "/manifest.json");
    QFile extractedManifest(extractPath + "/manifest.json");

    QVERIFY(originalManifest.open(QIODevice::ReadOnly));
    QVERIFY(extractedManifest.open(QIODevice::ReadOnly));

    QCOMPARE(originalManifest.readAll(), extractedManifest.readAll());
}

void TestAppPackager::testInvalidAppDirectory() {
    QString invalidPath = tempDir->path() + "/nonexistent";
    bool    result      = packager->createPackage(invalidPath, packagePath);

    QVERIFY(!result);
    QVERIFY(!packager->lastError().isEmpty());
}

void TestAppPackager::testMissingManifest() {
    QString noManifestPath = tempDir->path() + "/no-manifest-app";
    QDir().mkpath(noManifestPath);

    bool result = packager->createPackage(noManifestPath, packagePath);

    QVERIFY(!result);
    QVERIFY(packager->lastError().contains("manifest.json"));
}

void TestAppPackager::testInvalidManifest() {
    QString invalidManifestPath = tempDir->path() + "/invalid-manifest-app";
    QDir().mkpath(invalidManifestPath);

    // Create invalid manifest (missing required fields)
    QFile manifest(invalidManifestPath + "/manifest.json");
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({"name": "Incomplete"})"); // Missing id, version, entryPoint, icon
    manifest.close();

    bool result = packager->createPackage(invalidManifestPath, packagePath);

    QVERIFY(!result);
    QVERIFY(packager->lastError().contains("required field"));
}

QTEST_MAIN(TestAppPackager)
#include "test_apppackager.moc"
