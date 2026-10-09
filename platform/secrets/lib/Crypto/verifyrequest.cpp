// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/verifyrequest.h"
#include "Crypto/verifyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

VerifyRequestPrivate::VerifyRequestPrivate()
    : m_padding(CryptoManager::SignaturePaddingUnknown)
    , m_digestFunction(CryptoManager::DigestUnknown)
    , m_verificationStatus(Sailfish::Crypto::CryptoManager::VerificationStatusUnknown)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype VerifyRequest
  \brief Allows a client request the system crypto service to verify that data was signed with a specific key
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::VerifyRequest
*/

/*!
  \class VerifyRequest
  \brief Allows a client request the system crypto service to verify that data was signed with a specific key
  \inmodule SailfishCrypto
  \inheaderfile Crypto/verifyrequest.h
 */

/*!
  \brief Constructs a new VerifyRequest object with the given \a parent
 */
VerifyRequest::VerifyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new VerifyRequestPrivate)
{
}

/*!
  \brief Destroys the VerifyRequest
 */
VerifyRequest::~VerifyRequest()
{
}

/*!
  \qmlproperty ArrayBuffer VerifyRequest::signature
  \brief The signature which the client wishes the system service to verify
*/

/*!
  \brief Returns the signature which the client wishes the system service to verify
 */
QByteArray VerifyRequest::signature() const
{
    Q_D(const VerifyRequest);
    return d->m_signature;
}

/*!
  \brief Sets the signature which the client wishes the system service to verify to \a sig
 */
void VerifyRequest::setSignature(const QByteArray &sig)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_signature != sig) {
        d->m_signature = sig;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit signatureChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer VerifyRequest::data
  \brief The data which was signed by the remote party
*/

/*!
  \brief Returns the data which was signed by the remote party
 */
QByteArray VerifyRequest::data() const
{
    Q_D(const VerifyRequest);
    return d->m_data;
}

/*!
  \brief Sets the data which was signed by the remote party to \a data
 */
void VerifyRequest::setData(const QByteArray &data)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_data != data) {
        d->m_data = data;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit dataChanged();
    }
}

/*!
  \qmlproperty Key VerifyRequest::key
  \brief The key which the client wishes the system service to use to verify the data
*/

/*!
  \brief Returns the key which the client wishes the system service to use to verify the data
 */
Key VerifyRequest::key() const
{
    Q_D(const VerifyRequest);
    return d->m_key;
}

/*!
  \brief Sets the key which the client wishes the system service to use to verify the data to \a key
 */
void VerifyRequest::setKey(const Key &key)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_key != key) {
        d->m_key = key;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyChanged();
    }
}

/*!
  \qmlproperty enumeration VerifyRequest::padding
  \brief The signature padding mode which was used when signing the data
  \value SignaturePaddingUnknown
  \value SignaturePaddingCustom
  \value SignaturePaddingNone
  \value SignaturePaddingRsaPss
  \value SignaturePaddingRsaPkcs1    = EncryptionPaddingRsaPkcs1
  \value SignaturePaddingAnsiX923    = EncryptionPaddingAnsiX923
*/

/*!
  \brief Returns the signature padding mode which was used when signing the data
 */
Sailfish::Crypto::CryptoManager::SignaturePadding VerifyRequest::padding() const
{
    Q_D(const VerifyRequest);
    return d->m_padding;
}

/*!
  \brief Sets the signature padding mode which was used when signing the data to \a padding
 */
void VerifyRequest::setPadding(Sailfish::Crypto::CryptoManager::SignaturePadding padding)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_padding != padding) {
        d->m_padding = padding;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit paddingChanged();
    }
}

/*!
  \qmlproperty enumeration VerifyRequest::digestFunction
  \brief The digest which was used to generate the signature
  \value DigestUnknown
  \value DigestCustom
  \value DigestMd5
  \value DigestSha1
  \value DigestSha2_224
  \value DigestSha2_256
  \value DigestSha256        = DigestSha2_256
  \value DigestSha2_384
  \value DigestSha2_512
  \value DigestSha512        = DigestSha2_512
  \value DigestSha2_512_224
  \value DigestSha2_512_256
  \value DigestSha3_224
  \value DigestSha3_256
  \value DigestSha3_384
  \value DigestSha3_512
  \value DigestShake128
  \value DigestShake256
  \value DigestGost_94
  \value DigestGost_2012_256
  \value DigestGost_2012_512
  \value DigestBlake
  \value DigestBlake2
  \value DigestBlake2b
  \value DigestBlake2s
  \value DigestWhirlpool
  \value DigestRipeMd
  \value DigestRipeMd128_256
  \value DigestRipeMd160
  \value DigestRipeMd320
  \value DigestTiger
  \value DigestTiger128
  \value DigestTiger160
  \value DigestTiger192
  \value DigestTiger2
  \value DigestTiger2_128
  \value DigestTiger2_160
  \value DigestTiger2_192
  \value DigestRadioGatun
*/

/*!
  \brief Returns the digest which was used to generate the signature
 */
Sailfish::Crypto::CryptoManager::DigestFunction VerifyRequest::digestFunction() const
{
    Q_D(const VerifyRequest);
    return d->m_digestFunction;
}

/*!
  \brief Sets the digest which was used to generate the signature to \a digestFn
 */
void VerifyRequest::setDigestFunction(Sailfish::Crypto::CryptoManager::DigestFunction digestFn)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_digestFunction != digestFn) {
        d->m_digestFunction = digestFn;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit digestFunctionChanged();
    }
}

/*!
  \qmlproperty string VerifyRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the verification operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the verification operation
 */
QString VerifyRequest::cryptoPluginName() const
{
    Q_D(const VerifyRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the verification operation to \a pluginName
 */
void VerifyRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && d->m_cryptoPluginName != pluginName) {
        d->m_cryptoPluginName = pluginName;
        if (d->m_verificationStatus != Sailfish::Crypto::CryptoManager::VerificationStatusUnknown) {
            d->m_verificationStatus = Sailfish::Crypto::CryptoManager::VerificationStatusUnknown;
            emit verificationStatusChanged();
        }
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit cryptoPluginNameChanged();
    }
}

/*!
  \qmlproperty Sailfish::Crypto::CryptoManager::VerificationStatus VerifyRequest::verificationStatus
  \brief Returns verification result
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
  \brief Returns VerificationSucceeded if signature data was determined to have been signed with the specified key.

  Note: this value is only valid if the status of the request is Request::Finished.
 */
Sailfish::Crypto::CryptoManager::VerificationStatus VerifyRequest::verificationStatus() const
{
    Q_D(const VerifyRequest);
    return d->m_verificationStatus;
}

Request::Status VerifyRequest::status() const
{
    Q_D(const VerifyRequest);
    return d->m_status;
}

Result VerifyRequest::result() const
{
    Q_D(const VerifyRequest);
    return d->m_result;
}

QVariantMap VerifyRequest::customParameters() const
{
    Q_D(const VerifyRequest);
    return d->m_customParameters;
}

void VerifyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(VerifyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *VerifyRequest::manager() const
{
    Q_D(const VerifyRequest);
    return d->m_manager.data();
}

void VerifyRequest::setManager(CryptoManager *manager)
{
    Q_D(VerifyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void VerifyRequest::startRequest()
{
    Q_D(VerifyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Sailfish::Crypto::CryptoManager::VerificationStatus> reply =
                d->m_manager->d_ptr->verify(d->m_signature,
                                            d->m_data,
                                            d->m_key,
                                            d->m_padding,
                                            d->m_digestFunction,
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
            d->m_verificationStatus = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit verificationStatusChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, Sailfish::Crypto::CryptoManager::VerificationStatus> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_verificationStatus = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->verificationStatusChanged();
            });
        }
    }
}

void VerifyRequest::waitForFinished()
{
    Q_D(VerifyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
