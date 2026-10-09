// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_DECRYPTREQUEST_H
#define LIBSAILFISHCRYPTO_DECRYPTREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/request.h"
#include "Crypto/key.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QByteArray>

namespace Sailfish {

namespace Crypto {

class CryptoManager;

class DecryptRequestPrivate;
class SAILFISH_CRYPTO_API DecryptRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QByteArray data READ data WRITE setData NOTIFY dataChanged)
    Q_PROPERTY(QByteArray initializationVector READ initializationVector WRITE setInitializationVector NOTIFY initializationVectorChanged)
    Q_PROPERTY(Sailfish::Crypto::Key key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::BlockMode blockMode READ blockMode WRITE setBlockMode NOTIFY blockModeChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::EncryptionPadding padding READ padding WRITE setPadding NOTIFY paddingChanged)
    Q_PROPERTY(QByteArray authenticationData READ authenticationData WRITE setAuthenticationData NOTIFY authenticationDataChanged)
    Q_PROPERTY(QByteArray authenticationTag READ authenticationTag WRITE setAuthenticationTag NOTIFY authenticationTagChanged)
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(QByteArray plaintext READ plaintext NOTIFY plaintextChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::VerificationStatus verificationStatus READ verificationStatus NOTIFY verificationStatusChanged)

public:
    DecryptRequest(QObject *parent = Q_NULLPTR);
    ~DecryptRequest();

    QByteArray data() const;
    void setData(const QByteArray &data);

    QByteArray initializationVector() const;
    void setInitializationVector(const QByteArray &iv);

    Sailfish::Crypto::Key key() const;
    void setKey(const Sailfish::Crypto::Key &key);

    Sailfish::Crypto::CryptoManager::BlockMode blockMode() const;
    void setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode);

    Sailfish::Crypto::CryptoManager::EncryptionPadding padding() const;
    void setPadding(Sailfish::Crypto::CryptoManager::EncryptionPadding padding);

    QByteArray authenticationData() const;
    void setAuthenticationData(const QByteArray &data);

    QByteArray authenticationTag() const;
    void setAuthenticationTag(const QByteArray &authenticationTag);

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    QByteArray plaintext() const;
    Sailfish::Crypto::CryptoManager::VerificationStatus verificationStatus() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void dataChanged();
    void initializationVectorChanged();
    void keyChanged();
    void blockModeChanged();
    void paddingChanged();
    void authenticationDataChanged();
    void authenticationTagChanged();
    void cryptoPluginNameChanged();
    void plaintextChanged();
    void verificationStatusChanged();

private:
    QScopedPointer<DecryptRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(DecryptRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_DECRYPTREQUEST_H
