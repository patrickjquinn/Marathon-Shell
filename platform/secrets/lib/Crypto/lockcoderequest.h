// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_LOCKCODEREQUEST_H
#define LIBSAILFISHCRYPTO_LOCKCODEREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/request.h"
#include "Crypto/cryptomanager.h"
#include "Crypto/interactionparameters.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Crypto {

class LockCodeRequestPrivate;
class SAILFISH_CRYPTO_API LockCodeRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(LockCodeRequestType lockCodeRequestType READ lockCodeRequestType WRITE setLockCodeRequestType NOTIFY lockCodeRequestTypeChanged)
    Q_PROPERTY(LockCodeTargetType lockCodeTargetType READ lockCodeTargetType WRITE setLockCodeTargetType NOTIFY lockCodeTargetTypeChanged)
    Q_PROPERTY(QString lockCodeTarget READ lockCodeTarget WRITE setLockCodeTarget NOTIFY lockCodeTargetChanged)
    Q_PROPERTY(Sailfish::Crypto::InteractionParameters interactionParameters READ interactionParameters WRITE setInteractionParameters NOTIFY interactionParametersChanged)
    Q_PROPERTY(LockStatus lockStatus READ lockStatus NOTIFY lockStatusChanged)

public:
    enum LockCodeRequestType {
        QueryLockStatus = 0,
        ModifyLockCode,
        ProvideLockCode,
        ForgetLockCode
    };
    Q_ENUM(LockCodeRequestType)

    enum LockCodeTargetType {
        MetadataDatabase = 0,
        ExtensionPlugin,
    };
    Q_ENUM(LockCodeTargetType)

    enum LockStatus {
        Unknown = 0,
        Unsupported,
        Unlocked,
        Locked,
    };
    Q_ENUM(LockStatus)

    LockCodeRequest(QObject *parent = Q_NULLPTR);
    ~LockCodeRequest();

    LockCodeRequestType lockCodeRequestType() const;
    void setLockCodeRequestType(LockCodeRequestType type);

    LockCodeTargetType lockCodeTargetType() const;
    void setLockCodeTargetType(LockCodeTargetType type);

    QString lockCodeTarget() const;
    void setLockCodeTarget(const QString &targetName);

    InteractionParameters interactionParameters() const;
    void setInteractionParameters(const InteractionParameters &params);

    LockStatus lockStatus() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void lockCodeRequestTypeChanged();
    void lockCodeTargetTypeChanged();
    void lockCodeTargetChanged();
    void interactionParametersChanged();
    void lockStatusChanged();

private:
    QScopedPointer<LockCodeRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(LockCodeRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_LOCKCODEREQUEST_H
