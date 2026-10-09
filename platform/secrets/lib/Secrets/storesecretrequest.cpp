// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/storesecretrequest.h"
#include "Secrets/storesecretrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

StoreSecretRequestPrivate::StoreSecretRequestPrivate()
    : m_secretStorageType(StoreSecretRequest::CollectionSecret)
    , m_deviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked)
    , m_customLockUnlockSemantic(SecretManager::CustomLockKeepUnlocked)
    , m_accessControlMode(SecretManager::OwnerOnlyMode)
    , m_userInteractionMode(SecretManager::PreventInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype StoreSecretRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client request that the system secrets service securely store a secret
  \inherits Request
*/

/*!
  \class StoreSecretRequest
  \brief Allows a client request that the system secrets service securely store a secret
  \inmodule SailfishSecrets
  \inheaderfile Secrets/storesecretrequest.h

  This class allows clients to request the Secrets service to store a secret
  (either in a particular collection or as a standalone secret) in a particular
  storage plugin.

  Note that the filter data defined in the secret will be encrypted
  prior to storage only if the secret is stored in a collection and that collection
  is stored by an EncryptedStoragePlugin; otherwise, only the identifier and data
  will be stored in encrypted form.

  If the calling application is the creator of the collection specified in the
  secret's identifier, or alternatively if the user has granted the application
  permission to modify that collection and either there are no special access controls
  associated with the particular secret or the secret does not yet exist, then the
  Secrets service will instruct the storage plugin to store the secret into the collection.

  If the application is not the creator of the collection and the user has not yet
  been asked if the application should have permission to modify the collection,
  or if the secret already exists and has specific access controls associated with
  it but the user has not yet been asked whether the application should have permission
  to modify the secret, then a system-mediated access control UI flow may be triggered
  to obtain the user's permission (unless the given \a userInteractionMode is
  \a PreventInteraction in which case the request will fail).

  Alternatively, if the secret is a standalone secret, and a standalone secret with
  that identifier already exists and was created by another application,
  but the \a accessControlMode is \c OwnerOnlyMode, the request will fail,
  as applications are not able to steal ownership from other applications.

  If the collection uses an encryption key derived from the system device-lock,
  then the value will be able to be stored without any other UI flow being required;
  however, if the collection uses an encryption key derived from a custom lock,
  then the custom lock authentication key will be obtained from the user via
  an authentication flow determined by the authentication plugin used for that
  collection (which may support \c ApplicationInteraction if the collection
  is an application-specific collection using an \c ApplicationSpecificAuthentication
  plugin, but otherwise will be a system-mediated UI flow, unless the \a userInteractionMode
  specified is \c PreventInteraction in which case the request will fail).

  If the secret is a standalone secret protected by a custom-lock rather than
  the system device-lock, then an authentication flow will be required in order
  to retrieve a custom lock code or passphrase from the user.

  An example of storing a secret into a pre-existing collection is as follows:

  \code
  // Define the secret.
  Sailfish::Secrets::Secret exampleSecret(
          Sailfish::Secrets::Secret::Identifier(
                  QLatin1String("ExampleSecret"),
                  QLatin1String("ExampleCollection"),
                  Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName));
  exampleSecret.setData("Some secret data");
  exampleSecret.setType(Sailfish::Secrets::Secret::TypeBlob);
  exampleSecret.setFilterData(QLatin1String("domain"),
                              QLatin1String("sailfishos.org"));
  exampleSecret.setFilterData(QLatin1String("example"),
                              QLatin1String("true"));

  // Request that the secret be securely stored.
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::StoreSecretRequest ssr;
  ssr.setManager(&sm);
  ssr.setSecretStorageType(Sailfish::Secrets::StoreSecretRequest::CollectionSecret);
  ssr.setUserInteractionMode(Sailfish::Secrets::SecretManager::SystemInteraction);
  ssr.setSecret(exampleSecret);
  ssr.startRequest(); // status() will change to Finished when complete
  \endcode

  An example of storing a standalone secret protected by the device lock is:

  \code
  // Define a standalone secret (no collection name specified in the identifier)
  Sailfish::Secrets::Secret standaloneSecret(
          Sailfish::Secrets::Secret::Identifier(
               QStringLiteral("StandaloneSecret"),
               QString(),
               Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName));
  standaloneSecret.setData("Example secret data");
  standaloneSecret.setType(Secret::TypeBlob);
  standaloneSecret.setFilterData(QLatin1String("domain"),
                                 QLatin1String("sailfishos.org"));
  standaloneSecret.setFilterData(QLatin1String("example"),
                                 QLatin1String("true"));

  // Request that the secret be stored by the default storage plugin
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::StoreSecretRequest ssr;
  ssr.setManager(&sm);
  ssr.setSecretStorageType(StoreSecretRequest::StandaloneDeviceLockSecret);
  ssr.setDeviceLockUnlockSemantic(Sailfish::Secrets::SecretManager::DeviceLockKeepUnlocked);
  ssr.setAccessControlMode(Sailfish::Secrets::SecretManager::OwnerOnlyMode);
  ssr.setEncryptionPluginName(Sailfish::Secrets::SecretManager::DefaultEncryptionPluginName);
  ssr.setUserInteractionMode(Sailfish::Secrets::SecretManager::SystemInteraction);
  ssr.setSecret(standaloneSecret);
  ssr.startRequest(); // status() will change to Finished when complete
  \endcode

  An example of storing a secret into a pre-existing collection, where the
  secret data is requested securely from the user by the secrets service
  prior to storage, follows:

  \code
  // Define the secret data request prompt parameters.
  Sailfish::Secrets::InteractionParameters uiParams;
  uiParams.setInputType(Sailfish::Secrets::InteractionParameters::AlphaNumericInput);
  uiParams.setEchoMode(Sailfish::Secrets::InteractionParameters::NormalEcho);

  // Define the secret.  Note that it contains metadata only.
  Sailfish::Secrets::Secret exampleSecret(
          Sailfish::Secrets::Secret::Identifier(
                  QLatin1String("ExampleSecret"),
                  QLatin1String("ExampleCollection"),
                  Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName));
  exampleSecret.setType(Sailfish::Secrets::Secret::TypeBlob);
  exampleSecret.setFilterData(QLatin1String("domain"),
                              QLatin1String("sailfishos.org"));
  exampleSecret.setFilterData(QLatin1String("example"),
                              QLatin1String("true"));

  // Request that the secret be securely stored.
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::StoreSecretRequest ssr;
  ssr.setManager(&sm);
  ssr.setInteractionParameters(uiParams);
  ssr.setSecretStorageType(Sailfish::Secrets::StoreSecretRequest::CollectionSecret);
  ssr.setUserInteractionMode(Sailfish::Secrets::SecretManager::SystemInteraction);
  ssr.setSecret(exampleSecret);
  ssr.startRequest(); // status() will change to Finished when complete
  \endcode
 */

/*!
  \brief Constructs a new StoreSecretRequest object with the given \a parent.
 */
StoreSecretRequest::StoreSecretRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new StoreSecretRequestPrivate)
{
}

/*!
  \brief Destroys the StoreSecretRequest
 */
StoreSecretRequest::~StoreSecretRequest()
{
}

/*!
  \qmlproperty enumeration StoreSecretRequest::secretStorageType
  \brief The type of storage which will apply to the stored secret
  \value CollectionSecret
  \value StandaloneDeviceLockSecret
  \value StandaloneCustomLockSecret
*/

/*!
  \brief Returns the type of storage which will apply to the stored secret

  A secret whose storage type is StoreSecretRequest::CollectionSecret will
  be stored in the collection whose name is specified in the secret's
  identifier's \l{Sailfish::Secrets::Secret::Identifier::collectionName()}
  field.  The collection will have either a custom lock or device lock
  depending on the semantics defined for it when it was created.

  A secret whose storage type is StoreSecretRequest::StandaloneCustomLockSecret
  will be individually encrypted with the custom lock code, and then the
  encrypted version will be stored in a standalone, unencrypted collection.

  A secret whose storage type is StoreSecretRequest::StandaloneDeviceLockSecret
  will be individually encrypted with the device lock code, and then the
  encrypted version will be stored in a standalone, unencrypted collection.
 */
StoreSecretRequest::SecretStorageType StoreSecretRequest::secretStorageType() const
{
    Q_D(const StoreSecretRequest);
    return d->m_secretStorageType;
}

/*!
  \brief Sets the type of storage which will apply to the stored secret to \a type
 */
void StoreSecretRequest::setSecretStorageType(StoreSecretRequest::SecretStorageType type)
{
    Q_D(StoreSecretRequest);
    if (d->m_status != Request::Active && d->m_secretStorageType != type) {
        d->m_secretStorageType = type;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit secretStorageTypeChanged();
    }
}

/*!
  \qmlproperty string StoreSecretRequest::encryptionPluginName
  \brief The name of the encryption plugin which the client wishes to use to encrypt the standalone secret
*/

/*!
  \brief Returns the name of the encryption plugin which the client wishes to use to encrypt the standalone secret
 */
QString StoreSecretRequest::encryptionPluginName() const
{
    Q_D(const StoreSecretRequest);
    return d->m_encryptionPluginName;
}

/*!
  \brief Sets the name of the encryption plugin which the client wishes to use to encrypt the standalone secret to \a pluginName

  Note: this will only apply to secrets whose secretStorageType() is
  StoreSecretRequest::StandaloneCustomLockSecret or
  StoreSecretRequest::StandaloneDeviceLockSecret.
 */
void StoreSecretRequest::setEncryptionPluginName(const QString &pluginName)
{
    Q_D(StoreSecretRequest);
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
  \qmlproperty string StoreSecretRequest::authenticationPluginName
  \brief The name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the secret)
*/

/*!
  \brief Returns the name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the secret)
 */
QString StoreSecretRequest::authenticationPluginName() const
{
    Q_D(const StoreSecretRequest);
    return d->m_authenticationPluginName;
}

/*!
  \brief Sets the name of the authentication plugin which the client wishes to use to authenticate the user (in order to unlock the secret) to \a pluginName

  Note: this will only apply to secrets whose secretStorageType() is StoreSecretRequest::StandaloneCustomLockSecret.
 */
void StoreSecretRequest::setAuthenticationPluginName(const QString &pluginName)
{
    Q_D(StoreSecretRequest);
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
  \qmlproperty Sailfish.Secrets.Secret StoreSecretRequest::secret
  \brief The secret which the client wishes to store securely
*/

/*!
  \brief Returns the secret which the client wishes to store securely
 */
Secret StoreSecretRequest::secret() const
{
    Q_D(const StoreSecretRequest);
    return d->m_secret;
}

/*!
  \brief Sets the secret which the client wishes to store securely to \a secret

  Note: if the secretStorageType() is StoreSecretRequest::CollectionSecret, the
  identifier of the secret must specify a valid collection name.
  Conversely, if the secretStorageType() is either
  StoreSecretRequest::StandaloneCustomLockSecret or
  StoreSecretRequest::StandaloneDeviceLockSecret then the identifier of the
  secret must not contain any collection name.
 */
void StoreSecretRequest::setSecret(const Secret &secret)
{
    Q_D(StoreSecretRequest);
    if (d->m_status != Request::Active && d->m_secret != secret) {
        d->m_secret = secret;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit secretChanged();
    }
}

/*!
  \qmlproperty Sailfish.Secrets.InteractionParameters StoreSecretRequest::interactionParameters
  \brief The user input parameters which should be used when requesting the secret data from the user
*/

/*!
  \brief Returns the user input parameters which should be used when requesting the secret data from the user

  If the user input parameters are not valid, the secret data which is contained
  within the secret() will be stored.  If the user input parameters are valid, then the
  secret data which is contained within the secret() will be overwritten prior to storage
  with the data retrieved from the user.

  Note: specifying user input parameters implies that system-mediated user interaction
  flows are allowed by the calling application.
 */
InteractionParameters StoreSecretRequest::interactionParameters() const
{
    Q_D(const StoreSecretRequest);
    return d->m_interactionParameters;
}

/*!
  \brief Sets the user input parameters which should be used when requesting the secret data from the user to \a params

  If the user input parameters are not valid, the secret data which is contained
  within the secret() will be stored.  If the user input parameters are valid, then the
  secret data which is contained within the secret() will be overwritten prior to storage
  with the data retrieved from the user.

  Note: specifying user input parameters implies that system-mediated user interaction
  flows are allowed by the calling application.
 */
void StoreSecretRequest::setInteractionParameters(const InteractionParameters &params)
{
    Q_D(StoreSecretRequest);
    if (d->m_status != Request::Active && d->m_interactionParameters != params) {
        d->m_interactionParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit interactionParametersChanged();
    }
}

/*!
  \qmlproperty enumeration StoreSecretRequest::DeviceLockUnlockSemantic
  \brief The unlock semantic which will apply to the secret if it is protected by the device lock.
  \value SecretManager.DeviceLockKeepUnlocked unlock after first successful device unlock, stay unlocked.  e.g. background processes.
  \value SecretManager.DeviceLockVerifyLock unlock on device unlock, relock on device lock requiring verify (not passphrase) to unlock on subsequent access.
  \value SecretManager.DeviceLockRelock unlock on device unlock, relock on device lock requiring passphrase to unlock on subsequent access.
*/

/*!
  \brief Returns the unlock semantic which will apply to the secret if it is protected by the device lock.
 */
SecretManager::DeviceLockUnlockSemantic StoreSecretRequest::deviceLockUnlockSemantic() const
{
    Q_D(const StoreSecretRequest);
    return d->m_deviceLockUnlockSemantic;
}

/*!
  \brief Sets the unlock semantic which will apply to the secret if it is protected by the device lock to \a semantic.

  Note: this will only apply to secrets whose secretStorageType() is StoreSecretRequest::StandaloneDeviceLockSecret.
 */
void StoreSecretRequest::setDeviceLockUnlockSemantic(SecretManager::DeviceLockUnlockSemantic semantic)
{
    Q_D(StoreSecretRequest);
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
  \qmlproperty enumeration StoreSecretRequest::customLockUnlockSemantic
  \brief The unlock semantic which will apply to the secret if it is protected by a custom lock.
  \value SecretManager.CustomLockKeepUnlocked unlock after first successful access (with UI flow), stay unlocked.  e.g. background processes.
  \value SecretManager.CustomLockDeviceLockRelock unlock after successful access (with UI flow) after device unlock, relock on device lock.
  \value SecretManager.CustomLockTimoutRelock unlock after successful access (with UI flow) after device unlock, relock after timeout.
  \value SecretManager.CustomLockAccessRelock unlock and relock on every successful access (with UI flow).
*/


/*!
  \brief Returns the unlock semantic which will apply to the secret if it is protected by a custom lock.
 */
SecretManager::CustomLockUnlockSemantic StoreSecretRequest::customLockUnlockSemantic() const
{
    Q_D(const StoreSecretRequest);
    return d->m_customLockUnlockSemantic;
}

/*!
  \brief Sets the unlock semantic which will apply to the secret if it is protected by a custom lock to \a semantic.

  Note: this will only apply to secrets whose secretStorageType() is StoreSecretRequest::StandaloneCustomLockSecret.
 */
void StoreSecretRequest::setCustomLockUnlockSemantic(SecretManager::CustomLockUnlockSemantic semantic)
{
    Q_D(StoreSecretRequest);
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
  \qmlproperty enumeration StoreSecretRequest::accessControlMode
  \brief The access control mode which will be enforced for the secret
  \value SecretManager.OwnerOnlyMode no fine-grained access control necessary, only the creating application can access/write/delete.
  \value SecretManager.SystemAccessControlMode access control via system access control, other applications can access if user gives permission.
  \value SecretManager.NoAccessControlMode other applications can access; use with care (prefer CustomLockAccessRelock)
*/

/*!
  \brief Returns the access control mode which will be enforced for the secret
 */
SecretManager::AccessControlMode StoreSecretRequest::accessControlMode() const
{
    Q_D(const StoreSecretRequest);
    return d->m_accessControlMode;
}

/*!
  \brief Sets the access control mode which will be enforced for the secret to \a mode

  Note: this will only apply to secrets whose secretStorageType() is
  StoreSecretRequest::StandaloneCustomLockSecret or
  StoreSecretRequest::StandaloneDeviceLockSecret.
 */
void StoreSecretRequest::setAccessControlMode(SecretManager::AccessControlMode mode)
{
    Q_D(StoreSecretRequest);
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
  \qmlproperty enumeration StoreSecretRequest::userInteractionMode
  \brief The user interaction mode required when storing the secret (e.g. if a custom lock code must be requested from the user)
  \value SecretManager.PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SecretManager.SystemInteraction  system-mediated user interaction via system UI if required
  \value SecretManager.ApplicationInteraction  in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
*/
/*!
  \brief Returns the user interaction mode required when storing the secret (e.g. if a custom lock code must be requested from the user)
 */
SecretManager::UserInteractionMode StoreSecretRequest::userInteractionMode() const
{
    Q_D(const StoreSecretRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when storing the secret (e.g. if a custom lock code must be requested from the user) to \a mode

  Note: this will only apply to secrets whose secretStorageType() is StoreSecretRequest::StandaloneCustomLockSecret.

  Note: if interactionParameters() are specified, a system-mediated user interaction flow to request
  the secret data will be performed, regardless of the value of the userInteractionMode().
 */
void StoreSecretRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(StoreSecretRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

Request::Status StoreSecretRequest::status() const
{
    Q_D(const StoreSecretRequest);
    return d->m_status;
}

Result StoreSecretRequest::result() const
{
    Q_D(const StoreSecretRequest);
    return d->m_result;
}

SecretManager *StoreSecretRequest::manager() const
{
    Q_D(const StoreSecretRequest);
    return d->m_manager.data();
}

void StoreSecretRequest::setManager(SecretManager *manager)
{
    Q_D(StoreSecretRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void StoreSecretRequest::startRequest()
{
    Q_D(StoreSecretRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result> reply;
        if (d->m_secretStorageType == StoreSecretRequest::CollectionSecret) {
            reply = d->m_manager->d_ptr->setSecret(d->m_secret,
                                                   d->m_interactionParameters,
                                                   d->m_userInteractionMode);
        } else if (d->m_secretStorageType == StoreSecretRequest::StandaloneCustomLockSecret) {
            reply = d->m_manager->d_ptr->setSecret(d->m_secret,
                                                   d->m_encryptionPluginName,
                                                   d->m_authenticationPluginName,
                                                   d->m_interactionParameters,
                                                   d->m_customLockUnlockSemantic,
                                                   d->m_accessControlMode,
                                                   d->m_userInteractionMode);
        } else { // StandaloneDeviceLockSecret
            reply = d->m_manager->d_ptr->setSecret(d->m_secret,
                                                   d->m_encryptionPluginName,
                                                   d->m_interactionParameters,
                                                   d->m_deviceLockUnlockSemantic,
                                                   d->m_accessControlMode,
                                                   d->m_userInteractionMode);
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

void StoreSecretRequest::waitForFinished()
{
    Q_D(StoreSecretRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
