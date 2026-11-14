// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CIPHERREQUEST_H
#define LIBSAILFISHCRYPTO_CIPHERREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/cryptomanager.h"
#include "Crypto/request.h"
#include "Crypto/key.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>
#include <QtCore/QByteArray>

namespace Sailfish {

namespace Crypto {

class CipherRequestPrivate;
class SAILFISH_CRYPTO_API CipherRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(CipherMode cipherMode READ cipherMode WRITE setCipherMode NOTIFY cipherModeChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::Operation operation READ operation WRITE setOperation NOTIFY operationChanged)
    Q_PROPERTY(QByteArray data READ data WRITE setData NOTIFY dataChanged)
    Q_PROPERTY(QByteArray initializationVector READ initializationVector WRITE setInitializationVector NOTIFY initializationVectorChanged)
    Q_PROPERTY(Sailfish::Crypto::Key key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::BlockMode blockMode READ blockMode WRITE setBlockMode NOTIFY blockModeChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::EncryptionPadding encryptionPadding READ encryptionPadding WRITE setEncryptionPadding NOTIFY encryptionPaddingChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::SignaturePadding signaturePadding READ signaturePadding WRITE setSignaturePadding NOTIFY signaturePaddingChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::DigestFunction digestFunction READ digestFunction WRITE setDigestFunction NOTIFY digestFunctionChanged)
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(QByteArray generatedData READ generatedData NOTIFY generatedDataChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::VerificationStatus verificationStatus READ verificationStatus NOTIFY verificationStatusChanged)

public:
    enum CipherMode {
        InitializeCipher = 0,
        UpdateCipherAuthentication,
        UpdateCipher,
        FinalizeCipher,
    };
    Q_ENUM(CipherMode)

    CipherRequest(QObject *parent = Q_NULLPTR);
    ~CipherRequest();

    CipherMode cipherMode() const;
    void setCipherMode(CipherMode mode);

    Sailfish::Crypto::CryptoManager::Operation operation() const;
    void setOperation(Sailfish::Crypto::CryptoManager::Operation op);

    QByteArray data() const;
    void setData(const QByteArray &data);

    QByteArray initializationVector() const;
    void setInitializationVector(const QByteArray &iv);

    Sailfish::Crypto::Key key() const;
    void setKey(const Sailfish::Crypto::Key &key);

    Sailfish::Crypto::CryptoManager::BlockMode blockMode() const;
    void setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode);

    Sailfish::Crypto::CryptoManager::EncryptionPadding encryptionPadding() const;
    void setEncryptionPadding(Sailfish::Crypto::CryptoManager::EncryptionPadding padding);

    Sailfish::Crypto::CryptoManager::SignaturePadding signaturePadding() const;
    void setSignaturePadding(Sailfish::Crypto::CryptoManager::SignaturePadding padding);

    Sailfish::Crypto::CryptoManager::DigestFunction digestFunction() const;
    void setDigestFunction(Sailfish::Crypto::CryptoManager::DigestFunction digestFn);

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    QByteArray generatedData() const;
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
    void cipherModeChanged();
    void operationChanged();
    void dataChanged();
    void initializationVectorChanged();
    void keyChanged();
    void blockModeChanged();
    void encryptionPaddingChanged();
    void signaturePaddingChanged();
    void digestFunctionChanged();
    void cryptoPluginNameChanged();
    void generatedDataChanged();
    void verificationStatusChanged();

private:
    QScopedPointer<CipherRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(CipherRequest)
};

} // namespace Crypto

} // namespace Sailfish

Q_DECLARE_METATYPE(Sailfish::Crypto::CipherRequest::CipherMode);

#endif // LIBSAILFISHCRYPTO_CIPHERREQUEST_H
