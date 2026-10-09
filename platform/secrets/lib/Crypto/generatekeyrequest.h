// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_GENERATEKEYREQUEST_H
#define LIBSAILFISHCRYPTO_GENERATEKEYREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/request.h"
#include "Crypto/key.h"
#include "Crypto/keypairgenerationparameters.h"
#include "Crypto/keyderivationparameters.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Crypto {

class CryptoManager;

class GenerateKeyRequestPrivate;
class SAILFISH_CRYPTO_API GenerateKeyRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(Sailfish::Crypto::KeyDerivationParameters keyDerivationParameters READ keyDerivationParameters WRITE setKeyDerivationParameters NOTIFY keyDerivationParametersChanged)
    Q_PROPERTY(Sailfish::Crypto::KeyPairGenerationParameters keyPairGenerationParameters READ keyPairGenerationParameters WRITE setKeyPairGenerationParameters NOTIFY keyPairGenerationParametersChanged)
    Q_PROPERTY(Sailfish::Crypto::Key keyTemplate READ keyTemplate WRITE setKeyTemplate NOTIFY keyTemplateChanged)
    Q_PROPERTY(Sailfish::Crypto::Key generatedKey READ generatedKey NOTIFY generatedKeyChanged)

public:
    GenerateKeyRequest(QObject *parent = Q_NULLPTR);
    ~GenerateKeyRequest();

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    Sailfish::Crypto::KeyDerivationParameters keyDerivationParameters() const;
    void setKeyDerivationParameters(const Sailfish::Crypto::KeyDerivationParameters &params);

    Sailfish::Crypto::KeyPairGenerationParameters keyPairGenerationParameters() const;
    void setKeyPairGenerationParameters(const Sailfish::Crypto::KeyPairGenerationParameters &params);

    Sailfish::Crypto::Key keyTemplate() const;
    void setKeyTemplate(const Sailfish::Crypto::Key &key);

    Sailfish::Crypto::Key generatedKey() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void cryptoPluginNameChanged();
    void keyDerivationParametersChanged();
    void keyPairGenerationParametersChanged();
    void keyTemplateChanged();
    void generatedKeyChanged();

private:
    QScopedPointer<GenerateKeyRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(GenerateKeyRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_GENERATEKEYREQUEST_H
