#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class MarathonAppVerifier : public QObject {
    Q_OBJECT

  public:
    enum VerificationResult {
        Valid,
        InvalidSignature,
        UntrustedKey,
        TamperedManifest,
        SignatureFileMissing,
        ManifestMissing,
        GPGNotAvailable,
        VerificationFailed
    };
    Q_ENUM(VerificationResult)

    explicit MarathonAppVerifier(QObject *parent = nullptr);

    Q_INVOKABLE VerificationResult verifyPackage(const QString &packagePath);
    Q_INVOKABLE VerificationResult verifyDirectory(const QString &appDir);

    Q_INVOKABLE bool        signManifest(const QString &manifestPath, const QString &signaturePath,
                                         const QString &keyId = QString());

    Q_INVOKABLE bool        isTrustedKey(const QString &keyFingerprint);

    Q_INVOKABLE bool        addTrustedKey(const QString &keyPath);
    Q_INVOKABLE bool        removeTrustedKey(const QString &keyFingerprint);

    Q_INVOKABLE QStringList getTrustedKeys();

    Q_INVOKABLE QString     lastError() const {
        return m_lastError;
    }

  signals:
    void verificationStarted();
    void verificationComplete(VerificationResult result);
    void error(const QString &message);

  private:
    bool    verifySignatureFile(const QString &manifestPath, const QString &signaturePath);
    bool    isGPGAvailable();
    QString getTrustedKeysDir();
    bool    initializeTrustedKeysDir();

    QString m_lastError;
};
