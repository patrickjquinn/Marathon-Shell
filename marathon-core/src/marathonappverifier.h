#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class MarathonAppVerifier : public QObject {
    Q_OBJECT

  public:
    enum VerificationResult : quint8 {
        Valid,
        AllowedUnsigned,
        SignatureMissing,
        InvalidSignature,
        UntrustedKey,
        RevokedKey,
        VerificationFailed
    };
    Q_ENUM(VerificationResult)

    explicit MarathonAppVerifier(QObject *parent = nullptr);

    // Checks <packagePath>.minisig over the archive's bytes. Nothing reads
    // the archive itself, so call this before extracting it.
    Q_INVOKABLE MarathonAppVerifier::VerificationResult verifyPackage(const QString &packagePath);

    // Writes <packagePath>.minisig with a minisign secret key.
    Q_INVOKABLE bool    signPackage(const QString &packagePath, const QString &secretKeyPath);

    Q_INVOKABLE QString lastError() const {
        return m_lastError;
    }
    // Id of the key the last verified package names, empty if unsigned.
    Q_INVOKABLE QString signerKeyId() const {
        return m_signerKeyId;
    }

    static QStringList trustedKeyDirs();
    // MARATHON_ALLOW_UNSIGNED=1: the developer override for unsigned
    // packages and directory installs. Signatures that are present are
    // still checked.
    static bool unsignedAllowed();

  signals:
    void verificationStarted();
    void verificationComplete(MarathonAppVerifier::VerificationResult result);
    void error(const QString &message);

  private:
    QString m_lastError;
    QString m_signerKeyId;
};
