// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_CREATECOLLECTIONREQUEST_H
#define LIBSAILFISHSECRETS_CREATECOLLECTIONREQUEST_H

#include "Secrets/secretsglobal.h"
#include "Secrets/request.h"
#include "Secrets/secretmanager.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Secrets {

class CreateCollectionRequestPrivate;
class SAILFISH_SECRETS_API CreateCollectionRequest : public Sailfish::Secrets::Request
{
    Q_OBJECT
    Q_PROPERTY(CollectionLockType collectionLockType READ collectionLockType WRITE setCollectionLockType NOTIFY collectionLockTypeChanged)
    Q_PROPERTY(QString collectionName READ collectionName WRITE setCollectionName NOTIFY collectionNameChanged)
    Q_PROPERTY(QString storagePluginName READ storagePluginName WRITE setStoragePluginName NOTIFY storagePluginNameChanged)
    Q_PROPERTY(QString encryptionPluginName READ encryptionPluginName WRITE setEncryptionPluginName NOTIFY encryptionPluginNameChanged)
    Q_PROPERTY(QString authenticationPluginName READ authenticationPluginName WRITE setAuthenticationPluginName NOTIFY authenticationPluginNameChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic deviceLockUnlockSemantic READ deviceLockUnlockSemantic WRITE setDeviceLockUnlockSemantic NOTIFY deviceLockUnlockSemanticChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic customLockUnlockSemantic READ customLockUnlockSemantic WRITE setCustomLockUnlockSemantic NOTIFY customLockUnlockSemanticChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::AccessControlMode accessControlMode READ accessControlMode WRITE setAccessControlMode NOTIFY accessControlModeChanged)
    Q_PROPERTY(Sailfish::Secrets::SecretManager::UserInteractionMode userInteractionMode READ userInteractionMode WRITE setUserInteractionMode NOTIFY userInteractionModeChanged)

public:
    enum CollectionLockType {
        DeviceLock = 0,
        CustomLock
    };

    CreateCollectionRequest(QObject *parent = Q_NULLPTR);
    ~CreateCollectionRequest();

    CollectionLockType collectionLockType() const;
    void setCollectionLockType(CollectionLockType type);

    QString collectionName() const;
    void setCollectionName(const QString &collectionName);

    QString storagePluginName() const;
    void setStoragePluginName(const QString &pluginName);

    QString encryptionPluginName() const;
    void setEncryptionPluginName(const QString &pluginName);

    QString authenticationPluginName() const;
    void setAuthenticationPluginName(const QString &pluginName);

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
    void collectionLockTypeChanged();
    void collectionNameChanged();
    void storagePluginNameChanged();
    void encryptionPluginNameChanged();
    void authenticationPluginNameChanged();
    void deviceLockUnlockSemanticChanged();
    void customLockUnlockSemanticChanged();
    void accessControlModeChanged();
    void userInteractionModeChanged();

private:
    QScopedPointer<CreateCollectionRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(CreateCollectionRequest)
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_CREATECOLLECTIONREQUEST_H
