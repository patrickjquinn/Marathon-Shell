// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CALCULATEDIGESTREQUEST_H
#define LIBSAILFISHCRYPTO_CALCULATEDIGESTREQUEST_H

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

class CalculateDigestRequestPrivate;
class SAILFISH_CRYPTO_API CalculateDigestRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QByteArray data READ data WRITE setData NOTIFY dataChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::SignaturePadding padding READ padding WRITE setPadding NOTIFY paddingChanged)
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::DigestFunction digestFunction READ digestFunction WRITE setDigestFunction NOTIFY digestFunctionChanged)
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(QByteArray digest READ digest NOTIFY digestChanged)

public:
    CalculateDigestRequest(QObject *parent = Q_NULLPTR);
    ~CalculateDigestRequest();

    QByteArray data() const;
    void setData(const QByteArray &data);

    Sailfish::Crypto::CryptoManager::SignaturePadding padding() const;
    void setPadding(Sailfish::Crypto::CryptoManager::SignaturePadding padding);

    Sailfish::Crypto::CryptoManager::DigestFunction digestFunction() const;
    void setDigestFunction(Sailfish::Crypto::CryptoManager::DigestFunction digest);

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    QByteArray digest() const;

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
    void paddingChanged();
    void digestFunctionChanged();
    void cryptoPluginNameChanged();
    void digestChanged();

private:
    QScopedPointer<CalculateDigestRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(CalculateDigestRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_CALCULATEDIGESTREQUEST_H
