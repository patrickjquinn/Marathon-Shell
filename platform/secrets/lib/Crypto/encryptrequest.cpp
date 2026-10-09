// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/encryptrequest.h"
#include "Crypto/encryptrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

EncryptRequestPrivate::EncryptRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype EncryptRequest
  \brief Allows a client request that the system crypto service encrypt data with a specific key.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::EncryptRequest
*/

/*!
 * \class EncryptRequest
 * \brief Allows a client request that the system crypto service encrypt data with a specific key.
 * \inmodule SailfishCrypto
 * \inheaderfile Crypto/encryptrequest.h
 */

/*!
 * \brief Constructs a new EncryptRequest object which interfaces to the system
 *        crypto service via the given \a manager, with the given \a parent.
 */
EncryptRequest::EncryptRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new EncryptRequestPrivate)
{
}

/*!
 * \brief Destroys the EncryptRequest
 */
EncryptRequest::~EncryptRequest()
{
}

/*!
  \qmlproperty ArrayBuffer EncryptRequest::data
  \brief The data which the client wishes the system service to encrypt
*/

/*!
 * \brief Returns the data which the client wishes the system service to encrypt
 */
QByteArray EncryptRequest::data() const
{
    Q_D(const EncryptRequest);
    return d->m_data;
}

/*!
 * \brief Sets the data which the client wishes the system service to encrypt to \a data
 */
void EncryptRequest::setData(const QByteArray &data)
{
    Q_D(EncryptRequest);
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
  \qmlproperty ArrayBuffer EncryptRequest::initializationVector
  \brief The initialization vector which the client wishes to use when encrypting the data
*/

/*!
 * \brief Returns the initialization vector which the client wishes to use when encrypting the data
 */
QByteArray EncryptRequest::initializationVector() const
{
    Q_D(const EncryptRequest);
    return d->m_initializationVector;
}

/*!
 * \brief Sets the initialization vector which the client wishes to use when encrypting the data to \a iv
 *
 * Note that this is only applicable for certain key types using certain
 * modes of encryption (e.g. CBC mode with AES symmetric keys).
 *
 * The client must specify the same initialization vector when decrypting
 * the cipher text as they used when encrypting it.  The initialization
 * vector is not secret, and can be stored along with the ciphertext,
 * however it should be generated using a cryptographically secure
 * random number generator (see \l{GenerateRandomDataRequest}) and must
 * be the appropriate size according to the cipher.
 */
void EncryptRequest::setInitializationVector(const QByteArray &iv)
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && d->m_initializationVector != iv) {
        d->m_initializationVector = iv;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit initializationVectorChanged();
    }
}

/*!
  \qmlproperty Key EncryptRequest::key
  \brief The key which the client wishes the system service to use to encrypt the data
*/

/*!
 * \brief Returns the key which the client wishes the system service to use to encrypt the data
 */
Key EncryptRequest::key() const
{
    Q_D(const EncryptRequest);
    return d->m_key;
}

/*!
 * \brief Sets the key which the client wishes the system service to use to encrypt the data to \a key
 */
void EncryptRequest::setKey(const Key &key)
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && d->m_key != key) {
        d->m_key = key;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyChanged();
    }
}

/*!
  \qmlproperty enumeration EncryptRequest::blockMode
  \brief The block mode which should be used when encrypting the data
  \value BlockModeUnknown
  \value BlockModeCustom
  \value BlockModeEcb
  \value BlockModeCbc
  \value BlockModePcbc
  \value BlockModeCfb1
  \value BlockModeCfb8
  \value BlockModeCfb128
  \value BlockModeOfb
  \value BlockModeCtr
  \value BlockModeGcm
  \value BlockModeLrw
  \value BlockModeXex
  \value BlockModeXts
  \value BlockModeCmc
  \value BlockModeEme
  \value BlockModeCcm
*/

/*!
 * \brief Returns the block mode which should be used when encrypting the data
 */
Sailfish::Crypto::CryptoManager::BlockMode EncryptRequest::blockMode() const
{
    Q_D(const EncryptRequest);
    return d->m_blockMode;
}

/*!
 * \brief Sets the block mode which should be used when encrypting the data to \a mode
 */
void EncryptRequest::setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode)
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && d->m_blockMode != mode) {
        d->m_blockMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit blockModeChanged();
    }
}

/*!
  \qmlproperty enumeration EncryptRequest::padding
  \brief The encryption padding mode which should be used when encrypting the data
  \value EncryptionPaddingUnknown
  \value EncryptionPaddingCustom
  \value EncryptionPaddingNone
  \value EncryptionPaddingPkcs7
  \value EncryptionPaddingRsaOaep
  \value EncryptionPaddingRsaOaepMgf1
  \value EncryptionPaddingRsaPkcs1
  \value EncryptionPaddingAnsiX923
*/

/*!
 * \brief Returns the encryption padding mode which should be used when encrypting the data
 */
Sailfish::Crypto::CryptoManager::EncryptionPadding EncryptRequest::padding() const
{
    Q_D(const EncryptRequest);
    return d->m_padding;
}

/*!
 * \brief Sets the encryption padding mode which should be used when encrypting the data to \a padding
 */
void EncryptRequest::setPadding(Sailfish::Crypto::CryptoManager::EncryptionPadding padding)
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && d->m_padding != padding) {
        d->m_padding = padding;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit paddingChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer EncryptRequest::authenticationData
  \brief The authentication data for the encrypt operation
*/

/*!
 * \brief Returns the authentication data for the encrypt operation
 */
QByteArray EncryptRequest::authenticationData() const
{
    Q_D(const EncryptRequest);
    return d->m_authenticationData;
}

/*!
 * \brief Sets the authentication data for the encrypt operation
 *
 * This is only required if performing an authenticated encryption.
 */
void EncryptRequest::setAuthenticationData(const QByteArray &data)
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && d->m_authenticationData != data) {
        d->m_authenticationData = data;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit authenticationDataChanged();
    }
}

/*!
  \qmlproperty string EncryptRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the encryption operation
*/

/*!
 * \brief Returns the name of the crypto plugin which the client wishes to perform the encryption operation
 */
QString EncryptRequest::cryptoPluginName() const
{
    Q_D(const EncryptRequest);
    return d->m_cryptoPluginName;
}

/*!
 * \brief Sets the name of the crypto plugin which the client wishes to perform the encryption operation to \a pluginName
 */
void EncryptRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(EncryptRequest);
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
  \qmlproperty ArrayBuffer EncryptRequest::cipherText
  \brief The ciphertext result of the encryption operation.
  \note this value is only valid if the status of the request is \c Request.Finished.
*/

/*!
 * \brief Returns the ciphertext result of the encryption operation.
 *
 * Note: this value is only valid if the status of the request is Request::Finished.
 */
QByteArray EncryptRequest::ciphertext() const
{
    Q_D(const EncryptRequest);
    return d->m_ciphertext;
}

/*!
  \qmlproperty ArrayBuffer EncryptRequest::authenticationTag
  \brief Returns the authentication tag for the encryption operation
  \note this value is only valid if an authenticated encryption was performed and
  the status of the request is \c Request.Finished
*/

/*!
 * \brief Returns the authentication tag for the encryption operation.
 *
 * Note: this value is only valid if an authenticated encryption was performed and
 * the status of the request is Request::Finished.
 */
QByteArray EncryptRequest::authenticationTag() const
{
    Q_D(const EncryptRequest);
    return d->m_authenticationTag;
}

Request::Status EncryptRequest::status() const
{
    Q_D(const EncryptRequest);
    return d->m_status;
}

Result EncryptRequest::result() const
{
    Q_D(const EncryptRequest);
    return d->m_result;
}

QVariantMap EncryptRequest::customParameters() const
{
    Q_D(const EncryptRequest);
    return d->m_customParameters;
}

void EncryptRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(EncryptRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *EncryptRequest::manager() const
{
    Q_D(const EncryptRequest);
    return d->m_manager.data();
}

void EncryptRequest::setManager(CryptoManager *manager)
{
    Q_D(EncryptRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

/*!
 * \brief Starts an encryption operation.
 *
 * If \l authenticationData has been set, the encryption operation will be
 * authenticated using the \l authenticationData.
 */
void EncryptRequest::startRequest()
{
    Q_D(EncryptRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QByteArray, QByteArray> reply =
                d->m_manager->d_ptr->encrypt(d->m_data,
                                             d->m_initializationVector,
                                             d->m_key,
                                             d->m_blockMode,
                                             d->m_padding,
                                             d->m_authenticationData,
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
            d->m_ciphertext = reply.argumentAt<1>();
            d->m_authenticationTag = reply.argumentAt<2>();
            emit statusChanged();
            emit resultChanged();
            emit ciphertextChanged();
            emit authenticationTagChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QByteArray, QByteArray> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_ciphertext = reply.argumentAt<1>();
                    this->d_ptr->m_authenticationTag = reply.argumentAt<2>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->ciphertextChanged();
                emit this->authenticationTagChanged();
            });
        }
    }
}

void EncryptRequest::waitForFinished()
{
    Q_D(EncryptRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
