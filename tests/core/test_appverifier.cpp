#include <QTest>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include "marathonappverifier.h"
#include "minisign_testkeys.h"

class TestAppVerifier : public QObject {
    Q_OBJECT

    QTemporaryDir m_root;
    QString       m_trustedKeysDir;

    QString       package(const QString &name) {
        const QString path = m_root.path() + "/" + name + ".marathon";
        return TestKeys::write(path, "PK\x03\x04 pretend archive " + name.toUtf8()) ? path :
                                                                                      QString();
    }

    QString signedPackage(const QString &name, const TestKeys::Pair &key) {
        const QString path    = package(name);
        const QString keyPath = m_root.path() + "/" + name + ".key";
        if (path.isEmpty() || !TestKeys::write(keyPath, key.secret))
            return {};
        MarathonAppVerifier verifier;
        return verifier.signPackage(path, keyPath) ? path : QString();
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_root.isValid());
        qputenv("XDG_CONFIG_HOME", (m_root.path() + "/config").toUtf8());
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
        m_trustedKeysDir = m_root.path() + "/config/marathon/trusted-keys";
        QCOMPARE(MarathonAppVerifier::trustedKeyDirs().constLast(), m_trustedKeysDir);
        QVERIFY(QDir().mkpath(m_trustedKeysDir));
        QVERIFY(TestKeys::write(m_trustedKeysDir + "/alice.pub", TestKeys::alice.pub));
        QVERIFY(TestKeys::write(m_trustedKeysDir + "/bob.pub", TestKeys::bob.pub));
        QVERIFY(TestKeys::write(m_trustedKeysDir + "/revoked",
                                QByteArray("# test revocation\n") + TestKeys::bob.id + "\n"));
    }

    void cleanup() {
        qunsetenv("MARATHON_ALLOW_UNSIGNED");
    }

    void trustedKeySignatureIsValid() {
        const QString path = signedPackage("alice", TestKeys::alice);
        QVERIFY(!path.isEmpty());
        QVERIFY(QFile::exists(path + ".minisig"));
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::Valid);
        QCOMPARE(verifier.signerKeyId(), QString(TestKeys::alice.id));
    }

    void tamperedArchiveIsRejected() {
        const QString path = signedPackage("tampered", TestKeys::alice);
        QVERIFY(!path.isEmpty());
        QFile f(path);
        QVERIFY(f.open(QIODevice::Append));
        f.write(" ");
        f.close();
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::InvalidSignature);
    }

    void untrustedKeyIsRejected() {
        const QString path = signedPackage("mallory", TestKeys::mallory);
        QVERIFY(!path.isEmpty());
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::UntrustedKey);
        QCOMPARE(verifier.signerKeyId(), QString(TestKeys::mallory.id));
    }

    void revokedKeyIsRejected() {
        const QString path = signedPackage("bob", TestKeys::bob);
        QVERIFY(!path.isEmpty());
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::RevokedKey);
    }

    void unsignedIsRejectedUnlessOverridden() {
        const QString path = package("unsigned");
        QVERIFY(!path.isEmpty());
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::SignatureMissing);
        qputenv("MARATHON_ALLOW_UNSIGNED", "1");
        QCOMPARE(verifier.verifyPackage(path), MarathonAppVerifier::AllowedUnsigned);
    }

    // The override waives the signature, not the checking of one that is there.
    void overrideStillChecksSignatures() {
        qputenv("MARATHON_ALLOW_UNSIGNED", "1");
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyPackage(signedPackage("mallory2", TestKeys::mallory)),
                 MarathonAppVerifier::UntrustedKey);
        QCOMPARE(verifier.verifyPackage(signedPackage("bob2", TestKeys::bob)),
                 MarathonAppVerifier::RevokedKey);
    }

    void signingWithAMissingKeyFails() {
        const QString       path = package("nokey");
        MarathonAppVerifier verifier;
        QVERIFY(!verifier.signPackage(path, m_root.path() + "/missing.key"));
        QVERIFY(!verifier.lastError().isEmpty());
        QVERIFY(!QFile::exists(path + ".minisig"));
    }
};

QTEST_GUILESS_MAIN(TestAppVerifier)
#include "test_appverifier.moc"
