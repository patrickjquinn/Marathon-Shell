// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "security.h"

#include <QSslCertificateExtension>
#include <QSslCipher>
#include <QSslKey>
#include <QSslSocket>
#include <QTimer>

namespace {

// QSslCertificate::subjectDisplayName()'s rule (common name, else
// organization, else organizational unit), as qtmozembed documents it.
QString displayName(const QStringList &commonName, const QStringList &organization, const QStringList &unit)
{
    if (!commonName.isEmpty())
        return commonName.first();
    if (!organization.isEmpty())
        return organization.first();
    return unit.value(0);
}

QVariantMap nameMap(const QSslCertificate &certificate, bool subject)
{
    QVariantMap map;
    const QList<QByteArray> attributes = subject ? certificate.subjectInfoAttributes()
                                                 : certificate.issuerInfoAttributes();
    for (const QByteArray &attribute : attributes) {
        const QStringList values = subject ? certificate.subjectInfo(attribute) : certificate.issuerInfo(attribute);
        map.insert(QString::fromLatin1(attribute), values.join(QStringLiteral(", ")));
    }
    return map;
}

KeelSecurity::TLS_VERSION tlsVersion(QSsl::SslProtocol protocol)
{
    // TLS 1.0 and 1.1 are deprecated in Qt, but a server may still use them.
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    switch (protocol) {
    case QSsl::TlsV1_0:
        return KeelSecurity::TLS_VERSION_1;
    case QSsl::TlsV1_1:
        return KeelSecurity::TLS_VERSION_1_1;
    case QSsl::TlsV1_2:
        return KeelSecurity::TLS_VERSION_1_2;
    case QSsl::TlsV1_3:
        return KeelSecurity::TLS_VERSION_1_3;
    default:
        return KeelSecurity::SSL_VERSION_INVALID;
    }
    QT_WARNING_POP
}

} // namespace

KeelSecurity::KeelSecurity(QObject *parent)
    : QObject(parent)
{
}

KeelSecurity::~KeelSecurity()
{
    delete m_socket;
}

// qtmozembed's rule: secure, no certificate problem, a named subject and
// no weak cryptography (mixed content is not reported by Qt WebEngine).
bool KeelSecurity::allGood() const
{
    return m_state == Secure && !m_domainMismatch && !m_notValidAtThisTime && !m_untrusted
            && !subjectDisplayName().isEmpty() && !usesWeakCrypto();
}

bool KeelSecurity::usesWeakCrypto() const
{
    static const char *const weak[] = { "RC4", "DES-CBC-", "NULL", "EXP", "MD5" };
    for (const char *w : weak) {
        if (m_cipher.contains(QLatin1String(w)))
            return true;
    }
    return m_protocol == SSL_VERSION_3;
}

QString KeelSecurity::subjectDisplayName() const
{
    return displayName(m_certificate.subjectInfo(QSslCertificate::CommonName),
                       m_certificate.subjectInfo(QSslCertificate::Organization),
                       m_certificate.subjectInfo(QSslCertificate::OrganizationalUnitName));
}

QString KeelSecurity::issuerDisplayName() const
{
    return displayName(m_certificate.issuerInfo(QSslCertificate::CommonName),
                       m_certificate.issuerInfo(QSslCertificate::Organization),
                       m_certificate.issuerInfo(QSslCertificate::OrganizationalUnitName));
}

QString KeelSecurity::subjectOrganization() const
{
    return m_certificate.subjectInfo(QSslCertificate::Organization).value(0);
}

// The keys CertificateModel's details() has; values from QSslCertificate.
QVariantMap KeelSecurity::serverCertDetails() const
{
    if (m_certificate.isNull())
        return {};
    QVariantMap details;
    details.insert(QStringLiteral("Version"), QString::fromLatin1(m_certificate.version()));
    details.insert(QStringLiteral("SerialNumber"), QString::fromLatin1(m_certificate.serialNumber()));
    details.insert(QStringLiteral("SubjectDisplayName"), subjectDisplayName());
    details.insert(QStringLiteral("OrganizationName"), subjectOrganization());
    details.insert(QStringLiteral("IssuerDisplayName"), issuerDisplayName());
    details.insert(QStringLiteral("Validity"),
                   QVariantMap { { QStringLiteral("NotBefore"), m_certificate.effectiveDate() },
                                 { QStringLiteral("NotAfter"), m_certificate.expiryDate() } });
    details.insert(QStringLiteral("Issuer"), nameMap(m_certificate, false));
    details.insert(QStringLiteral("Subject"), nameMap(m_certificate, true));
    const QSslKey key = m_certificate.publicKey();
    QVariantMap publicKey;
    if (!key.isNull()) {
        const char *algorithm = key.algorithm() == QSsl::Rsa ? "rsaEncryption"
                : key.algorithm() == QSsl::Ec               ? "id-ecPublicKey"
                : key.algorithm() == QSsl::Dsa              ? "dsaEncryption"
                                                            : "unknown";
        publicKey.insert(QStringLiteral("Algorithm"), QString::fromLatin1(algorithm));
        publicKey.insert(QStringLiteral("Bits"), QString::number(key.length()));
    }
    details.insert(QStringLiteral("SubjectPublicKeyInfo"), publicKey);
    QVariantMap extensions;
    const QList<QSslCertificateExtension> list = m_certificate.extensions();
    for (const QSslCertificateExtension &extension : list) {
        QString name = extension.name();
        if (extension.isCritical())
            name.append(QStringLiteral(" (Critical)"));
        extensions.insert(name, extension.value().toString());
    }
    details.insert(QStringLiteral("Extensions"), extensions);
    details.insert(QStringLiteral("Signature"), QVariantMap());
    return details;
}

void KeelSecurity::clear()
{
    delete m_socket;
    m_state = None;
    m_certificate = QSslCertificate();
    m_domainMismatch = m_notValidAtThisTime = m_untrusted = false;
    m_protocol = SSL_VERSION_INVALID;
    m_cipher.clear();
}

void KeelSecurity::_keelReset()
{
    clear();
    emit changed();
}

void KeelSecurity::_keelLoaded(const QUrl &url)
{
    if (m_state == Broken)
        return;
    clear();
    const QString scheme = url.scheme();
    if (scheme == QLatin1String("https") || scheme == QLatin1String("wss")) {
        m_state = Secure;
        fetchCertificate(url);
    } else if (scheme == QLatin1String("http") || scheme == QLatin1String("ws")) {
        m_state = Insecure;
    }
    // Other schemes (file, data, about, qrc): no connection, no state.
    emit changed();
}

void KeelSecurity::_keelCertificateError(const QUrl &url, int type)
{
    clear();
    m_state = Broken;
    m_domainMismatch = type == -200;
    m_notValidAtThisTime = type == -201;
    m_untrusted = type != -200 && type != -201;
    fetchCertificate(url);
    emit changed();
}

void KeelSecurity::fetchCertificate(const QUrl &url)
{
    // KEEL_WEBVIEW_CERTIFICATES=0: no connection of Keel's own (tests,
    // offline hosts); the state stays, without certificate details.
    if (!QSslSocket::supportsSsl() || qEnvironmentVariable("KEEL_WEBVIEW_CERTIFICATES") == QLatin1String("0"))
        return;
    auto *socket = new QSslSocket(this);
    m_socket = socket;
    const bool broken = m_state == Broken;
    connect(socket, &QSslSocket::sslErrors, socket, [this, socket, broken](const QList<QSslError> &errors) {
        // Keel's own handshake: the errors describe the certificate (the
        // page itself was already accepted or refused by Chromium).
        for (const QSslError &error : errors) {
            switch (error.error()) {
            case QSslError::HostNameMismatch:
                m_domainMismatch = true;
                break;
            case QSslError::CertificateExpired:
            case QSslError::CertificateNotYetValid:
                m_notValidAtThisTime = true;
                break;
            default:
                m_untrusted = true;
                break;
            }
        }
        if (!broken && (m_domainMismatch || m_notValidAtThisTime || m_untrusted))
            m_state = Broken;
        socket->ignoreSslErrors();
    });
    connect(socket, &QSslSocket::encrypted, socket, [this, socket]() {
        m_certificate = socket->peerCertificate();
        m_protocol = tlsVersion(socket->sessionProtocol());
        m_cipher = socket->sessionCipher().name();
        socket->disconnectFromHost();
        socket->deleteLater();
        emit changed();
    });
    connect(socket, &QSslSocket::errorOccurred, socket, [this, socket]() {
        socket->deleteLater();
        emit changed();
    });
    // Abandoned after 15 s (no answer): the state stays, without details.
    QTimer::singleShot(15000, socket, &QObject::deleteLater);
    socket->setPeerVerifyName(url.host());
    socket->connectToHostEncrypted(url.host(), static_cast<quint16>(url.port(443)));
}
