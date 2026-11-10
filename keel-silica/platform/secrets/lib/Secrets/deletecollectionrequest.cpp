// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/deletecollectionrequest.h"
#include "Secrets/deletecollectionrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

DeleteCollectionRequestPrivate::DeleteCollectionRequestPrivate()
    : m_userInteractionMode(SecretManager::PreventInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype DeleteCollectionRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client request that the system secrets service delete a collection from secrets storage
  \inherits Request
*/

/*!
  \class DeleteCollectionRequest
  \brief Allows a client request that the system secrets service delete a collection from secrets storage
  \inmodule SailfishSecrets
  \inheaderfile Secrets/deletecollectionrequest.h

  This class allows clients to request the Secrets service to delete a collection
  with the particular collectionName() from the storage plugin with the specified
  storagePluginName().

  If the calling application is the creator of the collection, or alternatively
  if the user has granted the application permission to delete the collection,
  then the Secrets service will instruct the storage plugin to delete the
  collection and any secrets it contains.

  If the application is not the creator of the collection and the user has not yet
  been asked if the application should have permission to delete the collection,
  a system-mediated access control UI flow may be triggered to obtain the user's
  permission (unless the given \a userInteractionMode is \a PreventInteraction
  in which case the request will fail).

  An example of deleting a collection is as follows:

  \code
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::DeleteCollectionRequest dcr;
  dcr.setManager(&sm);
  dcr.setStoragePluginName(Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName);
  dcr.setCollectionName(QLatin1String("ExampleCollection"));
  dcr.setUserInteractionMode(Sailfish::Secrets::SecretManager::SystemInteraction);
  dcr.startRequest(); // status() will change to Finished when complete
  \endcode
}
\endcode
 */

/*!
  \brief Constructs a new DeleteCollectionRequest object with the given \a parent.
 */
DeleteCollectionRequest::DeleteCollectionRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new DeleteCollectionRequestPrivate)
{
}

/*!
  \brief Destroys the DeleteCollectionRequest
 */
DeleteCollectionRequest::~DeleteCollectionRequest()
{
}

/*!
  \qmlproperty string DeleteCollectionRequest::collectionName
  \brief The name of the collection which the client wishes delete
 */

/*!
  \brief Returns the name of the collection which the client wishes delete
 */
QString DeleteCollectionRequest::collectionName() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_collectionName;
}

/*!
  \brief Sets the name of the collection which the client wishes to delete to \a name
 */
void DeleteCollectionRequest::setCollectionName(const QString &name)
{
    Q_D(DeleteCollectionRequest);
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
  \qmlproperty string DeleteCollectionRequest::storagePluginName
  \brief The name of the storage plugin from which the client wishes to delete the collection
*/

/*!
  \brief Returns the name of the storage plugin from which the client wishes to delete the collection
 */
QString DeleteCollectionRequest::storagePluginName() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_storagePluginName;
}

/*!
  \brief Sets the name of the storage plugin from which the client wishes to delete the collection to \a pluginName
 */
void DeleteCollectionRequest::setStoragePluginName(const QString &pluginName)
{
    Q_D(DeleteCollectionRequest);
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
  \qmlproperty enumeration DeleteCollectionRequest::userInteractionMode
  \brief The user interaction mode required when creating the collection (e.g. if a custom lock code must be requested from the user)
  \value SecretManager.PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SecretManager.SystemInteraction system-mediated user interaction via system UI if required
  \value SecretManager.ApplicationInteraction in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
 */

/*!
  \brief Returns the user interaction mode required when deleting the collection (e.g. if a custom lock code must be requested from the user)
 */
SecretManager::UserInteractionMode DeleteCollectionRequest::userInteractionMode() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when deleting the collection (e.g. if a custom lock code must be requested from the user) to \a mode
 */
void DeleteCollectionRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(DeleteCollectionRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

Request::Status DeleteCollectionRequest::status() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_status;
}

Result DeleteCollectionRequest::result() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_result;
}

SecretManager *DeleteCollectionRequest::manager() const
{
    Q_D(const DeleteCollectionRequest);
    return d->m_manager.data();
}

void DeleteCollectionRequest::setManager(SecretManager *manager)
{
    Q_D(DeleteCollectionRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void DeleteCollectionRequest::startRequest()
{
    Q_D(DeleteCollectionRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result> reply = d->m_manager->d_ptr->deleteCollection(
                                                    d->m_collectionName,
                                                    d->m_storagePluginName,
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

void DeleteCollectionRequest::waitForFinished()
{
    Q_D(DeleteCollectionRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
