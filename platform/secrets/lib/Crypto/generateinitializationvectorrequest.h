// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Bea Lam <bea.lam@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_GENERATEDINITIALIZATIONVECTORREQUEST_H
#define LIBSAILFISHCRYPTO_GENERATEDINITIALIZATIONVECTORREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/cryptomanager.h"
#include "Crypto/request.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QByteArray>

namespace Sailfish {

namespace Crypto {

class GenerateInitializationVectorRequestPrivate;
class SAILFISH_CRYPTO_API GenerateInitializationVectorRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::Algorithm algorithm READ algorithm WRITE setAlgorithm NOTIFY algorithmChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::BlockMode blockMode READ blockMode WRITE setBlockMode NOTIFY blockModeChanged)
    Q_PROPERTY(int keySize READ keySize WRITE setKeySize NOTIFY keySizeChanged)
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(QByteArray generatedInitializationVector READ generatedInitializationVector NOTIFY generatedInitializationVectorChanged)

public:
    GenerateInitializationVectorRequest(QObject *parent = Q_NULLPTR);
    ~GenerateInitializationVectorRequest();

    Sailfish::Crypto::CryptoManager::Algorithm algorithm() const;
    void setAlgorithm(Sailfish::Crypto::CryptoManager::Algorithm algorithm);

    Sailfish::Crypto::CryptoManager::BlockMode blockMode() const;
    void setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode);

    int keySize() const;
    void setKeySize(int keySize);

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    QByteArray generatedInitializationVector() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void algorithmChanged();
    void blockModeChanged();
    void keySizeChanged();
    void cryptoPluginNameChanged();
    void generatedInitializationVectorChanged();

private:
    QScopedPointer<GenerateInitializationVectorRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(GenerateInitializationVectorRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_GENERATEDINITIALIZATIONVECTORREQUEST_H
