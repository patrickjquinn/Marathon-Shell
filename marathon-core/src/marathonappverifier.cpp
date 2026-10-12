#include "marathonappverifier.h"
#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <syslog.h>

MarathonAppVerifier::MarathonAppVerifier(QObject *parent)
    : QObject(parent) {
    initializeTrustedKeysDir();
}

QString MarathonAppVerifier::getTrustedKeysDir() {
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
        "/marathon/trusted-keys";
}

bool MarathonAppVerifier::initializeTrustedKeysDir() {
    QString keysDir = getTrustedKeysDir();
    QDir    dir;
    if (!dir.exists(keysDir)) {
        if (!dir.mkpath(keysDir)) {
            qWarning() << "[MarathonAppVerifier] Failed to create trusted keys directory:"
                       << keysDir;
            return false;
        }
        qDebug() << "[MarathonAppVerifier] Created trusted keys directory:" << keysDir;
    }
    return true;
}

bool MarathonAppVerifier::isGPGAvailable() {
    QProcess gpgCheck;
    gpgCheck.start("gpg", QStringList() << "--version");

    if (!gpgCheck.waitForStarted(3000)) {
        m_lastError = "GPG is not available on this system";
        return false;
    }

    gpgCheck.waitForFinished(3000);
    return gpgCheck.exitCode() == 0;
}

MarathonAppVerifier::VerificationResult
MarathonAppVerifier::verifySignatureFile(const QString &manifestPath,
                                         const QString &signaturePath) {
    if (!isGPGAvailable()) {
        m_lastError = "GPG is not installed or not available";
        return GPGNotAvailable;
    }

    QDir              keysDir(getTrustedKeysDir());
    const QStringList keyFiles =
        keysDir.entryList(QStringList() << "*.asc" << "*.gpg", QDir::Files);
    const bool    strictMode = qEnvironmentVariableIsSet("MARATHON_REQUIRE_SIGNATURES");

    QStringList   args{"--batch", "--status-fd", "1"};
    QTemporaryDir keyring;
    if (keyFiles.isEmpty()) {
        if (strictMode) {
            m_lastError = "No trusted keys configured (strict mode requires trusted keys)";
            qWarning() << "[MarathonAppVerifier] Rejected: no trusted keys in strict mode";
            syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] App rejected - no trusted keys: manifest=%s",
                   manifestPath.toUtf8().constData());
            return UntrustedKey;
        }
        qWarning() << "[MarathonAppVerifier] No trusted keys configured, using the default keyring";
    } else {
        // Verify against a keyring holding only the trusted keys, so a key that
        // merely sits in the user's keyring does not count.
        if (!keyring.isValid()) {
            m_lastError = "Failed to create temporary keyring";
            return VerificationFailed;
        }
        args << "--homedir" << keyring.path() << "--no-autostart";
        QProcess    gpgImport;
        QStringList importArgs = args;
        importArgs << "--import";
        for (const QString &keyFile : keyFiles)
            importArgs << keysDir.filePath(keyFile);
        gpgImport.start("gpg", importArgs);
        if (!gpgImport.waitForFinished(10000) || gpgImport.exitCode() != 0) {
            m_lastError = "Failed to import trusted keys: " +
                QString::fromUtf8(gpgImport.readAllStandardError());
            return VerificationFailed;
        }
    }

    QProcess gpgVerify;
    gpgVerify.start("gpg", args << "--verify" << signaturePath << manifestPath);

    if (!gpgVerify.waitForStarted(3000)) {
        m_lastError = "Failed to start GPG verification process";
        return VerificationFailed;
    }

    if (!gpgVerify.waitForFinished(10000)) {
        m_lastError = "GPG verification process timed out";
        return VerificationFailed;
    }

    const QString status = QString::fromUtf8(gpgVerify.readAllStandardOutput());

    if (gpgVerify.exitCode() == 0 && status.contains("[GNUPG:] VALIDSIG ")) {
        qDebug() << "[MarathonAppVerifier] Signature verification successful";
        if (keyFiles.isEmpty())
            syslog(LOG_AUTH | LOG_WARNING,
                   "[SECURITY] App accepted without trusted key (dev mode): manifest=%s",
                   manifestPath.toUtf8().constData());
        else
            syslog(LOG_AUTH | LOG_INFO, "[SECURITY] App signature verified: manifest=%s",
                   manifestPath.toUtf8().constData());
        return Valid;
    }

    if (status.contains("[GNUPG:] BADSIG ")) {
        m_lastError = "Invalid GPG signature detected";
        qWarning() << "[MarathonAppVerifier] BAD signature detected";
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Invalid app signature: manifest=%s",
               manifestPath.toUtf8().constData());
        return InvalidSignature;
    }

    if (status.contains("[GNUPG:] NO_PUBKEY ")) {
        m_lastError = "Package is signed by a key that is not trusted";
        qWarning() << "[MarathonAppVerifier] Signature from untrusted key";
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] App signed by untrusted key: manifest=%s",
               manifestPath.toUtf8().constData());
        return UntrustedKey;
    }

    const QString output = QString::fromUtf8(gpgVerify.readAllStandardError());
    m_lastError          = "GPG verification failed: " + output;
    qWarning() << "[MarathonAppVerifier] Verification failed:" << output;
    syslog(LOG_AUTH | LOG_WARNING, "[SECURITY] App signature verification failed: manifest=%s",
           manifestPath.toUtf8().constData());
    return InvalidSignature;
}

MarathonAppVerifier::VerificationResult
MarathonAppVerifier::verifyDirectory(const QString &appDir) {
    qDebug() << "[MarathonAppVerifier] Verifying directory:" << appDir;

    emit verificationStarted();

    QDir dir(appDir);
    if (!dir.exists()) {
        m_lastError = "Directory does not exist: " + appDir;
        emit error(m_lastError);
        emit verificationComplete(VerificationFailed);
        return VerificationFailed;
    }

    QString manifestPath = appDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "manifest.json not found in directory";
        emit error(m_lastError);
        emit verificationComplete(ManifestMissing);
        return ManifestMissing;
    }

    QString signaturePath = appDir + "/SIGNATURE.txt";
    if (!QFile::exists(signaturePath)) {
        bool strictMode = qEnvironmentVariableIsSet("MARATHON_REQUIRE_SIGNATURES");
        if (strictMode) {
            m_lastError = "SIGNATURE.txt not found (strict mode requires signatures)";
            qWarning() << "[MarathonAppVerifier] Rejected: no signature in strict mode";
            syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Unsigned app rejected (strict mode): dir=%s",
                   appDir.toUtf8().constData());
            emit error(m_lastError);
            emit verificationComplete(SignatureFileMissing);
            return SignatureFileMissing;
        }
        qWarning() << "[MarathonAppVerifier] SIGNATURE.txt not found (allowing in dev mode)";
        syslog(LOG_AUTH | LOG_WARNING, "[SECURITY] Unsigned app allowed (dev mode): dir=%s",
               appDir.toUtf8().constData());
        emit verificationComplete(Valid);
        return Valid;
    }

    const VerificationResult result = verifySignatureFile(manifestPath, signaturePath);
    if (result != Valid) {
        emit error(m_lastError);
        emit verificationComplete(result);
        return result;
    }

    qDebug() << "[MarathonAppVerifier] Verification successful";
    emit verificationComplete(Valid);
    return Valid;
}

bool MarathonAppVerifier::signManifest(const QString &manifestPath, const QString &signaturePath,
                                       const QString &keyId) {
    qDebug() << "[MarathonAppVerifier] Signing manifest:" << manifestPath;

    if (!isGPGAvailable()) {
        m_lastError = "GPG is not installed or not available";
        return false;
    }

    if (!QFile::exists(manifestPath)) {
        m_lastError = "Manifest file does not exist: " + manifestPath;
        return false;
    }

    QProcess    gpgSign;
    QStringList args;
    args << "--detach-sign" << "--armor" << "--output" << signaturePath;

    if (!keyId.isEmpty()) {
        args << "--local-user" << keyId;
    }

    args << manifestPath;

    gpgSign.start("gpg", args);

    if (!gpgSign.waitForStarted(3000)) {
        m_lastError = "Failed to start GPG signing process";
        return false;
    }

    if (!gpgSign.waitForFinished(30000)) {
        m_lastError = "GPG signing process timed out";
        return false;
    }

    if (gpgSign.exitCode() != 0) {
        QString output = QString::fromUtf8(gpgSign.readAllStandardError());
        m_lastError    = "GPG signing failed: " + output;
        qWarning() << "[MarathonAppVerifier] Signing failed:" << output;
        return false;
    }

    if (!QFile::exists(signaturePath)) {
        m_lastError = "Signature file was not created";
        return false;
    }

    qDebug() << "[MarathonAppVerifier] Manifest signed successfully";
    return true;
}
