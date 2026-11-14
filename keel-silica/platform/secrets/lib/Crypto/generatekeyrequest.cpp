// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/generatekeyrequest.h"
#include "Crypto/generatekeyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

GenerateKeyRequestPrivate::GenerateKeyRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype GenerateKeyRequest
  \brief Allows a client request that the system crypto service generate a key based on a template.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::GenerateKeyRequest
*/

/*!
  \class GenerateKeyRequest
  \brief Allows a client request that the system crypto service generate a key based on a template.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/generatekeyrequest.h

  This key will not be stored securely by the crypto daemon, but instead will
  be returned in its complete form to the caller.
 */

/*!
  \brief Constructs a new GenerateKeyRequest object with the given \a parent.
 */
GenerateKeyRequest::GenerateKeyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new GenerateKeyRequestPrivate)
{
}

/*!
  \brief Destroys the GenerateKeyRequest
 */
GenerateKeyRequest::~GenerateKeyRequest()
{
}

/*!
  \qmlproperty string GenerateKeyRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the key generation operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the key generation operation
 */
QString GenerateKeyRequest::cryptoPluginName() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the key generation operation to \a pluginName
 */
void GenerateKeyRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(GenerateKeyRequest);
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
  \qmlproperty KeyDerivationParameters GenerateKeyRequest::keyDerivationParameters
  \brief The symmetric key derivation parameters which should be used to generate the secret key data
*/

/*!
  \brief Returns the symmetric key derivation parameters which should be used to generate the secret key data

  These parameters are only meaningful if the template key
  algorithm is a symmetric cipher algorithm.
 */
KeyDerivationParameters
GenerateKeyRequest::keyDerivationParameters() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_skdfParams;
}

/*!
  \brief Sets the symmetric key derivation parameters which should be used to generate the secret key data to \a params
 */
void GenerateKeyRequest::setKeyDerivationParameters(
        const KeyDerivationParameters &params)
{
    Q_D(GenerateKeyRequest);
    if (d->m_status != Request::Active && d->m_skdfParams != params) {
        d->m_skdfParams = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyDerivationParametersChanged();
    }
}

/*!
  \qmlproperty KeyPairGenerationParameters GenerateKeyRequest::keyPairGenerationParameters
  \brief The asymmetric key pair generation parameters which
         should be used to generate the public and private key data
*/

/*!
  \brief Returns the asymmetric key pair generation parameters which
         should be used to generate the public and private key data

  These parameters are only meaningful if the template key
  algorithm is an asymmetric cipher algorithm.
 */
KeyPairGenerationParameters
GenerateKeyRequest::keyPairGenerationParameters() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_kpgParams;
}

/*!
  \brief Sets the asymmetric key pair generation parameters which
         should be used to generate the public and private key data to \a params
 */
void GenerateKeyRequest::setKeyPairGenerationParameters(
        const KeyPairGenerationParameters &params)
{
    Q_D(GenerateKeyRequest);
    if (d->m_status != Request::Active && d->m_kpgParams != params) {
        d->m_kpgParams = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyPairGenerationParametersChanged();
    }
}

/*!
  \qmlproperty Key GenerateKeyRequest::keyTemplate
  \brief The key which should be used as a template when generating the full key
*/

/*!
  \brief Returns the key which should be used as a template when generating the full key
 */
Key GenerateKeyRequest::keyTemplate() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_keyTemplate;
}

/*!
  \brief Sets the key which should be used as a template when generating the full key to \a key
 */
void GenerateKeyRequest::setKeyTemplate(const Key &key)
{
    Q_D(GenerateKeyRequest);
    if (d->m_status != Request::Active && d->m_keyTemplate != key) {
        d->m_keyTemplate = key;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyTemplateChanged();
    }
}

/*!
  \qmlproperty Key GenerateKeyRequest::generatedKey
  \brief Returns the generated key
  \note this value is only valid if the status of the request is \c Request.Finished.
*/

/*!
  \brief Returns the generated key

  Note: this value is only valid if the status of the request is Request::Finished.
 */
Key GenerateKeyRequest::generatedKey() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_generatedKey;
}

Request::Status GenerateKeyRequest::status() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_status;
}

Result GenerateKeyRequest::result() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_result;
}

QVariantMap GenerateKeyRequest::customParameters() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_customParameters;
}

void GenerateKeyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(GenerateKeyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *GenerateKeyRequest::manager() const
{
    Q_D(const GenerateKeyRequest);
    return d->m_manager.data();
}

void GenerateKeyRequest::setManager(CryptoManager *manager)
{
    Q_D(GenerateKeyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void GenerateKeyRequest::startRequest()
{
    Q_D(GenerateKeyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Key> reply =
                d->m_manager->d_ptr->generateKey(d->m_keyTemplate,
                                                 d->m_kpgParams,
                                                 d->m_skdfParams,
                                                 d->m_customParameters,
                                                 d->m_cryptoPluginName);
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
            d->m_generatedKey = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit generatedKeyChanged();
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
                    this->d_ptr->m_generatedKey = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->generatedKeyChanged();
            });
        }
    }
}

void GenerateKeyRequest::waitForFinished()
{
    Q_D(GenerateKeyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
