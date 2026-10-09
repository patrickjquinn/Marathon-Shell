// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/storedkeyidentifiersrequest.h"
#include "Crypto/storedkeyidentifiersrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

StoredKeyIdentifiersRequestPrivate::StoredKeyIdentifiersRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \class StoredKeyIdentifiersRequest
  \brief Allows a client request the identifiers of securely-stored keys from the system crypto service
  \inmodule SailfishCrypto
  \inheaderfile Crypto/storedkeyidentifiersrequest.h
 */

/*!
  \brief Constructs a new StoredKeyIdentifiersRequest object with the given \a parent.
 */
StoredKeyIdentifiersRequest::StoredKeyIdentifiersRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new StoredKeyIdentifiersRequestPrivate)
{
}

/*!
  \brief Destroys the StoredKeyIdentifiersRequest
 */
StoredKeyIdentifiersRequest::~StoredKeyIdentifiersRequest()
{
}

/*!
  \qmlproperty string StoredKeyIdentifiersRequest::storagePluginName
  \brief The name of the storage plugin from which the client wishes to retrieve key identifiers
*/

/*!
  \brief Returns the name of the storage plugin from which the client wishes to retrieve key identifiers
 */
QString StoredKeyIdentifiersRequest::storagePluginName() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_storagePluginName;
}

/*!
  \brief Sets the name of the storage plugin from which the client wishes to retrieve key identifiers to \a pluginName
 */
void StoredKeyIdentifiersRequest::setStoragePluginName(const QString &pluginName)
{
    Q_D(StoredKeyIdentifiersRequest);
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
  \qmlproperty string StoredKeyIdentifiersRequest::collectionName
  \brief The name of the collection from which the client wishes to retrieve key identifiers
*/

/*!
  \brief Returns the name of the collection from which the client wishes to retrieve key identifiers
 */
QString StoredKeyIdentifiersRequest::collectionName() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_collectionName;
}

/*!
  \brief Sets the name of the collection from which the client wishes to retrieve key identifiers to \a name

  If the collection \a name is empty, this signifies that the client wishes
  to retrieve the identifiers of keys stored in any collection.  Note that
  in this case, if some collection stored by the plugin is locked, the
  client may not be returned any identifiers of keys stored within that
  collection, and no unlocking flow will be started for such locked
  collections.

  If the collection \name is non-empty, this signifies that the client
  wishes to retrieve the identifiers of keys stored only in that collection.
  If the collection is locked, an unlock flow will be started (prompting
  the user for the passphrase to unlock that collection).
 */
void StoredKeyIdentifiersRequest::setCollectionName(const QString &name)
{
    Q_D(StoredKeyIdentifiersRequest);
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
  \brief Returns the identifiers of securely-stored keys

  Note: this value is only valid if the status of the request is Request::Finished.
 */
QVector<Key::Identifier> StoredKeyIdentifiersRequest::identifiers() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_identifiers;
}

Request::Status StoredKeyIdentifiersRequest::status() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_status;
}

Result StoredKeyIdentifiersRequest::result() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_result;
}

QVariantMap StoredKeyIdentifiersRequest::customParameters() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_customParameters;
}

void StoredKeyIdentifiersRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(StoredKeyIdentifiersRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *StoredKeyIdentifiersRequest::manager() const
{
    Q_D(const StoredKeyIdentifiersRequest);
    return d->m_manager.data();
}

void StoredKeyIdentifiersRequest::setManager(CryptoManager *manager)
{
    Q_D(StoredKeyIdentifiersRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void StoredKeyIdentifiersRequest::startRequest()
{
    Q_D(StoredKeyIdentifiersRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QVector<Key::Identifier> > reply =
                d->m_manager->d_ptr->storedKeyIdentifiers(d->m_storagePluginName,
                                                          d->m_collectionName,
                                                          d->m_customParameters);
        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::CryptoManagerNotInitializedError,
                                 reply.error().message());
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Crypto::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            d->m_identifiers = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit identifiersChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QVector<Key::Identifier> > reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_identifiers = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->identifiersChanged();
            });
        }
    }
}

void StoredKeyIdentifiersRequest::waitForFinished()
{
    Q_D(StoredKeyIdentifiersRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
