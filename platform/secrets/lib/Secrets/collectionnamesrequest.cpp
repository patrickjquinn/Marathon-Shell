// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/collectionnamesrequest.h"
#include "Secrets/collectionnamesrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

CollectionNamesRequestPrivate::CollectionNamesRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype CollectionNamesRequest
  \inqmlmodule Sailfish.Secrets
  \brief Allows a client request the names of collections of secrets from the system secrets service
  \inherits Request
*/

/*!
  \class CollectionNamesRequest
  \brief Allows a client request the names of collections of secrets from the system secrets service
  \inmodule SailfishSecrets
  \inheaderfile Secrets/collectionnamesrequest.h

  This class allows clients to request the Secrets service return the names of
  collections of secrets which are stored in a particular storage plugin.
  Note that the client may not have the ability to read from or write to any
  collection returned from this method, depending on the access controls which
  apply to the collections.

  An example of requesting collection names follows:

  \code
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::CollectionNamesRequest cnr;
  cnr.setManager(&sm);
  cnr.setStoragePluginName(Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName);
  cnr.startRequest();
  // status() will change to Finished when complete
  // collectionNames() will contain the names of the collections
  \endcode
 */

/*!
  \brief Constructs a new CollectionNamesRequest object with the given \a parent.
 */
CollectionNamesRequest::CollectionNamesRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new CollectionNamesRequestPrivate)
{
}

/*!
  \brief Destroys the CollectionNamesRequest
 */
CollectionNamesRequest::~CollectionNamesRequest()
{
}

/*!
  \qmlproperty string CollectionNamesRequest::storagePluginName
  \brief The name of the storage plugin from which the client wishes to retrieve collection names
 */

/*!
  \brief Returns the name of the storage plugin from which the client wishes to retrieve collection names
 */
QString CollectionNamesRequest::storagePluginName() const
{
    Q_D(const CollectionNamesRequest);
    return d->m_storagePluginName;
}

/*!
  \brief Sets the name of the storage plugin from which the client wishes to retrieve collection names to \a pluginName
 */
void CollectionNamesRequest::setStoragePluginName(const QString &pluginName)
{
    Q_D(CollectionNamesRequest);
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
  \qmlproperty array CollectionNamesRequest::collectionNames
  \brief Provides the names of the collections stored by the specified storage plugin
 */

/*!
  \brief Returns the names of the collections stored by the specified storage plugin
 */
QStringList CollectionNamesRequest::collectionNames() const
{
    Q_D(const CollectionNamesRequest);
    return d->m_collectionNames.keys();
}

/*!
  \qmlmethod bool CollectionNamesRequest::isCollectionLocked(string collectionName)
  \brief Returns true if the collection with the specified \a collectionName was locked
         when this request was performed.
 */

/*!
  \brief Returns true if the collection with the specified \a collectionName was locked
         when this request was performed.

  Note that the value reported by this method will not automatically update if a
  collection is subsequently unlocked (e.g. by performing a StoredKeyIdentifiersRequest
  with the collection name set to the given collection); instead, the user must
  start this request again, and then the updated value will be reported appropriately.
 */
bool CollectionNamesRequest::isCollectionLocked(const QString &collectionName) const
{
    Q_D(const CollectionNamesRequest);
    return d->m_collectionNames.value(collectionName);
}

Request::Status CollectionNamesRequest::status() const
{
    Q_D(const CollectionNamesRequest);
    return d->m_status;
}

Result CollectionNamesRequest::result() const
{
    Q_D(const CollectionNamesRequest);
    return d->m_result;
}

SecretManager *CollectionNamesRequest::manager() const
{
    Q_D(const CollectionNamesRequest);
    return d->m_manager.data();
}

void CollectionNamesRequest::setManager(SecretManager *manager)
{
    Q_D(CollectionNamesRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void CollectionNamesRequest::startRequest()
{
    Q_D(CollectionNamesRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QMap<QString, bool> > reply = d->m_manager->d_ptr->collectionNames(
                    d->m_storagePluginName);
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
                QDBusPendingReply<Result, QMap<QString, bool> > reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_collectionNames = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->collectionNamesChanged();
            });
        }
    }
}

void CollectionNamesRequest::waitForFinished()
{
    Q_D(CollectionNamesRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
