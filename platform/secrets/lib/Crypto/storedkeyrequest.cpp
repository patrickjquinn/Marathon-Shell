// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/storedkeyrequest.h"
#include "Crypto/storedkeyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

StoredKeyRequestPrivate::StoredKeyRequestPrivate()
    : m_keyComponents(Key::MetaData | Key::PublicKeyData)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype StoredKeyRequest
  \brief Allows a client request a securely-stored key from the system crypto service.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::StoredKeyRequest
*/

/*!
  \class StoredKeyRequest
  \brief Allows a client request a securely-stored key from the system crypto service.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/storedkeyrequest.h
 */

/*!
  \brief Constructs a new StoredKeyRequest object with the given \a parent.
 */
StoredKeyRequest::StoredKeyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new StoredKeyRequestPrivate)
{
}

/*!
  \brief Destroys the StoredKeyRequest
 */
StoredKeyRequest::~StoredKeyRequest()
{
}

/*!
  \qmlproperty Key.Identifier StoredKeyRequest::identifier
  \brief Returns the identifier of the securely-stored key which the client wishes to retrieve
*/

/*!
  \brief Returns the identifier of the securely-stored key which the client wishes to retrieve
 */
Key::Identifier StoredKeyRequest::identifier() const
{
    Q_D(const StoredKeyRequest);
    return d->m_identifier;
}


/*!
  \brief Sets the identifier of the securely-stored key which the client wishes to retrieve to \a ident
 */
void StoredKeyRequest::setIdentifier(const Key::Identifier &ident)
{
    Q_D(StoredKeyRequest);
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
  \qmlproperty Sailfish::Crypto::Key::Components StoredKeyRequest::keyComponents
  \brief Returns the flags describing which components of the stored key the client wishes to retrieve
  \value NoData
  \value MetaData
  \value PublicKeyData
  \value PrivateKeyData
*/


/*!
  \brief Returns the flags describing which components of the stored key the client wishes to retrieve
 */
Key::Components StoredKeyRequest::keyComponents() const
{
    Q_D(const StoredKeyRequest);
    return d->m_keyComponents;
}

/*!
  \brief Sets the flags describing which components of the stored key the client wishes to retrieve to \a components

  If the \a components includes \c Key::MetaData then information
  about the key (including its origin, algorithm, supported block modes,
  supported encryption and signature paddings, supported digests, operations,
  and filter data) will be retrieved.

  If the \a components includes \c Key::PublicKeyData then
  public key data will be retrieved.

  If the \a components includes \c Key::PrivateKeyData then
  private key data and secret key data will be retrieved.

  Depending on the storage plugin, the custom parameters associated with the
  key may be considered to be either metadata, public key data, or secret
  key data, and will be retrieved or omitted accordingly.
 */
void StoredKeyRequest::setKeyComponents(Key::Components components)
{
    Q_D(StoredKeyRequest);
    if (d->m_status != Request::Active && d->m_keyComponents != components) {
        d->m_keyComponents = components;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyComponentsChanged();
    }
}

/*!
  \qmlproperty Key StoredKeyRequest::storedKey
  \brief Returns the retrieved key
  \note this value is only valid if the status of the request is \c Request.Finished.
*/

/*!
  \brief Returns the retrieved key

  Note: this value is only valid if the status of the request is Request::Finished.
 */
Key StoredKeyRequest::storedKey() const
{
    Q_D(const StoredKeyRequest);
    return d->m_storedKey;
}

Request::Status StoredKeyRequest::status() const
{
    Q_D(const StoredKeyRequest);
    return d->m_status;
}

Result StoredKeyRequest::result() const
{
    Q_D(const StoredKeyRequest);
    return d->m_result;
}

QVariantMap StoredKeyRequest::customParameters() const
{
    Q_D(const StoredKeyRequest);
    return d->m_customParameters;
}

void StoredKeyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(StoredKeyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *StoredKeyRequest::manager() const
{
    Q_D(const StoredKeyRequest);
    return d->m_manager.data();
}

void StoredKeyRequest::setManager(CryptoManager *manager)
{
    Q_D(StoredKeyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void StoredKeyRequest::startRequest()
{
    Q_D(StoredKeyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Key> reply =
                d->m_manager->d_ptr->storedKey(d->m_identifier,
                                               d->m_keyComponents,
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
            d->m_storedKey = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit storedKeyChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, Key> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_storedKey = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->storedKeyChanged();
            });
        }
    }
}

void StoredKeyRequest::waitForFinished()
{
    Q_D(StoredKeyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
