#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include "../shell/src/marathonappverifier.h"

class TestAppVerifier : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanupTestCase();
    void testVerifyValidSignature();
    void testVerifyInvalidSignature();
    void testVerifyMissingSignature();
    void testVerifyMissingManifest();
    void testSignManifest();
    void testTrustedKeyManagement();

  private:
    QTemporaryDir       *tempDir;
    MarathonAppVerifier *verifier;
    QString              testAppPath;
};

void TestAppVerifier::initTestCase() {
    tempDir = new QTemporaryDir();
    QVERIFY(tempDir->isValid());

    testAppPath = tempDir->path() + "/testapp";
    QDir().mkpath(testAppPath);

    verifier = new MarathonAppVerifier(this);
}

void TestAppVerifier::cleanupTestCase() {
    delete verifier;
    delete tempDir;
}

void TestAppVerifier::testVerifyValidSignature() {
    // Create test manifest
    QString manifestPath = testAppPath + "/manifest.json";
    QFile   manifest(manifestPath);
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({
        "id": "test.app",
        "name": "Test App",
        "version": "1.0.0",
        "entryPoint": "TestApp.qml",
        "icon": "icon.svg"
    })");
    manifest.close();

    // Sign the manifest
    QString signaturePath = testAppPath + "/SIGNATURE.txt";
    bool signed           = verifier->signManifest(manifestPath, signaturePath);

    // In dev mode (no trusted keys), this should succeed if GPG is available
    // If GPG is not available, skip this test
    if (!signed) {
        QSKIP("GPG not available or key not configured");
        return;
    }

    // Verify the signature
    auto result = verifier->verifyDirectory(testAppPath);
    QVERIFY(result == MarathonAppVerifier::Valid ||
            result == MarathonAppVerifier::SignatureFileMissing); // Dev mode allows unsigned
}

void TestAppVerifier::testVerifyInvalidSignature() {
    QString manifestPath  = testAppPath + "/manifest.json";
    QString signaturePath = testAppPath + "/SIGNATURE.txt";

    // Create manifest and sign it
    QFile manifest(manifestPath);
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({"id": "test", "name": "Test"})");
    manifest.close();

    if (!verifier->signManifest(manifestPath, signaturePath)) {
        QSKIP("GPG not available");
        return;
    }

    // Modify manifest after signing (tamper with it)
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({"id": "hacked", "name": "Hacked"})");
    manifest.close();

    // Verification should detect tampering
    auto result = verifier->verifyDirectory(testAppPath);
    QVERIFY(result == MarathonAppVerifier::InvalidSignature ||
            result == MarathonAppVerifier::TamperedManifest);
}

void TestAppVerifier::testVerifyMissingSignature() {
    QString appPath = tempDir->path() + "/unsigned-app";
    QDir().mkpath(appPath);

    // Create manifest without signature
    QFile manifest(appPath + "/manifest.json");
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({"id": "unsigned", "name": "Unsigned"})");
    manifest.close();

    // In development mode, apps without signatures are allowed
    auto result = verifier->verifyDirectory(appPath);
    QVERIFY(result == MarathonAppVerifier::Valid); // Dev mode allows unsigned
}

void TestAppVerifier::testVerifyMissingManifest() {
    QString appPath = tempDir->path() + "/no-manifest-app";
    QDir().mkpath(appPath);

    // No manifest.json file
    auto result = verifier->verifyDirectory(appPath);
    QCOMPARE(result, MarathonAppVerifier::ManifestMissing);
}

void TestAppVerifier::testSignManifest() {
    QString manifestPath  = testAppPath + "/test-manifest.json";
    QString signaturePath = testAppPath + "/test-signature.txt";

    QFile   manifest(manifestPath);
    QVERIFY(manifest.open(QIODevice::WriteOnly));
    manifest.write(R"({"test": "data"})");
    manifest.close();

    bool result = verifier->signManifest(manifestPath, signaturePath);

    if (!result) {
        QSKIP("GPG not available or not configured");
        return;
    }

    // Verify signature file was created
    QVERIFY(QFile::exists(signaturePath));

    // Signature should not be empty
    QFile sig(signaturePath);
    QVERIFY(sig.open(QIODevice::ReadOnly));
    QByteArray data = sig.readAll();
    QVERIFY(!data.isEmpty());
    QVERIFY(data.contains("BEGIN PGP SIGNATURE"));
}

void TestAppVerifier::testTrustedKeyManagement() {
    // Test adding trusted keys
    QString keyPath = tempDir->path() + "/test-key.asc";
    QFile   key(keyPath);
    QVERIFY(key.open(QIODevice::WriteOnly));
    key.write("-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest\n-----END PGP PUBLIC KEY BLOCK-----");
    key.close();

    // Add trusted key
    bool added = verifier->addTrustedKey(keyPath);
    QVERIFY(added);

    // Verify key was added
    QStringList keys = verifier->getTrustedKeys();
    QVERIFY(keys.size() > 0);
}

QTEST_MAIN(TestAppVerifier)
#include "test_appverifier.moc"
