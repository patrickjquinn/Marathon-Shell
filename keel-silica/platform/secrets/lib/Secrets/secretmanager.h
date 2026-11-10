// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRETMANAGER_H
#define LIBSAILFISHSECRETS_SECRETMANAGER_H

#include "Secrets/secret.h"
#include "Secrets/secretsglobal.h"
#include "Secrets/plugininfo.h"

#include <QtCore/QVector>
#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QByteArray>
#include <QtCore/QString>
#include <QtCore/QMap>

namespace Sailfish {

namespace Secrets {

class CreateCollectionRequest;
class DeleteCollectionRequest;
class DeleteSecretRequest;
class FindSecretsRequest;
class InteractionRequest;
class PluginInfoRequest;
class StoredSecretRequest;
class StoreSecretRequest;
class InteractionView;
class SecretManagerPrivate;
class SAILFISH_SECRETS_API SecretManager : public QObject
{
    Q_OBJECT

public:
    enum UserInteractionMode {
         PreventInteraction = 0,            // no user interaction allowed, operation will fail if interaction is required
         SystemInteraction,                 // system-mediated user interaction via system UI if required
         ApplicationInteraction             // in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
    };
    Q_ENUM(UserInteractionMode)

    enum AccessControlMode {
        OwnerOnlyMode = 0,                  // no fine-grained access control necessary, only the creating application can access/write/delete.
        SystemAccessControlMode,            // access control via system access control, other applications can access if user gives permission.
        NoAccessControlMode                 // other applications can access; use with care (prefer CustomLockAccessRelock)
    };
    Q_ENUM(AccessControlMode)

    enum DeviceLockUnlockSemantic {
        DeviceLockKeepUnlocked = 0,         // unlock after first successful device unlock, stay unlocked.  e.g. background processes.
        DeviceLockVerifyLock,               // unlock on device unlock, relock on device lock requiring verify (not passphrase) to unlock on subsequent access.
        DeviceLockRelock,                   // unlock on device unlock, relock on device lock requiring passphrase to unlock on subsequent access.
    };
    Q_ENUM(DeviceLockUnlockSemantic)

    enum CustomLockUnlockSemantic {
        CustomLockKeepUnlocked = 8,         // unlock after first successful access (with UI flow), stay unlocked.  e.g. background processes.
        CustomLockDeviceLockRelock,         // unlock after successful access (with UI flow) after device unlock, relock on device lock.
        CustomLockTimoutRelock,             // unlock after successful access (with UI flow) after device unlock, relock after timeout.
        CustomLockAccessRelock,             // unlock and relock on every successful access (with UI flow).
    };
    Q_ENUM(CustomLockUnlockSemantic)

    enum FilterOperator {
        OperatorOr = 0,
        OperatorAnd
    };
    Q_ENUM(FilterOperator)

    static const QString InAppAuthenticationPluginName;
    static const QString DefaultAuthenticationPluginName;
    static const QString DefaultStoragePluginName;
    static const QString DefaultEncryptionPluginName;
    static const QString DefaultEncryptedStoragePluginName;

    SecretManager(QObject *parent = Q_NULLPTR);
    virtual ~SecretManager();

    bool isInitialized() const;

    // for In-Process UI flows via ApplicationSpecificAuthentication plugins only.
    void registerInteractionView(Sailfish::Secrets::InteractionView *view);

Q_SIGNALS:
    void isInitializedChanged();

protected:
    SecretManagerPrivate *pimpl() const; // for unit tests

private:
    QScopedPointer<SecretManagerPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(SecretManager)
    friend class CollectionNamesRequest;
    friend class CreateCollectionRequest;
    friend class DeleteCollectionRequest;
    friend class DeleteSecretRequest;
    friend class FindSecretsRequest;
    friend class InteractionRequest;
    friend class LockCodeRequest;
    friend class PluginInfoRequest;
    friend class HealthCheckRequest;
    friend class StoredSecretRequest;
    friend class StoreSecretRequest;
};

} // namespace Secrets

} // namespace Sailfish

Q_DECLARE_METATYPE(Sailfish::Secrets::SecretManager::UserInteractionMode)
Q_DECLARE_METATYPE(Sailfish::Secrets::SecretManager::AccessControlMode)
Q_DECLARE_METATYPE(Sailfish::Secrets::SecretManager::DeviceLockUnlockSemantic)
Q_DECLARE_METATYPE(Sailfish::Secrets::SecretManager::CustomLockUnlockSemantic)
Q_DECLARE_METATYPE(Sailfish::Secrets::SecretManager::FilterOperator)

#endif // LIBSAILFISHSECRETS_SECRETMANAGER_H
