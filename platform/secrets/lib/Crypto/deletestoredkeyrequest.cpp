// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/deletestoredkeyrequest.h"
#include "Crypto/deletestoredkeyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

DeleteStoredKeyRequestPrivate::DeleteStoredKeyRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype DeleteStoredKeyRequest
  \brief Allows a client request that the system crypto service delete a stored key
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::DeleteStoredKeyRequest
*/

/*!
  \class DeleteStoredKeyRequest
  \brief Allows a client request that the system crypto service delete a stored key
  \inmodule SailfishCrypto
  \inheaderfile Crypto/deletestoredkeyrequest.h
 */

/*!
  \brief Constructs a new DeleteStoredKeyRequest object with the given \a parent.
 */
DeleteStoredKeyRequest::DeleteStoredKeyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new DeleteStoredKeyRequestPrivate)
{
}

/*!
  \brief Destroys the DeleteStoredKeyRequest
 */
DeleteStoredKeyRequest::~DeleteStoredKeyRequest()
{
}

/*!
  \qmlproperty Key.Identifier DeleteStoredKeyRequest::identifier
  \brief The identifier of the stored key which the client wishes to be deleted
*/

/*!
  \brief Returns the identifier of the stored key which the client wishes to be deleted
 */
Key::Identifier DeleteStoredKeyRequest::identifier() const
{
    Q_D(const DeleteStoredKeyRequest);
    return d->m_identifier;
}

/*!
  \brief Sets the identifier of the stored key which the client wishes to be deleted to \a ident
 */
void DeleteStoredKeyRequest::setIdentifier(const Key::Identifier &ident)
{
    Q_D(DeleteStoredKeyRequest);
    if (d->m_status != Request::Active && d->m_identifier != ident) {
        d->m_identifier = ident;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit identifierChanged();
    }
}

Request::Status DeleteStoredKeyRequest::status() const
{
    Q_D(const DeleteStoredKeyRequest);
    return d->m_status;
}

Result DeleteStoredKeyRequest::result() const
{
    Q_D(const DeleteStoredKeyRequest);
    return d->m_result;
}

QVariantMap DeleteStoredKeyRequest::customParameters() const
{
    Q_D(const DeleteStoredKeyRequest);
    return d->m_customParameters;
}

void DeleteStoredKeyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(DeleteStoredKeyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *DeleteStoredKeyRequest::manager() const
{
    Q_D(const DeleteStoredKeyRequest);
    return d->m_manager.data();
}

void DeleteStoredKeyRequest::setManager(CryptoManager *manager)
{
    Q_D(DeleteStoredKeyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void DeleteStoredKeyRequest::startRequest()
{
    Q_D(DeleteStoredKeyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        // should we pass customParameters in this case, or not?
        // there's no "specific plugin" which is the target of the request..
        QDBusPendingReply<Result> reply =
                d->m_manager->d_ptr->deleteStoredKey(d->m_identifier);
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

void DeleteStoredKeyRequest::waitForFinished()
{
    Q_D(DeleteStoredKeyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
