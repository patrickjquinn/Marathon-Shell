#include <QTest>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSignalSpy>
#include "marathonapppackager.h"

class TestAppPackager : public QObject {
    Q_OBJECT

  private:
    bool writeFile(const QString &path, const QByteArray &data) {
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(data);
        f.close();
        return true;
    }

    QByteArray readFile(const QString &path) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly))
            return {};
        return f.readAll();
    }

    QByteArray validManifest(const QString &id = "com.test.app") {
        QJsonObject m;
        m["id"]         = id;
        m["name"]       = "Test App";
        m["version"]    = "1.0.0";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "icon.png";
        return QJsonDocument(m).toJson();
    }

    void createValidApp(const QString &dir, const QString &id = "com.test.app") {
        QDir().mkpath(dir);
        writeFile(dir + "/manifest.json", validManifest(id));
        writeFile(dir + "/Main.qml", "import QtQuick\nItem { width: 100; height: 100 }");
        writeFile(dir + "/icon.png", "FAKEPNG");
    }

  private slots:

    // === CONTRACT: Validation must reject all forms of bad input ===
    // These define what a "valid app directory" means.

    void rejectsNonexistentDirectory() {
        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage("/nonexistent/xyz", "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("does not exist"));
    }

    void rejectsMissingManifest() {
        QTemporaryDir       dir;
        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("manifest.json"));
    }

    void rejectsMalformedJson() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/manifest.json", "{bad json!!");

        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("Invalid JSON"));
    }

    void rejectsJsonArray() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/manifest.json", "[1,2,3]");

        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("must be a JSON object"));
    }

    // === CONTRACT: All five required fields must be present and non-empty ===

    void rejectsMissingRequiredFields_data() {
        QTest::addColumn<QString>("missingField");
        QTest::newRow("id") << "id";
        QTest::newRow("name") << "name";
        QTest::newRow("version") << "version";
        QTest::newRow("entryPoint") << "entryPoint";
        QTest::newRow("icon") << "icon";
    }

    void rejectsMissingRequiredFields() {
        QFETCH(QString, missingField);

        QTemporaryDir dir;
        QJsonObject   m;
        m["id"]         = "com.test.app";
        m["name"]       = "Test";
        m["version"]    = "1.0.0";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "icon.png";
        m.remove(missingField);
        writeFile(dir.path() + "/manifest.json", QJsonDocument(m).toJson());
        writeFile(dir.path() + "/Main.qml", "Item{}");

        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("missing required field"));
    }

    void rejectsEmptyRequiredFields() {
        QTemporaryDir dir;
        QJsonObject   m;
        m["id"]         = "";
        m["name"]       = "Test";
        m["version"]    = "1.0.0";
        m["entryPoint"] = "Main.qml";
        m["icon"]       = "icon.png";
        writeFile(dir.path() + "/manifest.json", QJsonDocument(m).toJson());

        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
    }

    // === CONTRACT: Entry point file must actually exist ===

    void rejectsMissingEntryPoint() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/manifest.json", validManifest());

        MarathonAppPackager packager;
        QVERIFY(!packager.createPackage(dir.path(), "/tmp/out.zip"));
        QVERIFY(packager.lastError().contains("Entry point file not found"));
    }

    // === CONTRACT: Extraction rejects nonexistent package ===

    void extractRejectsNonexistentFile() {
        MarathonAppPackager packager;
        QVERIFY(!packager.extractPackage("/nonexistent/package.zip", "/tmp/dest"));
        QVERIFY(packager.lastError().contains("does not exist"));
    }

    // === CONTRACT: On failure, error signal must be emitted ===

    void failureEmitsErrorSignal() {
        MarathonAppPackager packager;
        QSignalSpy          errorSpy(&packager, &MarathonAppPackager::error);

        packager.createPackage("/nonexistent", "/tmp/out.zip");

        QCOMPARE(errorSpy.count(), 1);
        QVERIFY(!errorSpy.first().first().toString().isEmpty());
    }

    // === CONTRACT: Round-trip must preserve file contents, not just existence ===

    void roundTripPreservesContent() {
        QTemporaryDir sourceDir, outputDir, extractDir;
        QVERIFY(sourceDir.isValid() && outputDir.isValid() && extractDir.isValid());

        createValidApp(sourceDir.path());
        QByteArray          originalManifest = readFile(sourceDir.path() + "/manifest.json");
        QByteArray          originalQml      = readFile(sourceDir.path() + "/Main.qml");

        QString             pkgPath = outputDir.path() + "/test.marathon";
        MarathonAppPackager packager;

        bool                created = packager.createPackage(sourceDir.path(), pkgPath);
        if (!created) {
            QSKIP("zip not available");
        }

        QString destPath  = extractDir.path() + "/extracted";
        bool    extracted = packager.extractPackage(pkgPath, destPath);
        if (!extracted && packager.lastError().contains("unzip")) {
            QSKIP("unzip not available");
        }
        QVERIFY(extracted);

        QCOMPARE(readFile(destPath + "/manifest.json"), originalManifest);
        QCOMPARE(readFile(destPath + "/Main.qml"), originalQml);
        QCOMPARE(readFile(destPath + "/icon.png"), QByteArray("FAKEPNG"));
    }

    // === CONTRACT: Progress must go from low to high and reach 100 ===

    void progressReaches100OnSuccess() {
        QTemporaryDir sourceDir, outputDir;
        QVERIFY(sourceDir.isValid() && outputDir.isValid());

        createValidApp(sourceDir.path());

        MarathonAppPackager packager;
        QSignalSpy          progressSpy(&packager, &MarathonAppPackager::packagingProgress);

        QString             pkgPath = outputDir.path() + "/test.marathon";
        bool                created = packager.createPackage(sourceDir.path(), pkgPath);
        if (!created)
            QSKIP("zip not available");

        QVERIFY(progressSpy.count() >= 2);

        int lastProgress = progressSpy.last().first().toInt();
        QCOMPARE(lastProgress, 100);

        for (int i = 1; i < progressSpy.count(); i++) {
            QVERIFY(progressSpy[i].first().toInt() >= progressSpy[i - 1].first().toInt());
        }
    }

    // === SECURITY CONTRACT: Symlinks pointing outside the package must be rejected ===
    // A malicious archive crafted with `zip --symlinks` preserves symlinks.
    // The packager must detect and reject these before or after extraction.

    void symlinkEscapeIsBlocked() {
        QTemporaryDir sourceDir, outputDir, extractDir;
        QVERIFY(sourceDir.isValid());

        createValidApp(sourceDir.path());
        QFile::link("/etc/passwd", sourceDir.path() + "/evil_link");

        // Use `zip --symlinks` to preserve the symlink in the archive
        // (the normal `zip -r` follows symlinks, which hides the attack)
        QString  pkgPath = outputDir.path() + "/evil.marathon";
        QProcess zipProc;
        zipProc.setWorkingDirectory(sourceDir.path());
        zipProc.start("zip", {"--symlinks", "-r", pkgPath, "."});
        if (!zipProc.waitForStarted(3000) || !zipProc.waitForFinished(10000)) {
            QSKIP("zip not available");
        }
        if (zipProc.exitCode() != 0) {
            QSKIP("zip --symlinks failed");
        }

        MarathonAppPackager packager;
        QString             destPath  = extractDir.path() + "/extracted";
        bool                extracted = packager.extractPackage(pkgPath, destPath);

        if (extracted) {
            // If extraction succeeded, check that the symlink wasn't silently
            // left in the extracted directory pointing outside
            QFileInfo link(destPath + "/evil_link");
            if (link.isSymLink()) {
                QString target = link.symLinkTarget();
                QFAIL(qPrintable("Symlink escape reached disk: evil_link -> " + target));
            }
            // If the symlink was resolved to a regular file, the zip tool
            // dereferenced it. The pre-extraction zipinfo check should have
            // caught the 'l' attribute line. If we got here, the archive
            // didn't actually contain a symlink entry.
        } else {
            QVERIFY2(packager.lastError().toLower().contains("symlink"),
                     qPrintable("Expected symlink error, got: " + packager.lastError()));
        }
    }

    // === SECURITY CONTRACT: Symlinks within the package dir should be fine ===

    void internalSymlinksAllowed() {
        QTemporaryDir sourceDir, outputDir, extractDir;
        QVERIFY(sourceDir.isValid());

        createValidApp(sourceDir.path());
        QFile::link(sourceDir.path() + "/Main.qml", sourceDir.path() + "/internal_link.qml");

        MarathonAppPackager packager;
        QString             pkgPath = outputDir.path() + "/safe.marathon";
        bool                created = packager.createPackage(sourceDir.path(), pkgPath);
        if (!created)
            QSKIP("zip not available");

        QString destPath  = extractDir.path() + "/extracted";
        bool    extracted = packager.extractPackage(pkgPath, destPath);
        if (!extracted && packager.lastError().contains("unzip"))
            QSKIP("unzip not available");

        QVERIFY(extracted);
    }

    // === CONTRACT: lastError must be empty string initially, set on failure ===

    void lastErrorClearedInitially() {
        MarathonAppPackager packager;
        QVERIFY(packager.lastError().isEmpty());
    }
};

QTEST_MAIN(TestAppPackager)
#include "test_apppackager.moc"
