// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/cipherrequest.h"
#include "Crypto/cipherrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

CipherRequestPrivate::CipherRequestPrivate()
    : m_cipherMode(CipherRequest::InitializeCipher)
    , m_blockMode(CryptoManager::BlockModeCbc)
    , m_encryptionPadding(CryptoManager::EncryptionPaddingNone)
    , m_signaturePadding(CryptoManager::SignaturePaddingNone)
    , m_digestFunction(CryptoManager::DigestSha256)
    , m_cipherSessionToken(0)
    , m_verificationStatus(Sailfish::Crypto::CryptoManager::VerificationStatusUnknown)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype CipherRequest
  \brief Allows the client to request a cipher session from the system crypto service
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::CipherRequest
*/

/*!
  \class CipherRequest
  \brief Allows the client to request a cipher session from the system crypto service
  \inmodule SailfishCrypto
  \inheaderfile Crypto/cipherrequest.h
 */

/*!
  \brief Constructs a new CipherRequest object with the given \a parent.
 */
CipherRequest::CipherRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new CipherRequestPrivate)
{
}

/*!
  \brief Destroys the CipherRequest
 */
CipherRequest::~CipherRequest()
{
}

/*!
  \qmlproperty enumeration CipherRequest::cipherMode
  \brief The mode which the client wishes to apply to the cipher session
  \value InitializeCipher
  \value UpdateCipherAuthentication
  \value UpdateCipher
  \value FinalizeCipher
*/

/*!
  \brief Returns the mode which the client wishes to apply to the cipher session
 */
CipherRequest::CipherMode CipherRequest::cipherMode() const
{
    Q_D(const CipherRequest);
    return d->m_cipherMode;
}

/*!
  \brief Sets the mode which the client wishes to apply to the cipher session to \a mode

  The mode will be applied by the system crypto service to the cipher session.
  In general, the client will want to initialize the cipher session, and then
  repeatedly update the cipher session with data to be operated upon, and
  then when finished with all data should finalize the cipher session.

  The following example shows how to use a CipherRequest to encrypt a stream
  of data using AES 256 encryption in CBC mode.  Note that it forces the
  request to finish synchronously, however this is purely to keep the example
  concise; real code should \bold{not} use the waitForFinished() method,
  but instead should react to the statusChanged() signal to determine when
  each step of the request has finished.  Also, error checking has been
  omitted for brevity.

  \code
  QByteArray ciphertext;
  CipherRequest cr;
  cr.setManager(cryptoManager);

  // Initialize the cipher.
  cr.setCipherMode(CipherRequest::InitializeCipher);
  cr.setKey(key); // a valid AES 256 key or key reference
  cr.setBlockMode(Sailfish::Crypto::CryptoManager::BlockModeCbc);
  cr.setOperation(Sailfish::Crypto::CryptoManager::OperationEncrypt);
  cr.setInitializationVector(initializationVector);    // See GenerateInitializationVectorRequest
  cr.startRequest();
  cr.waitForFinished();

  // Update the cipher session with data to encrypt.
  while (morePlaintextBlocks()) {
      cr.setCipherMode(CipherRequest::UpdateCipher);
      cr.setData(getPlaintextBlock()); // e.g. read from file
      cr.startRequest();
      cr.waitForFinished();
      ciphertext.append(cr.generatedData());
  }

  // Finalize the cipher session.
  cr.setCipherMode(CipherRequest::FinalizeCipher);
  cr.startRequest();
  cr.waitForFinished();
  ciphertext.append(cr.generatedData());
  \endcode

  To decrypt some ciphertext, the same initialization vector must be
  specified as was used to encrypt the plaintext data originally.
  An example of decrypting data follows:

  \code
  QByteArray plaintext;
  CipherRequest cr;
  cr.setManager(cryptoManager);

  // Initialize the cipher.
  cr.setCipherMode(CipherRequest::InitializeCipher);
  cr.setKey(key); // a valid AES 256 key or key reference
  cr.setBlockMode(Sailfish::Crypto::CryptoManager::BlockModeCbc);
  cr.setOperation(Sailfish::Crypto::CryptoManager::OperationDecrypt);
  cr.setInitializationVector(initializationVector); // IV used during encryption.
  cr.startRequest();
  cr.waitForFinished();

  // Update the cipher session with data to decrypt.
  while (moreCiphertextBlocks()) {
      cr.setCipherMode(CipherRequest::UpdateCipher);
      cr.setData(getCiphertextBlock()); // e.g. read from file
      cr.startRequest();
      cr.waitForFinished();
      // Note: in CBC mode the first generatedData() will be smaller
      // than the input data by one complete block (16 bytes for AES 256).
      plaintext.append(cr.generatedData());
  }

  // Finalize the cipher session.
  cr.setCipherMode(CipherRequest::FinalizeCipher);
  cr.startRequest();
  cr.waitForFinished();
  plaintext.append(cr.generatedData());
  \endcode

  Note that authenticated encryption and decryption is slightly
  different, as encryption finalization produces an authentication tag, which must
  be provided during decryption finalization for verification.
  For example, after encrypting data using BlockModeGcm:

  \code
  // Finalize the GCM encryption cipher session.
  cr.setCipherMode(CipherRequest::FinalizeCipher);
  cr.startRequest();
  cr.waitForFinished();
  QByteArray gcmTag = cr.generatedData();
  \endcode

  and when decrypting, the authentication tag should be provided for finalization
  and the verificationStatus flag should be checked carefully:

  \code
  // Finalize the GCM decryption cipher session.
  cr.setCipherMode(CipherRequest::FinalizeCipher);
  cr.setData(gcmTag);
  cr.startRequest();
  cr.waitForFinished();
  Sailfish::Crypto::CryptoManager::VerificationStatus status = cr.verificationStatus();
  \endcode

  If \a mode is either CipherRequest::UpdateCipher or
  CipherRequest::FinalizeCipher then when the request is finished
  the generatedData() should contain the block of data which
  was generated based upon the input data (that is, it will be
  encrypted, decrypted, or signature data) or alternatively
  verificationStatus() should contain whether the signature data was
  verificationStatus or if authenticated decryption succeeded, if the
  operation() was CryptoManager::OperationEncrypt, CryptoManager::OperationDecrypt,
  CryptoManager::Sign, or CryptoManager::Verify or CryptoManager::OperationDecrypt
  with BlockModeGcm respectively.
 */
void CipherRequest::setCipherMode(CipherRequest::CipherMode mode)
{
    Q_D(CipherRequest);
    if (d->m_status != Request::Active && d->m_cipherMode != mode) {
        d->m_cipherMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit cipherModeChanged();
    }
}

/*!
  \qmlproperty enumeration CipherRequest::operation
  \brief The operation which the client wishes to perform with the cipher session
  \value OperationUnknown
  \value OperationCustom
  \value OperationSign
  \value OperationVerify
  \value OperationEncrypt
  \value OperationDecrypt
  \value OperationCalculateDigest
  \value OperationCalculateMac
  \value OperationDeriveKey
*/

/*!
  \brief Returns the operation which the client wishes to perform with the cipher session
 */
CryptoManager::Operation CipherRequest::operation() const
{
    Q_D(const CipherRequest);
    return d->m_operation;
}

/*!
  \brief Sets the operation which the client wishes to perform with the cipher session to \a op

  Note: this parameter is only meaningful prior to initializing the cipher.  Once
  initialized, the operation of the cipher cannot be changed.
 */
void CipherRequest::setOperation(CryptoManager::Operation op)
{
    Q_D(CipherRequest);
    if (d->m_status != Request::Active && d->m_operation != op) {
        d->m_operation = op;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit operationChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer CipherRequest::data
  \brief The data which the client wishes the system service to operate on
*/

/*!
  \brief Returns the data which the client wishes the system service to operate on
 */
QByteArray CipherRequest::data() const
{
    Q_D(const CipherRequest);
    return d->m_data;
}

/*!
  \brief Sets the data which the client wishes the system service to operate on to \a data
 */
void CipherRequest::setData(const QByteArray &data)
{
    Q_D(CipherRequest);
    if (d->m_data != data) {
        d->m_data = data;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit dataChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer CipherRequest::initializationVector
  \brief The initialization vector which the client wishes to use when encrypting or decrypting the data
*/

/*!
  \brief Returns the initialization vector which the client wishes to use when encrypting or decrypting the data
 */
QByteArray CipherRequest::initializationVector() const
{
    Q_D(const CipherRequest);
    return d->m_initializationVector;
}

/*!
  \brief Sets the initialization vector which the client wishes to use when encrypting or decrypting the data to \a iv

  This initialization vector data will only be used for encrypt or decrypt operations, and is only
  passed to the system service when the cipher mode is \l{CipherRequest::InitializeCipher}.

  Note that this is only applicable for certain key types using certain
  modes of encryption or decryption (e.g. CBC mode with AES symmetric keys).

  The client must specify the same initialization vector when decrypting
  the cipher text as they used when encrypting it.  The initialization
  vector is not secret, and can be stored along with the ciphertext,
  however it should be generated using a cryptographically secure
  random number generator (see \l{GenerateRandomDataRequest}) and must
  be the appropriate size according to the cipher.
 */
void CipherRequest::setInitializationVector(const QByteArray &iv)
{
    Q_D(CipherRequest);
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
  \qmlproperty Key CipherRequest::key
  \brief The key which the client wishes the system service to use to encrypt the data
*/

/*!
  \brief Returns the key which the client wishes the system service to use to encrypt the data
 */
Key CipherRequest::key() const
{
    Q_D(const CipherRequest);
    return d->m_key;
}

/*!
  \brief Sets the key which the client wishes the system service to use to encrypt the data to \a key
 */
void CipherRequest::setKey(const Key &key)
{
    Q_D(CipherRequest);
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
  \qmlproperty enumeration CipherRequest::blockMode
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
  \brief Returns the block mode which should be used when encrypting the data
 */
Sailfish::Crypto::CryptoManager::BlockMode CipherRequest::blockMode() const
{
    Q_D(const CipherRequest);
    return d->m_blockMode;
}

/*!
  \brief Sets the block mode which should be used when encrypting the data to \a mode
 */
void CipherRequest::setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode)
{
    Q_D(CipherRequest);
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
  \qmlproperty enumeration CipherRequest::encryptionPadding
  \brief The encryption padding mode which should be used when encrypting or decrypting the data
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
  \brief Returns the encryption padding mode which should be used when encrypting or decrypting the data
 */
Sailfish::Crypto::CryptoManager::EncryptionPadding CipherRequest::encryptionPadding() const
{
    Q_D(const CipherRequest);
    return d->m_encryptionPadding;
}

/*!
  \brief Sets the encryption padding mode which should be used when encrypting or decrypting the data to \a padding
 */
void CipherRequest::setEncryptionPadding(Sailfish::Crypto::CryptoManager::EncryptionPadding padding)
{
    Q_D(CipherRequest);
    if (d->m_status != Request::Active && d->m_encryptionPadding != padding) {
        d->m_encryptionPadding = padding;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit encryptionPaddingChanged();
    }
}

/*!
  \qmlproperty enumeration CipherRequest::signaturePadding
  \brief The signature padding mode which should be used when signing or verifying the data
  \value SignaturePaddingUnknown
  \value SignaturePaddingCustom
  \value SignaturePaddingNone
  \value SignaturePaddingRsaPss
  \value SignaturePaddingRsaPkcs1    = EncryptionPaddingRsaPkcs1
  \value SignaturePaddingAnsiX923    = EncryptionPaddingAnsiX923
*/

/*!
  \brief Returns the signature padding mode which should be used when signing or verifying the data
 */
Sailfish::Crypto::CryptoManager::SignaturePadding CipherRequest::signaturePadding() const
{
    Q_D(const CipherRequest);
    return d->m_signaturePadding;
}

/*!
  \brief Sets the signature padding mode which should be used when signing or verifying the data to \a padding
 */
void CipherRequest::setSignaturePadding(Sailfish::Crypto::CryptoManager::SignaturePadding padding)
{
    Q_D(CipherRequest);
    if (d->m_status != Request::Active && d->m_signaturePadding != padding) {
        d->m_signaturePadding = padding;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit signaturePaddingChanged();
    }
}

/*!
  \qmlproperty enumeration CipherRequest::digestFunction
  \brief The digest which should be used when signing or verifying the data
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
  \brief Returns the digest which should be used when signing or verifying the data
 */
Sailfish::Crypto::CryptoManager::DigestFunction CipherRequest::digestFunction() const
{
    Q_D(const CipherRequest);
    return d->m_digestFunction;
}

/*!
  \brief Sets tthe digest which should be used when signing or verifying the data to \a digestFn
 */
void CipherRequest::setDigestFunction(Sailfish::Crypto::CryptoManager::DigestFunction digestFn)
{
    Q_D(CipherRequest);
    if (d->m_status != Request::Active && d->m_digestFunction != digestFn) {
        d->m_digestFunction = digestFn;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit digestFunctionChanged();
    }
}

/*!
  \qmlproperty string CipherRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the encryption operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the encryption operation
 */
QString CipherRequest::cryptoPluginName() const
{
    Q_D(const CipherRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the encryption operation to \a pluginName
 */
void CipherRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(CipherRequest);
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
  \qmlproperty ArrayBuffer CipherRequest::generatedData
  \brief Returns the generated data result of the cipher operation.
  \note this value is only valid if the status of the request is \c Request.Finished
*/

/*!
  \brief Returns the generated data result of the cipher operation.

  Note: this value is only valid if the status of the request is Request::Finished.
 */
QByteArray CipherRequest::generatedData() const
{
    Q_D(const CipherRequest);
    return d->m_generatedData;
}

/*!
  \qmlproperty Sailfish::Crypto::CryptoManager::VerificationStatus CipherRequest::verificationStatus
  \brief Returns the result of the verify operation.
  \note this value is only valid if the status of the request is \c Request.Finished
  and the cipher session has been finalized and the \c operation was
  CryptoManager.OperationVerify
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
  \brief Returns the result of the verify operation.

  Note: this value is only valid if the status of the request is Request::Finished
  and the cipher session has been finalized and the operation() was
  CryptoManager::OperationVerify.
 */
Sailfish::Crypto::CryptoManager::VerificationStatus CipherRequest::verificationStatus() const
{
    Q_D(const CipherRequest);
    return d->m_verificationStatus;
}

Request::Status CipherRequest::status() const
{
    Q_D(const CipherRequest);
    return d->m_status;
}

Result CipherRequest::result() const
{
    Q_D(const CipherRequest);
    return d->m_result;
}

QVariantMap CipherRequest::customParameters() const
{
    Q_D(const CipherRequest);
    return d->m_customParameters;
}

void CipherRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(CipherRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *CipherRequest::manager() const
{
    Q_D(const CipherRequest);
    return d->m_manager.data();
}

void CipherRequest::setManager(CryptoManager *manager)
{
    Q_D(CipherRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void CipherRequest::startRequest()
{
    Q_D(CipherRequest);
    if (!d->m_manager.isNull()) {
        if (d->m_status != Request::Active) {
            d->m_status = Request::Active;
            emit statusChanged();
        }
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        if (d->m_cipherMode == CipherRequest::InitializeCipher) {
            for (QDBusPendingCallWatcher *w : d->m_watcherQueue) {
                w->deleteLater();
            }
            d->m_watcherQueue.clear();
            d->m_cipherSessionToken = 0;
            QDBusPendingReply<Result, quint32> reply =
                    d->m_manager->d_ptr->initializeCipherSession(
                        d->m_initializationVector,
                        d->m_key,
                        d->m_operation,
                        d->m_blockMode,
                        d->m_encryptionPadding,
                        d->m_signaturePadding,
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
                d->m_cipherSessionToken = reply.argumentAt<1>();
                emit statusChanged();
                emit resultChanged();
            } else {
                QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply);
                d->m_watcherQueue.enqueue(watcher);
                connect(watcher, &QDBusPendingCallWatcher::finished,
                        [this] {
                    QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcherQueue.dequeue();
                    QDBusPendingReply<Result, quint32> reply = *watcher;
                    bool needsStEmit = false;
                    if (this->d_ptr->m_watcherQueue.isEmpty() && this->d_ptr->m_status != Request::Finished) {
                        needsStEmit = true;
                        this->d_ptr->m_status = Request::Finished;
                    }
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_cipherSessionToken = reply.argumentAt<1>();
                    if (this->d_ptr->m_result.code() == Result::Succeeded
                            && this->d_ptr->m_cipherSessionToken == 0) {
                        this->d_ptr->m_result = Result(Result::CryptoPluginInvalidCipherSessionToken,
                                                       QStringLiteral("Plugin returned invalid cipher session token"));
                    }
                    watcher->deleteLater();
                    if (needsStEmit) {
                        emit this->statusChanged();
                    }
                    emit this->resultChanged();
                });
            }
        } else if (d->m_cipherMode == CipherRequest::UpdateCipherAuthentication) {
            if (d->m_cipherSessionToken == 0) {
                qWarning() << "Ignoring attempt to update authentication for uninitialized cipher session!";
            } else {
                QDBusPendingReply<Result> reply =
                        d->m_manager->d_ptr->updateCipherSessionAuthentication(
                                d->m_data,
                                d->m_customParameters,
                                d->m_cryptoPluginName,
                                d->m_cipherSessionToken);
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
                    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply);
                    d->m_watcherQueue.enqueue(watcher);
                    connect(watcher, &QDBusPendingCallWatcher::finished,
                            [this] {
                        QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcherQueue.dequeue();
                        QDBusPendingReply<Result> reply = *watcher;
                        bool needsStEmit = false;
                        if (this->d_ptr->m_watcherQueue.isEmpty() && this->d_ptr->m_status != Request::Finished) {
                            needsStEmit = true;
                            this->d_ptr->m_status = Request::Finished;
                        }
                        this->d_ptr->m_result = reply.argumentAt<0>();
                        watcher->deleteLater();
                        if (needsStEmit) {
                            emit this->statusChanged();
                        }
                        emit this->resultChanged();
                    });
                }
            }
        } else if (d->m_cipherMode == CipherRequest::UpdateCipher) {
            if (d->m_cipherSessionToken == 0) {
                qWarning() << "Ignoring attempt to update data for uninitialized cipher session!";
            } else {
                QDBusPendingReply<Result, QByteArray> reply =
                        d->m_manager->d_ptr->updateCipherSession(
                                d->m_data,
                                d->m_customParameters,
                                d->m_cryptoPluginName,
                                d->m_cipherSessionToken);
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
                    bool needsGdEmit = false;
                    if (d->m_generatedData != reply.argumentAt<1>()) {
                        needsGdEmit = true;
                        d->m_generatedData = reply.argumentAt<1>();
                    }
                    emit statusChanged();
                    emit resultChanged();
                    if (needsGdEmit) {
                        emit generatedDataChanged();
                    }
                } else {
                    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply);
                    d->m_watcherQueue.enqueue(watcher);
                    connect(watcher, &QDBusPendingCallWatcher::finished,
                            [this, watcher] {
                        this->d_ptr->m_completedHash.insert(watcher, true);
                        QDBusPendingCallWatcher *head = this->d_ptr->m_watcherQueue.size()
                                ? this->d_ptr->m_watcherQueue.head()
                                : Q_NULLPTR;
                        while (head && this->d_ptr->m_completedHash.value(head, false)) {
                            this->d_ptr->m_completedHash.remove(head);
                            head = this->d_ptr->m_watcherQueue.dequeue();
                            QDBusPendingReply<Result, QByteArray> reply = *head;
                            bool needsStEmit = false;
                            if (this->d_ptr->m_watcherQueue.isEmpty() && this->d_ptr->m_status != Request::Finished) {
                                needsStEmit = true;
                                this->d_ptr->m_status = Request::Finished;
                            }
                            this->d_ptr->m_result = reply.argumentAt<0>();
                            this->d_ptr->m_generatedData = reply.argumentAt<1>();
                            head->deleteLater();
                            head = this->d_ptr->m_watcherQueue.size()
                                    ? this->d_ptr->m_watcherQueue.head()
                                    : Q_NULLPTR;
                            if (needsStEmit) {
                                emit this->statusChanged();
                            }
                            emit this->resultChanged();
                            emit this->generatedDataChanged();
                        }
                    });
                }
            }
        } else {
            if (d->m_cipherSessionToken == 0) {
                qWarning() << "Ignoring attempt to finalize uninitialized cipher session!";
            } else {
                QDBusPendingReply<Result, QByteArray, CryptoManager::VerificationStatus> reply =
                        d->m_manager->d_ptr->finalizeCipherSession(
                                d->m_data,
                                d->m_customParameters,
                                d->m_cryptoPluginName,
                                d->m_cipherSessionToken);
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
                    bool needsGdEmit = false;
                    if (d->m_generatedData != reply.argumentAt<1>()) {
                        needsGdEmit = true;
                        d->m_generatedData = reply.argumentAt<1>();
                    }
                    bool needsVfEmit = false;
                    if (d->m_verificationStatus != reply.argumentAt<2>()) {
                        needsVfEmit = true;
                        d->m_verificationStatus = reply.argumentAt<2>();
                    }
                    emit statusChanged();
                    emit resultChanged();
                    if (needsGdEmit) {
                        emit generatedDataChanged();
                    }
                    if (needsVfEmit) {
                        emit verificationStatusChanged();
                    }
                } else {
                    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply);
                    d->m_watcherQueue.enqueue(watcher);
                    connect(watcher, &QDBusPendingCallWatcher::finished,
                            [this] {
                        QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcherQueue.dequeue();
                        QDBusPendingReply<Result, QByteArray, CryptoManager::VerificationStatus> reply = *watcher;
                        bool needsStEmit = false;
                        if (this->d_ptr->m_watcherQueue.isEmpty() && this->d_ptr->m_status != Request::Finished) {
                            needsStEmit = true;
                            this->d_ptr->m_status = Request::Finished;
                        }
                        bool needsVfEmit = false;
                        if (reply.isError()) {
                            this->d_ptr->m_result = Result(Result::DaemonError,
                                                           reply.error().message());
                        } else {
                            this->d_ptr->m_result = reply.argumentAt<0>();
                            if (this->d_ptr->m_result.code() == Result::Succeeded) {
                                this->d_ptr->m_cipherSessionToken = 0;
                            }
                            this->d_ptr->m_generatedData = reply.argumentAt<1>();
                            if (this->d_ptr->m_verificationStatus != reply.argumentAt<2>()) {
                                needsVfEmit = true;
                                this->d_ptr->m_verificationStatus = reply.argumentAt<2>();
                            }
                        }
                        watcher->deleteLater();
                        if (needsStEmit) {
                            emit this->statusChanged();
                        }
                        emit this->resultChanged();
                        emit this->generatedDataChanged();
                        if (needsVfEmit) {
                            emit verificationStatusChanged();
                        }
                    });
                }
            }
        }
    }
}

void CipherRequest::waitForFinished()
{
    Q_D(CipherRequest);
    if (d->m_status == Request::Active && !d->m_watcherQueue.isEmpty()) {
        QDBusPendingCallWatcher *watcher = d->m_watcherQueue.last(); // tail().
        watcher->waitForFinished();
    }
}
