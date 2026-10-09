// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/importkeyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

ImportKeyRequestPrivate::ImportKeyRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype ImportKeyRequest
  \brief Allows a client request that the system crypto service import a key from some data.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::ImportKeyRequest
*/

/*!
  \class ImportKeyRequest
  \brief Allows a client request that the system crypto service import a key from some data.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/importkeyrequest.h

  This key will not be stored securely by the crypto daemon, but instead will
  be returned in its complete form to the caller.
 */

/*!
  \brief Constructs a new ImportKeyRequest object with the given \a parent.
 */
ImportKeyRequest::ImportKeyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new ImportKeyRequestPrivate)
{
}

/*!
  \brief Destroys the ImportKeyRequest
 */
ImportKeyRequest::~ImportKeyRequest()
{
}

/*!
  \qmlproperty string ImportKeyRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the key import operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the key import operation
 */
QString ImportKeyRequest::cryptoPluginName() const
{
    Q_D(const ImportKeyRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the key import operation to \a pluginName
 */
void ImportKeyRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(ImportKeyRequest);
    if (d->m_status != Request::Active && d->m_cryptoPluginName != pluginName) {
        d->m_cryptoPluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit cryptoPluginNameChanged();
    }
}

/*!
  \qmlproperty InteractionParameters ImportKeyRequest::InteractionParameters
  \brief Returns the user input parameters which should be used when requesting the input data from the user
*/

/*!
  \brief Returns the user input parameters which should be used when requesting the input data from the user

  If specified, the user may be prompted to enter a pass phrase needed to decrypt the imported
  key.
 */
Sailfish::Crypto::InteractionParameters
ImportKeyRequest::interactionParameters() const
{
    Q_D(const ImportKeyRequest);
    return d->m_uiParams;
}

/*!
  \brief Sets the user input parameters which should be used when requesting the input data from the user to \a uiParams
 */
void ImportKeyRequest::setInteractionParameters(
        const Sailfish::Crypto::InteractionParameters &uiParams)
{
    Q_D(ImportKeyRequest);
    if (d->m_status != Request::Active && d->m_uiParams != uiParams) {
        d->m_uiParams = uiParams;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit interactionParametersChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer ImportKeyRequest::data
  \brief Returns the data which should be imported as a key.
*/

/*!
  \brief Returns the data which should be imported as a key.
 */
QByteArray ImportKeyRequest::data() const
{
    Q_D(const ImportKeyRequest);
    return d->m_data;
}

/*!
  \brief Sets the \a data which should be imported.
 */
void ImportKeyRequest::setData(const QByteArray &data)
{
    Q_D(ImportKeyRequest);
    if (d->m_status != Request::Active && d->m_data != data) {
        d->m_data = data;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit dataChanged();
    }
}

/*!
  \qmlproperty Key ImportKeyRequest::importedKey
  \brief Returns the imported key
  \note This value is only valid if the status of the request is \c Request.Finished.
*/

/*!
  \brief Returns the imported key

  Note: this value is only valid if the status of the request is Request::Finished.
 */
Key ImportKeyRequest::importedKey() const
{
    Q_D(const ImportKeyRequest);
    return d->m_importedKey;
}

Request::Status ImportKeyRequest::status() const
{
    Q_D(const ImportKeyRequest);
    return d->m_status;
}

Result ImportKeyRequest::result() const
{
    Q_D(const ImportKeyRequest);
    return d->m_result;
}

QVariantMap ImportKeyRequest::customParameters() const
{
    Q_D(const ImportKeyRequest);
    return d->m_customParameters;
}

void ImportKeyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(ImportKeyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *ImportKeyRequest::manager() const
{
    Q_D(const ImportKeyRequest);
    return d->m_manager.data();
}

void ImportKeyRequest::setManager(CryptoManager *manager)
{
    Q_D(ImportKeyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void ImportKeyRequest::startRequest()
{
    Q_D(ImportKeyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Key> reply =
                d->m_manager->d_ptr->importKey(d->m_data,
                                               d->m_uiParams,
                                               d->m_customParameters,
                                               d->m_cryptoPluginName);
        if (reply.isError()) {
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
            d->m_importedKey = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit importedKeyChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, Key> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::CryptoManagerNotInitializedError,
                                         reply.error().message());
                    this->d_ptr->m_importedKey = Key();
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_importedKey = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->importedKeyChanged();
            });
        }
    }
}

void ImportKeyRequest::waitForFinished()
{
    Q_D(ImportKeyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
