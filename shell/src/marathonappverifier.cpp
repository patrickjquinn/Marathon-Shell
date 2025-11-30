#include "marathonappverifier.h"
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QCryptographicHash>

MarathonAppVerifier::MarathonAppVerifier(QObject *parent)
    : QObject(parent) {
    initializeTrustedKeysDir();
}

QString MarathonAppVerifier::getTrustedKeysDir() {
    // User-specific trusted keys
    QString userDir =
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/marathon/trusted-keys";

    // Also check system-wide trusted keys in /usr/share/marathon-shell/trusted-keys/
    // but for now, we'll use user directory
    return userDir;
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

bool MarathonAppVerifier::verifySignatureFile(const QString &manifestPath,
                                              const QString &signaturePath) {
    if (!isGPGAvailable()) {
        m_lastError = "GPG is not installed or not available";
        return false;
    }

    // Import trusted keys to a temporary keyring
    QString     trustedKeysDir = getTrustedKeysDir();
    QDir        keysDir(trustedKeysDir);
    QStringList keyFiles = keysDir.entryList(QStringList() << "*.asc" << "*.gpg", QDir::Files);

    if (keyFiles.isEmpty()) {
        qDebug() << "[MarathonAppVerifier] No trusted keys found, accepting any valid signature "
                    "(DEV MODE)";
        // In development mode, accept any valid signature
        // In production, this should return false
    }

    // Verify signature
    QProcess    gpgVerify;
    QStringList args;
    args << "--verify" << signaturePath << manifestPath;

    gpgVerify.start("gpg", args);

    if (!gpgVerify.waitForStarted(3000)) {
        m_lastError = "Failed to start GPG verification process";
        return false;
    }

    if (!gpgVerify.waitForFinished(10000)) {
        m_lastError = "GPG verification process timed out";
        return false;
    }

    // GPG writes verification output to stderr
    QString output = QString::fromUtf8(gpgVerify.readAllStandardError());

    // Check for "Good signature"
    if (output.contains("Good signature", Qt::CaseInsensitive)) {
        qDebug() << "[MarathonAppVerifier] Signature verification successful";
        return true;
    }

    // Check for "BAD signature"
    if (output.contains("BAD signature", Qt::CaseInsensitive)) {
        m_lastError = "Invalid GPG signature detected";
        qWarning() << "[MarathonAppVerifier] BAD signature detected";
        return false;
    }

    // If no trusted keys and signature is valid, allow in dev mode
    if (keyFiles.isEmpty() && gpgVerify.exitCode() == 0) {
        qDebug() << "[MarathonAppVerifier] No trusted keys configured, accepting valid signature "
                    "(DEV MODE)";
        return true;
    }

    m_lastError = "GPG verification failed: " + output;
    qWarning() << "[MarathonAppVerifier] Verification failed:" << output;
    return false;
}

MarathonAppVerifier::VerificationResult
MarathonAppVerifier::verifyDirectory(const QString &appDir) {
    qDebug() << "[MarathonAppVerifier] Verifying directory:" << appDir;

    emit verificationStarted();

    // Check if directory exists
    QDir dir(appDir);
    if (!dir.exists()) {
        m_lastError = "Directory does not exist: " + appDir;
        emit error(m_lastError);
        emit verificationComplete(VerificationFailed);
        return VerificationFailed;
    }

    // Check for manifest.json
    QString manifestPath = appDir + "/manifest.json";
    if (!QFile::exists(manifestPath)) {
        m_lastError = "manifest.json not found in directory";
        emit error(m_lastError);
        emit verificationComplete(ManifestMissing);
        return ManifestMissing;
    }

    // Check for SIGNATURE.txt
    QString signaturePath = appDir + "/SIGNATURE.txt";
    if (!QFile::exists(signaturePath)) {
        // In development mode, allow unsigned packages
        qWarning() << "[MarathonAppVerifier] SIGNATURE.txt not found (development mode - allowing "
                      "unsigned)";
        emit verificationComplete(Valid);
        return Valid; // For now, allow unsigned in development

        // In production, uncomment this:
        // m_lastError = "SIGNATURE.txt not found in directory";
        // emit error(m_lastError);
        // emit verificationComplete(SignatureFileMissing);
        // return SignatureFileMissing;
    }

    // Verify signature
    if (!verifySignatureFile(manifestPath, signaturePath)) {
        emit error(m_lastError);
        emit verificationComplete(InvalidSignature);
        return InvalidSignature;
    }

    qDebug() << "[MarathonAppVerifier] Verification successful";
    emit verificationComplete(Valid);
    return Valid;
}

MarathonAppVerifier::VerificationResult
MarathonAppVerifier::verifyPackage(const QString &packagePath) {
    qDebug() << "[MarathonAppVerifier] Verifying package:" << packagePath;

    emit verificationStarted();

    // Check if package exists
    if (!QFile::exists(packagePath)) {
        m_lastError = "Package file does not exist: " + packagePath;
        emit error(m_lastError);
        emit verificationComplete(VerificationFailed);
        return VerificationFailed;
    }

    // For .marathon packages, we need to extract and verify
    // This will be called by the installer after extraction

    m_lastError =
        "Direct package verification not yet implemented. Extract first, then verify directory.";
    emit verificationComplete(VerificationFailed);
    return VerificationFailed;
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

    // Create detached signature
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

    // Verify the signature was created
    if (!QFile::exists(signaturePath)) {
        m_lastError = "Signature file was not created";
        return false;
    }

    qDebug() << "[MarathonAppVerifier] Manifest signed successfully";
    return true;
}

bool MarathonAppVerifier::isTrustedKey(const QString &keyFingerprint) {
    QString trustedKeysDir = getTrustedKeysDir();
    QDir    keysDir(trustedKeysDir);

    // Check if any key file matches this fingerprint
    QStringList keyFiles = keysDir.entryList(QStringList() << "*.asc" << "*.gpg", QDir::Files);

    for (const QString &keyFile : keyFiles) {
        if (keyFile.contains(keyFingerprint, Qt::CaseInsensitive)) {
            return true;
        }
    }

    return false;
}

bool MarathonAppVerifier::addTrustedKey(const QString &keyPath) {
    if (!QFile::exists(keyPath)) {
        m_lastError = "Key file does not exist: " + keyPath;
        return false;
    }

    QString trustedKeysDir = getTrustedKeysDir();
    QString fileName       = QFileInfo(keyPath).fileName();
    QString destPath       = trustedKeysDir + "/" + fileName;

    // Copy key to trusted keys directory
    if (QFile::exists(destPath)) {
        if (!QFile::remove(destPath)) {
            m_lastError = "Failed to remove existing key file";
            return false;
        }
    }

    if (!QFile::copy(keyPath, destPath)) {
        m_lastError = "Failed to copy key file to trusted keys directory";
        return false;
    }

    qDebug() << "[MarathonAppVerifier] Added trusted key:" << fileName;
    return true;
}

bool MarathonAppVerifier::removeTrustedKey(const QString &keyFingerprint) {
    QString     trustedKeysDir = getTrustedKeysDir();
    QDir        keysDir(trustedKeysDir);

    QStringList keyFiles = keysDir.entryList(QStringList() << "*.asc" << "*.gpg", QDir::Files);

    for (const QString &keyFile : keyFiles) {
        if (keyFile.contains(keyFingerprint, Qt::CaseInsensitive)) {
            QString fullPath = trustedKeysDir + "/" + keyFile;
            if (QFile::remove(fullPath)) {
                qDebug() << "[MarathonAppVerifier] Removed trusted key:" << keyFile;
                return true;
            } else {
                m_lastError = "Failed to remove key file: " + keyFile;
                return false;
            }
        }
    }

    m_lastError = "Key not found: " + keyFingerprint;
    return false;
}

QStringList MarathonAppVerifier::getTrustedKeys() {
    QString trustedKeysDir = getTrustedKeysDir();
    QDir    keysDir(trustedKeysDir);

    return keysDir.entryList(QStringList() << "*.asc" << "*.gpg", QDir::Files);
}
