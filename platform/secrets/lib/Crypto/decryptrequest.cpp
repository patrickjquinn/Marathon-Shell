// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/decryptrequest.h"
#include "Crypto/decryptrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

DecryptRequestPrivate::DecryptRequestPrivate()
    : m_verificationStatus(Sailfish::Crypto::CryptoManager::VerificationStatusUnknown),
      m_status(Request::Inactive)
{
}

/*!
  \qmltype DecryptRequest
  \brief Allows a client request that the system crypto service decrypt data with a specific key.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::DecryptRequest
*/

/*!
  \class DecryptRequest
  \brief Allows a client request that the system crypto service decrypt data with a specific key.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/decryptrequest.h
 */

/*!
  \brief Constructs a new DecryptRequest object with the given \a parent.
 */
DecryptRequest::DecryptRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new DecryptRequestPrivate)
{
}

/*!
  \brief Destroys the DecryptRequest
 */
DecryptRequest::~DecryptRequest()
{
}

/*!
  \qmlproperty ArrayBuffer DecryptRequest::data
  \brief The data which the client wishes to decrypt
*/

/*!
  \brief Returns the data which the client wishes to decrypt
 */
QByteArray DecryptRequest::data() const
{
    Q_D(const DecryptRequest);
    return d->m_data;
}

/*!
  \brief Sets the data which the client wishes to decrypt to \a data
 */
void DecryptRequest::setData(const QByteArray &data)
{
    Q_D(DecryptRequest);
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
  \qmlproperty ArrayBuffer DecryptRequest::initializationVector
  \brief The initialization vector which the client wishes to use when decrypting the data
*/

/*!
  \brief Returns the initialization vector which the client wishes to use when decrypting the data
 */
QByteArray DecryptRequest::initializationVector() const
{
    Q_D(const DecryptRequest);
    return d->m_initializationVector;
}

/*!
  \brief Sets the initialization vector which the client wishes to use when decrypting the data to \a iv

  Note that this is only applicable for certain key types using certain
  modes of encryption (e.g. CBC mode with AES symmetric keys).

  The client must specify the same initialization vector when decrypting
  the cipher text as they used when encrypting it.  The initialization
  vector is not secret, and can be stored along with the ciphertext,
  however it should be generated using a cryptographically secure
  random number generator (see \l{GenerateRandomDataRequest}) and must
  be the appropriate size according to the cipher.
 */
void DecryptRequest::setInitializationVector(const QByteArray &iv)
{
    Q_D(DecryptRequest);
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
  \qmlproperty Key DecryptRequest::key
  \brief The key the client wishes to be used to decrypt data
*/

/*!
  \brief Returns the key the client wishes to be used to decrypt data
 */
Key DecryptRequest::key() const
{
    Q_D(const DecryptRequest);
    return d->m_key;
}

/*!
  \brief Sets the key the client wishes to be used to decrypt data to \a key
 */
void DecryptRequest::setKey(const Key &key)
{
    Q_D(DecryptRequest);
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
  \qmlproperty enumeration DecryptRequest::blockMode
  \brief The block mode which should be used when decrypting the data
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
  \brief Returns the block mode to be used when decrypting the data
 */
Sailfish::Crypto::CryptoManager::BlockMode DecryptRequest::blockMode() const
{
    Q_D(const DecryptRequest);
    return d->m_blockMode;
}

/*!
  \brief Sets the block mode to be used when decrypting the data to the given \a mode
 */
void DecryptRequest::setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode)
{
    Q_D(DecryptRequest);
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
  \qmlproperty enumeration DecryptRequest::padding
  \brief The encryption padding mode which should be used when decrypting the data
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
  \brief Returns the encryption padding mode to be used when decrypting the data
 */
Sailfish::Crypto::CryptoManager::EncryptionPadding DecryptRequest::padding() const
{
    Q_D(const DecryptRequest);
    return d->m_padding;
}

/*!
  \brief Sets the encryption padding mode to be used when decrypting the data to the given \a padding
 */
void DecryptRequest::setPadding(Sailfish::Crypto::CryptoManager::EncryptionPadding padding)
{
    Q_D(DecryptRequest);
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
  \qmlproperty ArrayBuffer DecryptRequest::authenticationData
  \brief The authentication data for the decrypt operation
*/

/*!
  \brief Returns the authentication data for the decrypt operation
 */
QByteArray DecryptRequest::authenticationData() const
{
    Q_D(const DecryptRequest);
    return d->m_authenticationData;
}

/*!
  \brief Sets the authentication data for the decrypt operation

  This is only required if performing an authenticated decryption.
 */
void DecryptRequest::setAuthenticationData(const QByteArray &data)
{
    Q_D(DecryptRequest);
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
  \qmlproperty ArrayBuffer DecryptRequest::authenticationTag
  \brief The authentication tag for the decrypt operation
*/

/*!
  \brief Returns the authentication tag for the decrypt operation
 */
QByteArray DecryptRequest::authenticationTag() const
{
    Q_D(const DecryptRequest);
    return d->m_authenticationTag;
}

/*!
  \brief Sets the authentication tag for the decrypt operation

  This is only required if performing an authenticated decryption.
 */
void DecryptRequest::setAuthenticationTag(const QByteArray &authenticationTag)
{
    Q_D(DecryptRequest);
    if (d->m_status != Request::Active && d->m_authenticationTag != authenticationTag) {
        d->m_authenticationTag = authenticationTag;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit authenticationTagChanged();
    }
}

/*!
  \qmlproperty string DecryptRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the decryption operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the decryption operation
 */
QString DecryptRequest::cryptoPluginName() const
{
    Q_D(const DecryptRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the decryption operation to \a pluginName
 */
void DecryptRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(DecryptRequest);
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
  \qmlproperty ArrayBuffer DecryptRequest::plaintext
  \brief Returns the plaintext result of the decryption operation.
  \note this value is only valid if the status of the request is \c Request.Finished
*/

/*!
  \brief Returns the plaintext result of the decryption operation.

  Note: this value is only valid if the status of the request is Request::Finished.
 */
QByteArray DecryptRequest::plaintext() const
{
    Q_D(const DecryptRequest);
    return d->m_plaintext;
}

/*!
  \qmlproperty Sailfish::Crypto::CryptoManager::VerificationStatus DecryptRequest::verificationStatus
  \brief Returns the verification result of the decryption operation.
  \note this value is only valid if the status of the request is \c Request.Finished
  \value VerificationStatusUnknown
  \value VerificationSucceeded
  \value VerificationFailed
  \value VerificationSignatureInvalid
  \value VerificationSignatureExpired
  \value VerificationKeyExpired
  \value VerificationKeyRevoked
  \value VerificationKeyInvalid
*/

  
/*!
  \brief Returns the verification result of the decryption operation.

  Note: this value is only valid if the status of the request is Request::Finished.
 */
Sailfish::Crypto::CryptoManager::VerificationStatus DecryptRequest::verificationStatus() const
{
    Q_D(const DecryptRequest);
    return d->m_verificationStatus;
}

Request::Status DecryptRequest::status() const
{
    Q_D(const DecryptRequest);
    return d->m_status;
}

Result DecryptRequest::result() const
{
    Q_D(const DecryptRequest);
    return d->m_result;
}

QVariantMap DecryptRequest::customParameters() const
{
    Q_D(const DecryptRequest);
    return d->m_customParameters;
}

void DecryptRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(DecryptRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *DecryptRequest::manager() const
{
    Q_D(const DecryptRequest);
    return d->m_manager.data();
}

void DecryptRequest::setManager(CryptoManager *manager)
{
    Q_D(DecryptRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

/*!
  \brief Starts a decryption operation.

  If \l authenticationData has been set, the decryption operation will be
  authenticated using the \l authenticationData and \l authenticationTag values.
 */
void DecryptRequest::startRequest()
{
    Q_D(DecryptRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QByteArray, CryptoManager::VerificationStatus> reply = d->m_manager->d_ptr->decrypt(
                    d->m_data,
                    d->m_initializationVector,
                    d->m_key,
                    d->m_blockMode,
                    d->m_padding,
                    d->m_authenticationData,
                    d->m_authenticationTag,
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
            d->m_plaintext = reply.argumentAt<1>();
            d->m_verificationStatus = reply.argumentAt<2>();
            emit statusChanged();
            emit resultChanged();
            emit plaintextChanged();
            emit verificationStatusChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QByteArray, CryptoManager::VerificationStatus> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_plaintext = reply.argumentAt<1>();
                    this->d_ptr->m_verificationStatus = reply.argumentAt<2>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->plaintextChanged();
                emit this->verificationStatusChanged();
            });
        }
    }
}

void DecryptRequest::waitForFinished()
{
    Q_D(DecryptRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
