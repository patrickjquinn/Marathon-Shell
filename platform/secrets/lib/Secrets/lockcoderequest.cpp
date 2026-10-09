// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/lockcoderequest.h"
#include "Secrets/lockcoderequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

LockCodeRequestPrivate::LockCodeRequestPrivate()
    : m_lockStatus(LockCodeRequest::Unknown)
    , m_lockCodeRequestType(LockCodeRequest::ModifyLockCode)
    , m_lockCodeTargetType(LockCodeRequest::MetadataDatabase)
    , m_userInteractionMode(SecretManager::SystemInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype LockCodeRequest
  \brief Allows a client to request that the system service either
         unlock, lock, or modify the lock code associated with the
         device, an extension plugin, a standalone secret or a
         collection.
  \inqmlmodule Sailfish.Secrets
  \inherits Request
*/

/*!
  \class LockCodeRequest
  \brief Allows a client to request that the system service either
         unlock, lock, or modify the lock code associated with the
         device, an extension plugin, a standalone secret or a
         collection.
  \inmodule SailfishSecrets
  \inheaderfile Secrets/lockcoderequest.h

  \b{Note: most clients will never need to use this class, as the
  other request types automatically trigger locking and relocking
  flows as required.}

  The operation will be applied to the secrets bookkeeping database
  of the device, an extension plugin, a custom-locked collection or
  a standalone secret specified by the \l{lockCodeTargetType()} and
  \l{lockCodeTarget()} parameters.  This operation is only valid for
  custom-locked collections or secrets when performed by a non-privileged
  application.

  If the \l{lockCodeRequestType()} specified is \l{ModifyLockCode}
  then the user will be prompted (via a system-mediated user interaction
  flow) for the current lock code, and if that matches the existing
  lock code, they will then be prompted for the new lock code.  The
  datum will then be re-encrypted with a key derived from the new lock code.

  If the \l{lockCodeRequestType()} specified is \l{QueryLockStatus}
  then the service will return whether the specified target plugin
  or metadata database is locked and requires a lock code to be entered.

  If the \l{lockCodeRequestType()} specified is \l{ProvideLockCode}
  then the user will be prompted (via a system-mediated user interaction
  flow) for the current lock code, which will be used to unlock the datum.

  If the \l{lockCodeRequestType()} specified is \l{ForgetLockCode}
  then if the datum is currently unlocked, the user will be prompted (via a
  system-mediated user interaction flow) for the current lock code, and if
  it matches the actual lock code, the datum will be locked.

  An example of modifying the lock code used for a custom-locked collection
  follows:

  \code
  // Require an alpha-numeric lock code to be provided
  Sailfish::Secrets::InteractionParameters uiParams;
  uiParams.setInputType(Sailfish::Secrets::InteractionParameters::AlphaNumericInput);
  uiParams.setEchoMode(Sailfish::Secrets::InteractionParameters::PasswordEcho);

  // Request that the collection be re-keyed.
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::LockCodeRequest lcr;
  lcr.setManager(&sm);
  lcr.setLockCodeRequestType(Sailfish::Secrets::LockCodeRequest::ModifyLockCode);
  lcr.setLockCodeTargetType(Sailfish::Secrets::LockCodeRequest::ExtensionPlugin);
  lcr.setLockCodeTarget(QLatin1String("Some custom-locked collection"));
  lcr.setInteractionParameters(uiParams);
  lcr.startRequest(); // status() will change to Finished when complete
  \endcode
 */

/*!
  \brief Constructs a new LockCodeRequest object with the given \a parent.
 */
LockCodeRequest::LockCodeRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new LockCodeRequestPrivate)
{
}

/*!
  \brief Destroys the LockCodeRequest
 */
LockCodeRequest::~LockCodeRequest()
{
}

/*!
  \qmlproperty enumeration lockCodeRequestType
  \brief The type of lock code operation being requested
  \value QueryLockStatus
  \value ModifyLockCode
  \value ProvideLockCode
  \valie ForgetLockCode
*/

/*!
  \brief Returns the type of lock code operation being requested
 */
LockCodeRequest::LockCodeRequestType LockCodeRequest::lockCodeRequestType() const
{
    Q_D(const LockCodeRequest);
    return d->m_lockCodeRequestType;
}

/*!
  \brief Sets the type of lock code operation being requested to \a type
 */
void LockCodeRequest::setLockCodeRequestType(LockCodeRequest::LockCodeRequestType type)
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && d->m_lockCodeRequestType != type) {
        d->m_lockCodeRequestType = type;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        if (d->m_lockStatus != LockCodeRequest::Unknown) {
            d->m_lockStatus = LockCodeRequest::Unknown;
            emit lockStatusChanged();
        }
        emit lockCodeRequestTypeChanged();
    }
}

/*!
  \qmlproperty enumeration LockCodeRequest::lockCodeTargetType
  \brief The type of the target of the lock code operation
  \value MetadataDatabase
  \value ExtensionPlugin
*/

/*!
  \brief Returns the type of the target of the lock code operation
 */
LockCodeRequest::LockCodeTargetType LockCodeRequest::lockCodeTargetType() const
{
    Q_D(const LockCodeRequest);
    return d->m_lockCodeTargetType;
}

/*!
  \brief Sets the type of the target of the lock code operation to \a type

  Only privileged applications (usually, the system settings application)
  can perform lock code operations on the bookkeeping database.

  Only the owner of a collection or standalone-secret can perform lock code
  operations on that collection or secret.

  Some plugins must be unlocked prior to use, and such plugins should
  document their semantics for their intended clients.
 */
void LockCodeRequest::setLockCodeTargetType(LockCodeRequest::LockCodeTargetType type)
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && d->m_lockCodeTargetType != type) {
        d->m_lockCodeTargetType = type;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit lockCodeTargetTypeChanged();
    }
}

/*!
  \qmlproperty enumeration LockCodeRequest::userInteractionMode
  \brief The user interaction mode required when retrieving lock codes from the user
  \value PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SystemInteraction system-mediated user interaction via system UI if required
  \value ApplicationInteraction in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
*/

/*!
  \brief Returns the user interaction mode required when retrieving lock codes from the user
 */
SecretManager::UserInteractionMode LockCodeRequest::userInteractionMode() const
{
    Q_D(const LockCodeRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when retrieving lock codes from the user to \a mode

  This should only (and must be) be set to
  \l{SecretManager::ApplicationInteraction} if the collection or standalone
  secret is owned by the caller application and its original user interaction
  mode was already set to \c{ApplicationInteraction}, otherwise an error will
  be returned.

  Note that if \l{interactionParameters()} are provided then the \a mode
  will be ignored, which may result in an error being returned to the client
  (that is, if the collection or standalone secret is owned by the caller
  application and its original user interaction mode was set to
  \c{ApplicationInteraction}).
 */
void LockCodeRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

/*!
  \qmlproperty InteractionParameters LockCodeRequest::interactionParameters
  \brief The user input parameters which should be used when requesting the secret data from the user
*/

/*!
  \brief Returns the user input parameters which should be used when requesting the secret data from the user
 */
InteractionParameters LockCodeRequest::interactionParameters() const
{
    Q_D(const LockCodeRequest);
    return d->m_interactionParameters;
}

/*!
  \brief Sets the user input parameters which should be used when requesting the lock code from the user to \a params

  Note: specifying user input parameters implies that system-mediated user interaction
  flows are allowed by the calling application, and are required by the collection
  or standalone secret for which the lock code is being requested.
 */
void LockCodeRequest::setInteractionParameters(const InteractionParameters &params)
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && d->m_interactionParameters != params) {
        d->m_interactionParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit interactionParametersChanged();
    }
}

// TODO: in the future support oldLockCodeInteractionParameters also?
// e.g. to allow changing the type of lock code (from PIN to ALPHANUM, etc)?

/*!
  \qmlproperty string LockCodeRequest::lockCodeTarget
  \brief The name of the target to which the lock code operation should be applied
*/

/*!
  \brief Returns the name of the target to which the lock code operation should be applied
 */
QString LockCodeRequest::lockCodeTarget() const
{
    Q_D(const LockCodeRequest);
    return d->m_lockCodeTarget;
}

/*!
  \brief Sets the name of the target to which the lock code operation should be applied to \a name

  The \a name may identify either a custom-locked collection,
  a custom-locked standalone secret, an extension plugin or
  the bookkeeping database, depending on the value of the
  \l{lockCodeTargetType()}.
 */
void LockCodeRequest::setLockCodeTarget(const QString &targetName)
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && d->m_lockCodeTarget != targetName) {
        d->m_lockCodeTarget = targetName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit lockCodeTargetChanged();
    }
}

/*!
  \qmlproperty enumeration LockCodeRequest::lockStatus
  \brief The current lock status of the target plugin or metadata database
  \value Unknown 
  \value Unsupported
  \value Unlocked
  \value Locked
*/

/*!
  \brief Returns the current lock status of the target plugin or metadata database

  The value will only be valid if the request's operation is \c{QueryLockStatus}.
  Per-plugin lock status information is also reported from PluginInfoRequest.
 */
LockCodeRequest::LockStatus LockCodeRequest::lockStatus() const
{
    Q_D(const LockCodeRequest);
    return d->m_lockStatus;
}

Request::Status LockCodeRequest::status() const
{
    Q_D(const LockCodeRequest);
    return d->m_status;
}

Result LockCodeRequest::result() const
{
    Q_D(const LockCodeRequest);
    return d->m_result;
}

SecretManager *LockCodeRequest::manager() const
{
    Q_D(const LockCodeRequest);
    return d->m_manager.data();
}

void LockCodeRequest::setManager(SecretManager *manager)
{
    Q_D(LockCodeRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void LockCodeRequest::startRequest()
{
    Q_D(LockCodeRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        if (d->m_lockCodeRequestType == LockCodeRequest::QueryLockStatus) {
            QDBusPendingReply<Result, LockCodeRequest::LockStatus> reply;
            reply = d->m_manager->d_ptr->queryLockStatus(d->m_lockCodeTargetType,
                                                         d->m_lockCodeTarget);
            if (!reply.isValid() && !reply.error().message().isEmpty()) {
                d->m_status = Request::Finished;
                d->m_result = Result(Result::SecretManagerNotInitializedError,
                                     reply.error().message());
                d->m_lockStatus = LockCodeRequest::Unknown;
                emit lockStatusChanged();
                emit statusChanged();
                emit resultChanged();
            } else if (reply.isFinished()
                    // work around a bug in QDBusAbstractInterface / QDBusConnection...
                    && reply.argumentAt<0>().code() != Sailfish::Secrets::Result::Succeeded) {
                d->m_status = Request::Finished;
                d->m_result = reply.argumentAt<0>();
                d->m_lockStatus = LockCodeRequest::Unknown;
                emit lockStatusChanged();
                emit statusChanged();
                emit resultChanged();
            } else {
                d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
                connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                        [this] {
                    QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                    QDBusPendingReply<Result, LockCodeRequest::LockStatus> reply = *watcher;
                    this->d_ptr->m_status = Request::Finished;
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_lockStatus = reply.argumentAt<1>();
                    watcher->deleteLater();
                    emit this->lockStatusChanged();
                    emit this->statusChanged();
                    emit this->resultChanged();
                });
            }
        } else {
            QDBusPendingReply<Result> reply;
            if (d->m_lockCodeRequestType == LockCodeRequest::ModifyLockCode) {
                reply = d->m_manager->d_ptr->modifyLockCode(d->m_lockCodeTargetType,
                                                            d->m_lockCodeTarget,
                                                            d->m_interactionParameters,
                                                            d->m_userInteractionMode);
            } else if (d->m_lockCodeRequestType == LockCodeRequest::ProvideLockCode) {
                reply = d->m_manager->d_ptr->provideLockCode(d->m_lockCodeTargetType,
                                                             d->m_lockCodeTarget,
                                                             d->m_interactionParameters,
                                                             d->m_userInteractionMode);
            } else { // ForgetLockCode
                reply = d->m_manager->d_ptr->forgetLockCode(d->m_lockCodeTargetType,
                                                            d->m_lockCodeTarget,
                                                            d->m_interactionParameters,
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
}

void LockCodeRequest::waitForFinished()
{
    Q_D(LockCodeRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
