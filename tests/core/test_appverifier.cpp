#include <QTest>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include "marathonappverifier.h"

class TestAppVerifier : public QObject {
    Q_OBJECT

    QTemporaryDir m_root;
    QString       m_gnupgHome;
    QString       m_trustedKeysDir;

    bool          gpg(const QStringList &args, QByteArray *out = nullptr) {
        QProcess p;
        p.start("gpg",
                QStringList{"--homedir", m_gnupgHome, "--batch", "--yes", "--pinentry-mode",
                            "loopback", "--passphrase", ""} +
                    args);
        p.waitForFinished(60000);
        if (out)
            *out = p.readAllStandardOutput();
        return p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    }

    QString signedApp(const QString &uid) {
        const QString dir = m_root.path() + "/app-" + uid;
        QDir().mkpath(dir);
        QFile m(dir + "/manifest.json");
        if (!m.open(QIODevice::WriteOnly))
            return {};
        m.write(R"({"id":"org.test.app","name":"Test","entryPoint":"Main.qml"})");
        m.close();
        if (!gpg({"--local-user", uid, "--detach-sign", "--armor", "--output",
                  dir + "/SIGNATURE.txt", dir + "/manifest.json"}))
            return {};
        return dir;
    }

  private slots:
    void initTestCase() {
        if (QStandardPaths::findExecutable("gpg").isEmpty())
            QSKIP("gpg not installed");
        QVERIFY(m_root.isValid());
        m_gnupgHome = m_root.path() + "/gnupg";
        QDir().mkpath(m_gnupgHome);
        QFile::setPermissions(m_gnupgHome, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv("GNUPGHOME", m_gnupgHome.toUtf8());
        qputenv("XDG_CONFIG_HOME", (m_root.path() + "/config").toUtf8());
        m_trustedKeysDir = m_root.path() + "/config/marathon/trusted-keys";

        QVERIFY(gpg({"--quick-gen-key", "alice@test", "ed25519", "sign", "never"}));
        QVERIFY(gpg({"--quick-gen-key", "mallory@test", "ed25519", "sign", "never"}));

        QByteArray key;
        QVERIFY(gpg({"--armor", "--export", "alice@test"}, &key));
        QDir().mkpath(m_trustedKeysDir);
        QFile f(m_trustedKeysDir + "/trusted.asc");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(key);
    }

    void trustedKeySignatureIsValid() {
        const QString dir = signedApp("alice@test");
        QVERIFY(!dir.isEmpty());
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyDirectory(dir), MarathonAppVerifier::Valid);
    }

    // The signer is in the user's keyring, so gpg reports a good signature,
    // but the key is not in trusted-keys.
    void untrustedKeySignatureIsRejected() {
        const QString dir = signedApp("mallory@test");
        QVERIFY(!dir.isEmpty());
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyDirectory(dir), MarathonAppVerifier::UntrustedKey);
    }

    void tamperedManifestIsRejected() {
        const QString dir = signedApp("alice@test");
        QVERIFY(!dir.isEmpty());
        QFile m(dir + "/manifest.json");
        QVERIFY(m.open(QIODevice::Append));
        m.write(" ");
        m.close();
        MarathonAppVerifier verifier;
        QCOMPARE(verifier.verifyDirectory(dir), MarathonAppVerifier::InvalidSignature);
    }

    void cleanupTestCase() {
        QProcess::execute("gpgconf", {"--homedir", m_gnupgHome, "--kill", "all"});
    }
};

QTEST_GUILESS_MAIN(TestAppVerifier)
#include "test_appverifier.moc"
