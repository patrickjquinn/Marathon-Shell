// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_STORESECRETREQUEST_H
#define LIBSAILFISHSECRETS_STORESECRETREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secret.h"
#include "Secrets/interactionparameters.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Secrets {

class StoreSecretRequestPrivate;
class SAILFISH_SECRETS_API StoreSecretRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(SecretStorageType secretStorageType READ secretStorageType WRITE setSecretStorageType NOTIFY secretStorageTypeChanged)
    Q_PROPERTY(QString encryptionPluginName READ encryptionPluginName WRITE setEncryptionPluginName NOTIFY encryptionPluginNameChanged)
    Q_PROPERTY(QString authenticationPluginName READ authenticationPluginName WRITE setAuthenticationPluginName NOTIFY authenticationPluginNameChanged)
    Q_PROPERTY(Sailfish::Secrets::Secret secret READ secret WRITE setSecret NOTIFY secretChanged)
    Q_PROPERTY(Sailfish::Secrets::InteractionParameters interactionParameters READ interactionParameters WRITE setInteractionParameters NOTIFY interactionParametersChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic deviceLockUnlockSemantic READ deviceLockUnlockSemantic WRITE setDeviceLockUnlockSemantic NOTIFY deviceLockUnlockSemanticChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic customLockUnlockSemantic READ customLockUnlockSemantic WRITE setCustomLockUnlockSemantic NOTIFY customLockUnlockSemanticChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode READ accessControlMode WRITE setAccessControlMode NOTIFY accessControlModeChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode READ userInteractionMode WRITE setUserInteractionMode NOTIFY userInteractionModeChanged)

public:
    enum SecretStorageType {
        CollectionSecret = 0,
        StandaloneDeviceLockSecret,
        StandaloneCustomLockSecret
    };

    StoreSecretRequest(QObject *parent = Q_NULLPTR);
    ~StoreSecretRequest();

    SecretStorageType secretStorageType() const;
    void setSecretStorageType(SecretStorageType semantic);

    QString encryptionPluginName() const;
    void setEncryptionPluginName(const QString &pluginName);

    QString authenticationPluginName() const;
    void setAuthenticationPluginName(const QString &pluginName);

    Sailfish::Secrets::Secret secret() const;
    void setSecret(const Sailfish::Secrets::Secret &secret);

    InteractionParameters interactionParameters() const;
    void setInteractionParameters(const InteractionParameters &params);

    Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic deviceLockUnlockSemantic() const;
    void setDeviceLockUnlockSemantic(Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic semantic);

    Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic customLockUnlockSemantic() const;
    void setCustomLockUnlockSemantic(Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic semantic);

    Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode() const;
    void setAccessControlMode(Sailfish::Secrets::SecretManager::AccessControlMode mode);

    Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode() const;
    void setUserInteractionMode(Sailfish::Secrets::SecretManager::UserInteractionMode mode);

    Sailfish::Secrets::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Secrets::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Secrets::SecretManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Secrets::SecretManager *manager) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void secretStorageTypeChanged();
    void encryptionPluginNameChanged();
    void authenticationPluginNameChanged();
    void secretChanged();
    void interactionParametersChanged();
    void deviceLockUnlockSemanticChanged();
    void customLockUnlockSemanticChanged();
    void accessControlModeChanged();
    void userInteractionModeChanged();

private:
    QScopedPointer<StoreSecretRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(StoreSecretRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_STORESECRETREQUEST_H
