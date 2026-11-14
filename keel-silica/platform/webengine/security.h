// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the object behind Sailfish.WebView's WebView::security on
// Qt WebEngine. Sailfish documents the property as qtmozembed's QMozSecurity
// ("the TLS state and security capabilities of the connection with the
// site"); the member names, the TLS_VERSION enum and the meaning of
// allGood, validState and certIsNull follow qtmozembed's public header
// (github.com/sailfishos/qtmozembed, src/qmozsecurity.h, MPL-2.0; names
// only, no code). The serverCertDetails keys follow
// nemo-qml-plugin-systemsettings' CertificateModel (BSD; names only).
//
// Qt WebEngine does not expose the certificate of a page it loaded, so
// Keel learns it itself: after a page has loaded over https, it opens its
// own TLS connection to the same host and port (QSslSocket, the system's
// CA certificates) and reads the server's certificate, protocol and cipher
// from that handshake. Chromium has already accepted the connection (it
// shows an error page otherwise), so the page is secure; the details are
// the server's at the time Keel asks. A certificate error Chromium reports
// (certificateError) marks the state broken. What Qt WebEngine does not
// report at all stays false: mixed content, tracking protection, extended
// validation.
#ifndef KEEL_WEBENGINE_SECURITY_H
#define KEEL_WEBENGINE_SECURITY_H

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QSslCertificate>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QSslSocket;

class KeelSecurity : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(bool allGood READ allGood NOTIFY changed)
    Q_PROPERTY(QSslCertificate serverCertificate READ serverCertificate NOTIFY changed)
    Q_PROPERTY(bool domainMismatch READ domainMismatch NOTIFY changed)
    Q_PROPERTY(bool notValidAtThisTime READ notValidAtThisTime NOTIFY changed)
    Q_PROPERTY(bool untrusted READ untrusted NOTIFY changed)
    Q_PROPERTY(bool extendedValidation READ falseValue NOTIFY changed)
    Q_PROPERTY(TLS_VERSION protocolVersion READ protocolVersion NOTIFY changed)
    Q_PROPERTY(QString cipherName READ cipherName NOTIFY changed)
    Q_PROPERTY(bool validState READ validState NOTIFY changed)
    Q_PROPERTY(bool isInsecure READ isInsecure NOTIFY changed)
    Q_PROPERTY(bool isBroken READ isBroken NOTIFY changed)
    Q_PROPERTY(bool isSecure READ isSecure NOTIFY changed)
    Q_PROPERTY(bool blockedMixedActiveContent READ falseValue NOTIFY changed)
    Q_PROPERTY(bool loadedMixedActiveContent READ falseValue NOTIFY changed)
    Q_PROPERTY(bool blockedMixedDisplayContent READ falseValue NOTIFY changed)
    Q_PROPERTY(bool loadedMixedDisplayContent READ falseValue NOTIFY changed)
    Q_PROPERTY(bool blockedTrackingContent READ falseValue NOTIFY changed)
    Q_PROPERTY(bool identityEvToplevel READ falseValue NOTIFY changed)
    Q_PROPERTY(bool usesSSL3 READ usesSSL3 NOTIFY changed)
    Q_PROPERTY(bool usesWeakCrypto READ usesWeakCrypto NOTIFY changed)
    Q_PROPERTY(QString subjectDisplayName READ subjectDisplayName NOTIFY changed)
    Q_PROPERTY(QString issuerDisplayName READ issuerDisplayName NOTIFY changed)
    Q_PROPERTY(QString subjectOrganization READ subjectOrganization NOTIFY changed)
    Q_PROPERTY(QDateTime effectiveDate READ effectiveDate NOTIFY changed)
    Q_PROPERTY(QDateTime expiryDate READ expiryDate NOTIFY changed)
    Q_PROPERTY(bool certIsNull READ certIsNull NOTIFY changed)
    Q_PROPERTY(QVariantMap serverCertDetails READ serverCertDetails NOTIFY changed)

public:
    enum TLS_VERSION {
        SSL_VERSION_INVALID = -1,
        SSL_VERSION_3 = 0,
        TLS_VERSION_1 = 1,
        TLS_VERSION_1_1 = 2,
        TLS_VERSION_1_2 = 3,
        TLS_VERSION_1_3 = 4,
    };
    Q_ENUM(TLS_VERSION)

    explicit KeelSecurity(QObject *parent = nullptr);
    ~KeelSecurity() override;

    bool allGood() const;
    QSslCertificate serverCertificate() const { return m_certificate; }
    bool domainMismatch() const { return m_domainMismatch; }
    bool notValidAtThisTime() const { return m_notValidAtThisTime; }
    bool untrusted() const { return m_untrusted; }
    TLS_VERSION protocolVersion() const { return m_protocol; }
    QString cipherName() const { return m_cipher; }
    bool validState() const { return m_state != None; }
    bool isInsecure() const { return m_state == Insecure; }
    bool isBroken() const { return m_state == Broken; }
    bool isSecure() const { return m_state == Secure; }
    bool usesSSL3() const { return m_protocol == SSL_VERSION_3; }
    bool usesWeakCrypto() const;
    QString subjectDisplayName() const;
    QString issuerDisplayName() const;
    QString subjectOrganization() const;
    QDateTime effectiveDate() const { return m_certificate.effectiveDate(); }
    QDateTime expiryDate() const { return m_certificate.expiryDate(); }
    bool certIsNull() const { return m_certificate.isNull(); }
    QVariantMap serverCertDetails() const;
    static bool falseValue() { return false; }

    // A load started: no state until it has finished.
    Q_INVOKABLE void _keelReset();
    // The page at url has loaded (Chromium accepted its connection).
    Q_INVOKABLE void _keelLoaded(const QUrl &url);
    // Chromium refused the page's certificate (WebEngineCertificateError's
    // type: -200 name, -201 date, -202 authority, others broken).
    Q_INVOKABLE void _keelCertificateError(const QUrl &url, int type);

signals:
    void changed();

private:
    enum State { None, Insecure, Broken, Secure };

    void clear();
    void fetchCertificate(const QUrl &url);

    State m_state = None;
    QSslCertificate m_certificate;
    bool m_domainMismatch = false;
    bool m_notValidAtThisTime = false;
    bool m_untrusted = false;
    TLS_VERSION m_protocol = SSL_VERSION_INVALID;
    QString m_cipher;
    QPointer<QSslSocket> m_socket;
};

#endif // KEEL_WEBENGINE_SECURITY_H
