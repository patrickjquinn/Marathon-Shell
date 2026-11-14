// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/result.h"
#include "Crypto/result_p.h"

using namespace Sailfish::Crypto;

//--------------------------------------------

ResultPrivate::ResultPrivate()
    : QSharedData()
    , m_storageErrorCode(0)
    , m_errorCode(Result::NoError)
    , m_code(Result::Succeeded)
{
}

ResultPrivate::ResultPrivate(const ResultPrivate &other)
    : QSharedData(other)
    , m_errorMessage(other.m_errorMessage)
    , m_storageErrorCode(other.m_storageErrorCode)
    , m_errorCode(other.m_errorCode)
    , m_code(other.m_code)
{
}


ResultPrivate::~ResultPrivate()
{
}

//--------------------------------------------

/*!
  \qmltype Result
  \brief The result of a crypto operation
  \inqmlmodule Sailfish.Crypto
*/

/*!
  \class Result
  \brief The result of a crypto operation
  \inmodule SailfishCrypto
  \inheaderfile Crypto/result.h

  The result encapsulates information about whether a given crypto
  operation succeeded, failed, or is pending conclusion.  If the
  operation failed, the result will also include some extra information
  about why the operation failed, to better allow client applications
  to handle the failure gracefully.
 */

/*!
  \brief Constructs a new, empty, successful result.
 */
Result::Result(Result::ResultCode resultCode)
    : d_ptr(new ResultPrivate)
{
    d_ptr->m_code = resultCode;
    d_ptr->m_errorCode = resultCode == Result::Failed
            ? Result::UnknownError
            : Result::NoError;
    d_ptr->m_errorMessage = resultCode == Result::Failed
            ? QString::fromLatin1("Unknown error")
            : QString();
}

/*!
  \brief Constructs a new result with the given \a errorCode and \a errorMessage
 */
Result::Result(Result::ErrorCode errorCode, const QString &errorMessage)
    : d_ptr(new ResultPrivate)
{
    d_ptr->m_errorCode = errorCode;
    d_ptr->m_errorMessage = errorMessage;
    d_ptr->m_code = errorCode >= Result::UnknownError
            ? Result::Failed
            : Result::Succeeded;
}

/*!
  \brief Constructs a new result with the given \a errorCode, \a storageErrorCode and \a errorMessage
 */
Result::Result(Result::ErrorCode errorCode, int storageErrorCode, const QString &errorMessage)
    : d_ptr(new ResultPrivate)
{
    d_ptr->m_errorCode = errorCode;
    d_ptr->m_storageErrorCode = storageErrorCode;
    d_ptr->m_errorMessage = errorMessage;
    d_ptr->m_code = errorCode >= Result::UnknownError
            ? Result::Failed
            : Result::Succeeded;
}

/*!
  \brief Constructs a copy of the \a other result
 */
Result::Result(const Result &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the result
 */
Result::~Result()
{
}

/*!
  \brief Assigns the \a other result to this result
 */
Result& Result::operator=(const Result &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Sets the error message associated with the result to \a m
 */
void Result::setErrorMessage(const QString &m)
{
    d_ptr->m_errorMessage = m;
}

/*!
  \qmlproperty string Result::errorMessage
  \brief The error message associated with the result
*/

/*!
  \brief Returns the error message associated with the result

  The error message is not meant for consumption by users of
  the application, as it will not be translated and may contain
  technical information.  It is primarily intended for use
  by developers during development and debugging of applications.
 */
QString Result::errorMessage() const
{
    return d_ptr->m_errorMessage;
}

/*!
  \brief Sets the storage error code associated with the result to \a c
 */
void Result::setStorageErrorCode(int c)
{
    d_ptr->m_storageErrorCode = c;
}

/*!
  \qmlproperty int Result::storageErrorCode
  \brief The storage error code associated with the result
*/

/*!
  \brief Returns the storage error code associated with the result

  Some crypto operations will interact with the secrets storage backend
  (for example, when retrieving a \l{Key} from some crypto storage plugin).
  Such an operation may fail due to an error emitted by the storage backend,
  and if so, the storage-specific error code will be included here.

  The returned value will be a specific
  \c{Sailfish::Secrets::Result::ErrorCode} value.
 */
int Result::storageErrorCode() const
{
    return d_ptr->m_storageErrorCode;
}

/*!
  \brief Sets the error code associated with the result to \ c
 */
void Result::setErrorCode(int c)
{
    d_ptr->m_errorCode = static_cast<Result::ErrorCode>(c);
}

/*!
  \brief Sets the error code associated with the result to \ c
 */
void Result::setErrorCode(Result::ErrorCode c)
{
    d_ptr->m_errorCode = c;
}

/*!
  \qmlproperty enumeration Result::errorCode
  \brief The error code associated with the result
  \value NoError
  \value UnknownError
  \value SerializationError
  \value StorageError
  \value DaemonError
  \value DiscoveryError

  \value InvalidCryptographicServiceProvider
  \value InvalidStorageProvider
  \value InvalidKeyIdentifier
  \value DuplicateKeyIdentifier
  \value CryptoManagerNotInitializedError
  \value InvalidInitializationVectorError
  \value InvalidAuthenticationTagError

  \value OperationNotSupportedError
  \value BlockModeNotSupportedError
  \value EncryptionPaddingNotSupportedError
  \value SignaturePaddingNotSupportedError
  \value DigestNotSupportedError

  \value EmptySecretKeyError
  \value EmptyPrivateKeyError
  \value EmptyPublicKeyError
  \value EmptyDataError
  \value EmptySignatureError

  \value CryptoPluginEncryptionError
  \value CryptoPluginDecryptionError
  \value CryptoPluginRandomDataError
  \value CryptoPluginCipherSessionError
  \value CryptoPluginKeyGenerationError
  \value CryptoPluginKeyImportError
  \value CryptoPluginDigestError
  \value CryptoPluginSigningError
  \value CryptoPluginVerificationError
  \value CryptoPluginAuthenticationTagError
  \value CryptoPluginInvalidCipherSessionToken
  \value CryptoPluginIncorrectPassphrase
  \value CryptoPluginIsLockedError

  \value NetworkError
  \value NetworkSslError
  \value HttpContinue
  \value HttpSwitchingProtocol
  \value HttpOk
  \value HttpCreated
  \value HttpAccepted
  \value HttpNonAuthoritativeInformation
  \value HttpNoContent
  \value HttpResetContent
  \value HttpPartialContent
  \value HttpMultipleChoice
  \value HttpMovedPermanently
  \value HttpFound
  \value HttpSeeOther
  \value HttpNotModified
  \value HttpUseProxy
  \value HttpUnused
  \value HttpTemporaryRedirect
  \value HttpPermanentRedirect
  \value HttpBadRequest
  \value HttpUnauthorized
  \value HttpPaymentRequired
  \value HttpForbidden
  \value HttpNotFound
  \value HttpMethodNotAllowed
  \value HttpNotAcceptable
  \value HttpProxyAuthenticationRequired
  \value HttpRequestTimeout
  \value HttpConflict
  \value HttpGone
  \value HttpLengthRequired
  \value HttpPreconditionFailed
  \value HttpPayloadTooLarge
  \value HttpUriTooLong
  \value HttpUnsupportedMediaType
  \value HttpRequestRangeNotSatisfiable
  \value HttpExpectationFailed
  \value HttpMisdirectedRequest
  \value HttpUpgradeRequired
  \value HttpPreconditionRequired
  \value HttpTooManyRequests
  \value HttpRequestHeaderFieldsTooLarge
  \value HttpUnavailableForLegalReasons
  \value HttpInternalServerError
  \value HttpNotImplemented
  \value HttpBadGateway
  \value HttpServiceUnavailable
  \value HttpGatewayTimeout
  \value HttpVersionNotSupported
  \value HttpVariantAlsoNegotiates
  \value HttpInsufficientStorage
  \value HttpNetworkAuthenticationRequired

  \value OtherError
*/

/*!
  \brief Returns the error code associated with the result
 */
Result::ErrorCode Result::errorCode() const
{
    return d_ptr->m_errorCode;
}

/*!
  \brief Sets the result code associated with the result to \ c
 */
void Result::setCode(int c)
{
    d_ptr->m_code = static_cast<Result::ResultCode>(c);
}

/*!
  \brief Sets the result code associated with the result to \ c
 */
void Result::setCode(Result::ResultCode c)
{
    d_ptr->m_code = c;
}

/*!
  \qmlproperty enumeration Result::code
  \brief The result code associated with the result
  \value Succeeded
  \value Pending
  \value Failed
*/

/*!
  \brief Returns the result code associated with the result
 */
Result::ResultCode Result::code() const
{
    return d_ptr->m_code;
}

/*!
  \brief Returns true if the \a lhs result is equal to the \a rhs result
 */
bool Sailfish::Crypto::operator==(const Result &lhs, const Result &rhs)
{
    return lhs.code() == rhs.code()
            && lhs.errorCode() == rhs.errorCode()
            && lhs.storageErrorCode() == rhs.storageErrorCode()
            && lhs.errorMessage() == rhs.errorMessage();
}

/*!
  \brief Returns false if the \a lhs result is equal to the \a rhs result
 */
bool Sailfish::Crypto::operator!=(const Result &lhs, const Result &rhs)
{
    return !(operator==(lhs, rhs));
}

/*!
  \brief Returns true if the \a lhs result should sort less than \a rhs result
 */
bool Sailfish::Crypto::operator<(const Result &lhs, const Result &rhs)
{

    if (lhs.code() != rhs.code())
        return lhs.code() < rhs.code();

    if (lhs.errorCode() != rhs.errorCode())
        return lhs.errorCode() < rhs.errorCode();

    if (lhs.storageErrorCode() != rhs.storageErrorCode())
        return lhs.storageErrorCode() < rhs.storageErrorCode();

    return lhs.errorMessage() < rhs.errorMessage();
}
