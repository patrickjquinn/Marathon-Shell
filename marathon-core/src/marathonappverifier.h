#pragma once

#include <QObject>
#include <QString>

class MarathonAppVerifier : public QObject {
    Q_OBJECT

  public:
    enum VerificationResult : quint8 {
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

    Q_INVOKABLE MarathonAppVerifier::VerificationResult verifyDirectory(const QString &appDir);

    Q_INVOKABLE bool        signManifest(const QString &manifestPath, const QString &signaturePath,
                                         const QString &keyId = QString());

    Q_INVOKABLE QString     lastError() const {
        return m_lastError;
    }

  signals:
    void verificationStarted();
    void verificationComplete(MarathonAppVerifier::VerificationResult result);
    void error(const QString &message);

  private:
    VerificationResult verifySignatureFile(const QString &manifestPath,
                                           const QString &signaturePath);
    bool    isGPGAvailable();
    QString getTrustedKeysDir();
    bool    initializeTrustedKeysDir();

    QString m_lastError;
};
