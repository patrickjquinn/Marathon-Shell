// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_REQUEST_H
#define LIBSAILFISHCRYPTO_REQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/cryptomanager.h"
#include "Crypto/result.h"

#include <QtCore/QObject>
#include <QtCore/QVariantMap>

namespace Sailfish {

namespace Crypto {

class SAILFISH_CRYPTO_API Request : public QObject
{
    Q_OBJECT
    Q_PROPERTY(Sailfish::Crypto::CryptoManager* manager READ manager WRITE setManager NOTIFY managerChanged)
    Q_PROPERTY(QVariantMap customParameters READ customParameters WRITE setCustomParameters NOTIFY customParametersChanged)
    Q_PROPERTY(Sailfish::Crypto::Request::Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(Sailfish::Crypto::Result result READ result NOTIFY resultChanged)

public:
    enum Status {
        Inactive = 0,
        Active,
        Finished
    };
    Q_ENUM(Status)

    Request(QObject *parent = Q_NULLPTR);
    virtual ~Request();
    virtual Sailfish::Crypto::CryptoManager *manager() const = 0;
    virtual void setManager(Sailfish::Crypto::CryptoManager *manager) = 0;
    virtual QVariantMap customParameters() const = 0;
    virtual void setCustomParameters(const QVariantMap &params) = 0;
    virtual Sailfish::Crypto::Request::Status status() const = 0;
    virtual Sailfish::Crypto::Result result() const = 0;
    Q_INVOKABLE virtual void startRequest() = 0;
    Q_INVOKABLE virtual void waitForFinished() = 0;

Q_SIGNALS:
    void managerChanged();
    void customParametersChanged();
    void statusChanged();
    void resultChanged();
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_REQUEST_H
