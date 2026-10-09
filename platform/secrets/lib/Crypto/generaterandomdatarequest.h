// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_GENERATERANDOMDATAREQUEST_H
#define LIBSAILFISHCRYPTO_GENERATERANDOMDATAREQUEST_H

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

class GenerateRandomDataRequestPrivate;
class SAILFISH_CRYPTO_API GenerateRandomDataRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(QString csprngEngineName READ csprngEngineName WRITE setCsprngEngineName NOTIFY csprngEngineNameChanged)
    Q_PROPERTY(quint64 numberBytes READ numberBytes WRITE setNumberBytes NOTIFY numberBytesChanged)
    Q_PROPERTY(QByteArray generatedData READ generatedData NOTIFY generatedDataChanged)

public:
    static const QString DefaultCsprngEngineName;

    GenerateRandomDataRequest(QObject *parent = Q_NULLPTR);
    ~GenerateRandomDataRequest();

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    QString csprngEngineName() const;
    void setCsprngEngineName(const QString &engineName);

    quint64 numberBytes() const;
    void setNumberBytes(quint64 numberBytes);

    QByteArray generatedData() const;

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
    void csprngEngineNameChanged();
    void numberBytesChanged();
    void generatedDataChanged();

private:
    QScopedPointer<GenerateRandomDataRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(GenerateRandomDataRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_GENERATERANDOMDATAREQUEST_H
