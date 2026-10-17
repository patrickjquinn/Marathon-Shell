#include "marathonappverifier.h"
#include <QDebug>
#include <QStandardPaths>
#include "marathon-core-native/src/lib.rs.h"
#include <syslog.h>
#include <vector>

MarathonAppVerifier::MarathonAppVerifier(QObject *parent)
    : QObject(parent) {}

static std::vector<rust::String> rustStrings(const QStringList &list) {
    std::vector<rust::String> out;
    for (const QString &s : list) {
        const QByteArray utf8 = s.toUtf8();
        out.emplace_back(utf8.constData(), utf8.size());
    }
    return out;
}

QStringList MarathonAppVerifier::trustedKeyDirs() {
    return {QStringLiteral("/usr/share/marathon/trusted-keys"), systemKeyDir(),
            QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                QStringLiteral("/marathon/trusted-keys")};
}

QString MarathonAppVerifier::systemKeyDir() {
    return qEnvironmentVariable("MARATHON_SYSTEM_KEYS_DIR",
                                QStringLiteral("/usr/share/marathon/system-keys"));
}

bool MarathonAppVerifier::isSystemSigner(const QString &keyId) {
    if (keyId.isEmpty())
        return false;
    const QByteArray                id      = keyId.toUtf8();
    const std::vector<rust::String> keys    = rustStrings({systemKeyDir()});
    const std::vector<rust::String> revoked = rustStrings(trustedKeyDirs());
    return marathon::native::key_is_trusted(
        rust::Str(id.constData(), id.size()),
        rust::Slice<const rust::String>(keys.data(), keys.size()),
        rust::Slice<const rust::String>(revoked.data(), revoked.size()));
}

bool MarathonAppVerifier::unsignedAllowed() {
    return qgetenv("MARATHON_ALLOW_UNSIGNED") == "1";
}

MarathonAppVerifier::VerificationResult
MarathonAppVerifier::verifyPackage(const QString &packagePath) {
    emit verificationStarted();
    m_lastError.clear();

    const QByteArray                       archive = packagePath.toUtf8();
    const std::vector<rust::String>        dirs    = rustStrings(trustedKeyDirs());
    const marathon::native::PackageVerdict verdict = marathon::native::verify_package_signature(
        rust::Str(archive.constData(), archive.size()),
        rust::Slice<const rust::String>(dirs.data(), dirs.size()));
    m_signerKeyId             = QString::fromUtf8(verdict.key_id.data(), verdict.key_id.size());
    const QString      detail = QString::fromUtf8(verdict.detail.data(), verdict.detail.size());
    const QByteArray   key    = m_signerKeyId.toUtf8();

    VerificationResult result = VerificationFailed;
    switch (verdict.check) {
        case marathon::native::PackageCheck::Valid:
            syslog(LOG_AUTH | LOG_INFO, "[SECURITY] Package signature verified: package=%s key=%s",
                   archive.constData(), key.constData());
            result = Valid;
            break;
        case marathon::native::PackageCheck::Unsigned:
            if (unsignedAllowed()) {
                qWarning() << "[MarathonAppVerifier] Unsigned package accepted because"
                           << "MARATHON_ALLOW_UNSIGNED=1:" << packagePath;
                syslog(LOG_AUTH | LOG_WARNING,
                       "[SECURITY] Unsigned package allowed by MARATHON_ALLOW_UNSIGNED: package=%s",
                       archive.constData());
                result = AllowedUnsigned;
                break;
            }
            m_lastError = "Package is not signed (no .minisig signature beside it)";
            result      = SignatureMissing;
            break;
        case marathon::native::PackageCheck::InvalidSignature:
            m_lastError = "Invalid signature: " + detail;
            result      = InvalidSignature;
            break;
        case marathon::native::PackageCheck::UntrustedKey:
            m_lastError = "Package is signed by key " + m_signerKeyId + ", which is not trusted";
            result      = UntrustedKey;
            break;
        case marathon::native::PackageCheck::RevokedKey:
            m_lastError = "Package is signed by key " + m_signerKeyId + ", which is revoked";
            result      = RevokedKey;
            break;
        case marathon::native::PackageCheck::Failed:
            m_lastError = "Signature verification failed: " + detail;
            break;
    }

    if (!m_lastError.isEmpty()) {
        qWarning() << "[MarathonAppVerifier] Rejected" << packagePath << ":" << m_lastError;
        syslog(LOG_AUTH | LOG_ALERT, "[SECURITY] Package rejected: package=%s reason=%s",
               archive.constData(), m_lastError.toUtf8().constData());
        emit error(m_lastError);
    }
    emit verificationComplete(result);
    return result;
}

bool MarathonAppVerifier::signPackage(const QString &packagePath, const QString &secretKeyPath) {
    const QByteArray   archive = packagePath.toUtf8();
    const QByteArray   key     = secretKeyPath.toUtf8();
    const rust::String failure = marathon::native::sign_package(
        rust::Str(archive.constData(), archive.size()), rust::Str(key.constData(), key.size()));
    m_lastError = QString::fromUtf8(failure.data(), failure.size());
    return m_lastError.isEmpty();
}
