// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/storedsecretrequest.h"
#include "Secrets/storedsecretrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

StoredSecretRequestPrivate::StoredSecretRequestPrivate()
    : m_userInteractionMode(SecretManager::PreventInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype StoredSecretRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client request a secret from the system's secure secret storage service
  \inherits Request
*/

/*!
  \class StoredSecretRequest
  \brief Allows a client request a secret from the system's secure secret storage service
  \inmodule SailfishSecrets
  \inheaderfile Secrets/storedsecretrequest.h

  This class allows clients to request the Secrets service to retrieve a secret
  identified by a given identifier().  The identifier() will identify either a
  standalone or collection-stored secret.

  If the application making the request is the creator of the secret, or alternatively
  if the user has granted the application permission to read the specific secret,
  then the Secrets service will instruct the storage plugin to retrieve the secret.

  If the application is not the creator of the secret and the user has not yet
  been asked if the application should have permission to read the secret, then a
  system-mediated access control UI flow may be triggered to obtain the user's
  permission (unless the given \a userInteractionMode is \a PreventInteraction
  in which case the request will fail).

  If the secret uses an encryption key derived from the system device-lock,
  then the value will be able to be retrieved without any other UI flow being required
  if the secret (or the collection in which the secret is stored, if the secret is not a
  standalone secret) is currently unlocked; however, if the secret (or collection) uses
  an encryption key derived from a custom lock, then the custom lock authentication key
  will be obtained from the user via an authentication flow determined by the authentication
  plugin used for that secret (which may support \c ApplicationInteraction if the secret
  is an application-specific secret using an \c ApplicationSpecificAuthentication
  plugin, but otherwise will be a system-mediated UI flow, unless the \a userInteractionMode
  specified is \c PreventInteraction in which case the request will fail).

  If the data contained in the secret is actually a cryptographic key created via the
  \c Sailfish::Crypto library, then only those components of the key which were allowed
  for retrieval via \c Sailfish::Crypto::Key::setComponentConstraints() will be able to be
  retrieved, even if the calling application is the owner of the secret.  For more
  information about that topic, please see the documentation for the
  \c Sailfish::Crypto library.

  An example of retrieving a collection-stored secret follows:

  \code
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::StoredSecretRequest ssr;
  ssr.setManager(&sm);
  ssr.setIdentifier(Sailfish::Secrets::Secret::Identifier("ExampleSecret", "ExampleCollection"));
  ssr.setUserInteractionMode(Sailfish::Secrets::SecretManager::SystemInteraction);
  ssr.startRequest(); // status() will change to Finished when complete
  \endcode
 */

/*!
  \brief Constructs a new StoredSecretRequest object with the given \a parent.
 */
StoredSecretRequest::StoredSecretRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new StoredSecretRequestPrivate)
{
}

/*!
  \brief Destroys the StoredSecretRequest
 */
StoredSecretRequest::~StoredSecretRequest()
{
}

/*!
  \qmlproperty Secret.Identifier StoredSecretRequest::identifier
  \brief The identifier of the secret which the client wishes to retrieve
*/

/*!
  \brief Returns the identifier of the secret which the client wishes to retrieve
 */
Secret::Identifier StoredSecretRequest::identifier() const
{
    Q_D(const StoredSecretRequest);
    return d->m_identifier;
}

/*!
  \brief Sets the identifier of the secret which the client wishes to retrieve to \a ident
 */
void StoredSecretRequest::setIdentifier(const Secret::Identifier &ident)
{
    Q_D(StoredSecretRequest);
    if (d->m_status != Request::Active && d->m_identifier != ident) {
        d->m_identifier = ident;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit identifierChanged();
    }
}

/*!
  \qmlproperty Secret StoredSecretRequest::secret
  \brief The secret which was retrieved for the client
*/

/*!
  \brief Returns the secret which was retrieved for the client
 */
Secret StoredSecretRequest::secret() const
{
    Q_D(const StoredSecretRequest);
    return d->m_secret;
}

/*!
  \qmlproperty enumeration StoredSecretRequest::UserInteractionMode
  \brief The user interaction mode required when retrieving the secret (e.g. if a custom lock code must be requested from the user)
  \value PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SystemInteraction system-mediated user interaction via system UI if required
  \value ApplicationInteraction in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
*/

/*!
  \brief Returns the user interaction mode required when retrieving the secret (e.g. if a custom lock code must be requested from the user)
 */
SecretManager::UserInteractionMode StoredSecretRequest::userInteractionMode() const
{
    Q_D(const StoredSecretRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when retrieving the secret (e.g. if a custom lock code must be requested from the user) to \a mode
 */
void StoredSecretRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(StoredSecretRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

Request::Status StoredSecretRequest::status() const
{
    Q_D(const StoredSecretRequest);
    return d->m_status;
}

Result StoredSecretRequest::result() const
{
    Q_D(const StoredSecretRequest);
    return d->m_result;
}

SecretManager *StoredSecretRequest::manager() const
{
    Q_D(const StoredSecretRequest);
    return d->m_manager.data();
}

void StoredSecretRequest::setManager(SecretManager *manager)
{
    Q_D(StoredSecretRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void StoredSecretRequest::startRequest()
{
    Q_D(StoredSecretRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Secret> reply = d->m_manager->d_ptr->getSecret(
                                                        d->m_identifier,
                                                        d->m_userInteractionMode);
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
            d->m_secret = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit secretChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, Secret> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_secret = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->secretChanged();
            });
        }
    }
}

void StoredSecretRequest::waitForFinished()
{
    Q_D(StoredSecretRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
