// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/createcollectionrequest.h"
#include "Secrets/createcollectionrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

CreateCollectionRequestPrivate::CreateCollectionRequestPrivate()
    : m_collectionLockType(CreateCollectionRequest::DeviceLock)
    , m_deviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked)
    , m_customLockUnlockSemantic(SecretManager::CustomLockKeepUnlocked)
    , m_accessControlMode(SecretManager::OwnerOnlyMode)
    , m_userInteractionMode(SecretManager::PreventInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype CreateCollectionRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client request that the system secrets service create a collection for secrets storage
  \inherits Request
 */

/*!
  \class CreateCollectionRequest
  \brief Allows a client request that the system secrets service create a collection for secrets storage
  \inmodule SailfishSecrets
  \inheaderfile Secrets/createcollectionrequest.h

  This class allows clients to request the Secrets service to create a collection
  with the particular collectionName(), which will be stored by the storage plugin
  identified by its storagePluginName().

  The collection may be either a device-lock protected collection or a custom-lock
  protected collection, and different unlock semantics may apply in each case.
  Creating a custom-lock collection will also require an authentication flow to
  be specified so that the user can enter an appropriate lock-code or pass-phrase.
  In either case, secrets stored in the collection will be encrypted with a key
  derived from the appropriate authentication code, by the encryption plugin
  identified by its encryptionPluginName().

  If the storagePluginName() and encryptionPluginName() are specified to be the
  same plugin, then that plugin is assumed to be an \tt EncryptedStoragePlugin
  which performs block-level encryption of the entire collection, instead of
  per-value encryption of individual secrets.

  An accessControlMode() may also be specified for the collection, which will be
  enforced by the system secrets service, in order to allow or prevent other
  applications from reading the secret.

  An example of creating a device-lock protected, block-level encrypted collection
  is as follows:

  \code
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::CreateCollectionRequest ccr;
  ccr.setManager(&sm);
  ccr.setCollectionName(QLatin1String("ExampleCollection"));
  ccr.setAccessControlMode(Sailfish::Secrets::SecretManager::OwnerOnlyMode);
  ccr.setCollectionLockType(Sailfish::Secrets::CreateCollectionRequest::DeviceLock);
  ccr.setDeviceLockUnlockSemantic(Sailfish::Secrets::SecretManager::DeviceLockKeepUnlocked);
  ccr.setStoragePluginName(Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName);
  ccr.setEncryptionPluginName(Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName);
  ccr.startRequest(); // status() will change to Finished when complete
  \endcode
 */

/*!
  \brief Constructs a new CreateCollectionRequest object with the given \a parent.
 */
CreateCollectionRequest::CreateCollectionRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new CreateCollectionRequestPrivate)
{
}

/*!
  \brief Destroys the CreateCollectionRequest
 */
CreateCollectionRequest::~CreateCollectionRequest()
{
}

/*!
  \qmlproperty enumeration CreateCollectionRequest::collectionLockType
  \brief The type of lock which will be applied to the created collection.
  \value DeviceLock
  \value CustomLock
 */

/*!
  \brief Returns the type of lock which will be applied to the created collection.

  A collection whose lock type is CreateCollectionRequest::DeviceLock will use the
  device-lock code for its security, whereas a collection whose lock type is
  CreateCollectionRequest::CustomLock will use a separate pass phrase, PIN code, or
  other authentication method.
 */
CreateCollectionRequest::CollectionLockType CreateCollectionRequest::collectionLockType() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_collectionLockType;
}

/*!
  \brief Sets the type of lock which will be applied to the created collection to \a type
 */
void CreateCollectionRequest::setCollectionLockType(CreateCollectionRequest::CollectionLockType type)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_collectionLockType != type) {
        d->m_collectionLockType = type;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit collectionLockTypeChanged();
    }
}

/*!
  \qmlproperty string CreateCollectionRequest::collectionName
  \brief The name of the collection which the client wishes create
 */

/*!
  \brief Returns the name of the collection which the client wishes create
 */
QString CreateCollectionRequest::collectionName() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_collectionName;
}

/*!
  \brief Sets the name of the collection which the client wishes to create to \a name
 */
void CreateCollectionRequest::setCollectionName(const QString &name)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_collectionName != name) {
        d->m_collectionName = name;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit collectionNameChanged();
    }
}

/*!
  \qmlproperty string CreateCollectionRequest::storagePluginName
  \brief The name of the storage plugin which the client wishes to use to create the collection
 */

/*!
  \brief Returns the name of the storage plugin which the client wishes to use to create the collection
  \note When storagePluginName is the same as encryptionPluginName, then it is assumed that the user means an EncryptedStoragePlugin.
 */
QString CreateCollectionRequest::storagePluginName() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_storagePluginName;
}

/*!
  \brief Sets the name of the storage plugin which the client wishes to use to create the collection to \a pluginName
 */
void CreateCollectionRequest::setStoragePluginName(const QString &pluginName)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_storagePluginName != pluginName) {
        d->m_storagePluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit storagePluginNameChanged();
    }
}

/*!
  \qmlproperty string CreateCollectionRequest::encryptionPluginName
  \brief The name of the encryption plugin which the client wishes to use to encrypt secrets stored in the collection
 */

/*!
  \brief Returns the name of the encryption plugin which the client wishes to use to encrypt secrets stored in the collection
  \note When storagePluginName is the same as encryptionPluginName, then it is assumed that the user means an EncryptedStoragePlugin.
 */
QString CreateCollectionRequest::encryptionPluginName() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_encryptionPluginName;
}

/*!
  \brief Sets the name of the encryption plugin which the client wishes to use to encrypt secrets stored in the collection to \a pluginName
 */
void CreateCollectionRequest::setEncryptionPluginName(const QString &pluginName)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_encryptionPluginName != pluginName) {
        d->m_encryptionPluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit encryptionPluginNameChanged();
    }
}

/*!
  \qmlproperty string CreateCollectionRequest::authenticationPluginName
  \brief The name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the collection)
 */

/*!
  \brief Returns the name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the collection)
 */
QString CreateCollectionRequest::authenticationPluginName() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_authenticationPluginName;
}

/*!
  \brief Sets the name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the collection) to \a pluginName

  Note: this will only apply to collections whose collectionLockType() is CreateCollectionRequest::CustomLock.
 */
void CreateCollectionRequest::setAuthenticationPluginName(const QString &pluginName)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_authenticationPluginName != pluginName) {
        d->m_authenticationPluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit authenticationPluginNameChanged();
    }
}

/*!
  \qmlproperty enumeration CreateCollectionRequest::deviceLockUnlockSemantic
  \brief The unlock semantic which will apply to the collection if it is protected by the device lock.
  \value SecretManager.DeviceLockKeepUnlocked unlock after first successful device unlock, stay unlocked.  e.g. background processes.
  \value SecretManager.DeviceLockVerifyLock unlock on device unlock, relock on device lock requiring verify (not passphrase) to unlock on subsequent access.
  \value SecretManager.DeviceLockRelock unlock on device unlock, relock on device lock requiring passphrase to unlock on subsequent access.
 */

/*!
  \brief Returns the unlock semantic which will apply to the collection if it is protected by the device lock.
 */
SecretManager::DeviceLockUnlockSemantic CreateCollectionRequest::deviceLockUnlockSemantic() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_deviceLockUnlockSemantic;
}

/*!
  \brief Sets the unlock semantic which will apply to the collection if it is protected by the device lock to \a semantic.

  Note: this will only apply to collections whose collectionLockType() is CreateCollectionRequest::DeviceLock.
 */
void CreateCollectionRequest::setDeviceLockUnlockSemantic(SecretManager::DeviceLockUnlockSemantic semantic)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_deviceLockUnlockSemantic != semantic) {
        d->m_deviceLockUnlockSemantic = semantic;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit deviceLockUnlockSemanticChanged();
    }
}

/*!
  \qmlproperty enumeration CreateCollectionRequest::customLockUnlockSemantic
  \brief The unlock semantic which will apply to the collection if it is protected by a custom lock.
  \value SecretManager.CustomLockKeepUnlocked unlock after first successful access (with UI flow), stay unlocked.  e.g. background processes.
  \value SecretManager.CustomLockDeviceLockRelock unlock after successful access (with UI flow) after device unlock, relock on device lock.
  \value SecretManager.CustomLockTimoutRelock unlock after successful access (with UI flow) after device unlock, relock after timeout.
  \value SecretManager.CustomLockAccessRelock unlock and relock on every successful access (with UI flow).
 */

/*!
  \brief Returns the unlock semantic which will apply to the collection if it is protected by a custom lock.
 */
SecretManager::CustomLockUnlockSemantic CreateCollectionRequest::customLockUnlockSemantic() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_customLockUnlockSemantic;
}

/*!
  \brief Sets the unlock semantic which will apply to the collection if it is protected by a custom lock to \a semantic.

  Note: this will only apply to collections whose collectionLockType() is CreateCollectionRequest::CustomLock.
 */
void CreateCollectionRequest::setCustomLockUnlockSemantic(SecretManager::CustomLockUnlockSemantic semantic)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_customLockUnlockSemantic != semantic) {
        d->m_customLockUnlockSemantic = semantic;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customLockUnlockSemanticChanged();
    }
}

/*!
  \qmlproperty enumeration CreateCollectionRequest::accessControlMode
  \brief The access control mode which will be enforced for the collection
  \value SecretManager.OwnerOnlyMode no fine-grained access control necessary, only the creating application can access/write/delete.
  \value SecretManager.SystemAccessControlMode  access control via system access control, other applications can access if user gives permission.
  \value SecretManager.NoAccessControlMode other applications can access; use with care (prefer CustomLockAccessRelock)
 */

/*!
  \brief Returns the access control mode which will be enforced for the collection
 */
SecretManager::AccessControlMode CreateCollectionRequest::accessControlMode() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_accessControlMode;
}

/*!
  \brief Sets the access control mode which will be enforced for the collection to \a mode
 */
void CreateCollectionRequest::setAccessControlMode(SecretManager::AccessControlMode mode)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_accessControlMode != mode) {
        d->m_accessControlMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit accessControlModeChanged();
    }
}

/*!
  \qmlproperty enumeration CreateCollectionRequest::userInteractionMode
  \brief The user interaction mode required when creating the collection (e.g. if a custom lock code must be requested from the user)
  \value SecretManager.PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SecretManager.SystemInteraction system-mediated user interaction via system UI if required
  \value SecretManager.ApplicationInteraction in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
 */

/*!
  \brief Returns the user interaction mode required when creating the collection (e.g. if a custom lock code must be requested from the user)
 */
SecretManager::UserInteractionMode CreateCollectionRequest::userInteractionMode() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when creating the collection (e.g. if a custom lock code must be requested from the user) to \a mode

  Note: this will only apply to collections whose collectionLockType() is CreateCollectionRequest::CustomLock.
 */
void CreateCollectionRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

Request::Status CreateCollectionRequest::status() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_status;
}

Result CreateCollectionRequest::result() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_result;
}

SecretManager *CreateCollectionRequest::manager() const
{
    Q_D(const CreateCollectionRequest);
    return d->m_manager.data();
}

void CreateCollectionRequest::setManager(SecretManager *manager)
{
    Q_D(CreateCollectionRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void CreateCollectionRequest::startRequest()
{
    Q_D(CreateCollectionRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result> reply;
        if (d->m_collectionLockType == CreateCollectionRequest::CustomLock) {
            reply = d->m_manager->d_ptr->createCollection(d->m_collectionName,
                                                          d->m_storagePluginName,
                                                          d->m_encryptionPluginName,
                                                          d->m_authenticationPluginName,
                                                          d->m_customLockUnlockSemantic,
                                                          d->m_accessControlMode,
                                                          d->m_userInteractionMode);
        } else {
            reply = d->m_manager->d_ptr->createCollection(d->m_collectionName,
                                                          d->m_storagePluginName,
                                                          d->m_encryptionPluginName,
                                                          d->m_deviceLockUnlockSemantic,
                                                          d->m_accessControlMode);
        }

        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::SecretManagerNotInitializedError,
                                 reply.error().message());
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Secrets::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            emit statusChanged();
            emit resultChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
            });
        }
    }
}

void CreateCollectionRequest::waitForFinished()
{
    Q_D(CreateCollectionRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
