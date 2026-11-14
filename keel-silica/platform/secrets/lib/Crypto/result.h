// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_RESULT_H
#define LIBSAILFISHCRYPTO_RESULT_H

#include "Crypto/cryptoglobal.h"

#include <QtCore/QString>
#include <QtCore/QMetaType>
#include <QtCore/QSharedDataPointer>

namespace Sailfish {

namespace Crypto {

class ResultPrivate;
class SAILFISH_CRYPTO_API Result
{
    Q_GADGET
    Q_PROPERTY(QString errorMessage READ errorMessage WRITE setErrorMessage)
    Q_PROPERTY(int storageErrorCode READ storageErrorCode WRITE setStorageErrorCode)
    Q_PROPERTY(Sailfish::Crypto::Result::ErrorCode errorCode READ errorCode WRITE setErrorCode)
    Q_PROPERTY(Sailfish::Crypto::Result::ResultCode code READ code WRITE setCode)

public:
    enum ResultCode {
        Succeeded = 0,
        Pending   = 1,
        Failed    = 2
    };
    Q_ENUM(ResultCode)

    enum ErrorCode {
        NoError = 0,
        UnknownError = 2,
        SerializationError = 3,
        StorageError = 4,
        DaemonError = 5,
        DiscoveryError = 6,

        InvalidCryptographicServiceProvider = 10,
        InvalidStorageProvider,
        InvalidKeyIdentifier,
        DuplicateKeyIdentifier,
        CryptoManagerNotInitializedError,
        InvalidInitializationVectorError,
        InvalidAuthenticationTagError,

        OperationNotSupportedError = 20,
        BlockModeNotSupportedError,
        EncryptionPaddingNotSupportedError,
        SignaturePaddingNotSupportedError,
        DigestNotSupportedError,

        EmptySecretKeyError = 30,
        EmptyPrivateKeyError,
        EmptyPublicKeyError,
        EmptyDataError,
        EmptySignatureError,

        CryptoPluginEncryptionError = 40,
        CryptoPluginDecryptionError,
        CryptoPluginRandomDataError,
        CryptoPluginCipherSessionError,
        CryptoPluginKeyGenerationError,
        CryptoPluginKeyImportError,
        CryptoPluginDigestError,
        CryptoPluginSigningError,
        CryptoPluginVerificationError,
        CryptoPluginAuthenticationTagError,
        CryptoPluginInvalidCipherSessionToken,
        CryptoPluginIncorrectPassphrase,
        CryptoPluginIsLockedError,

        NetworkError = 98,
        NetworkSslError = 99,
        HttpContinue = 100,
        HttpSwitchingProtocol = 101,
        HttpOk = 200,
        HttpCreated = 201,
        HttpAccepted = 202,
        HttpNonAuthoritativeInformation = 203,
        HttpNoContent = 204,
        HttpResetContent = 205,
        HttpPartialContent = 206,
        HttpMultipleChoice = 300,
        HttpMovedPermanently = 301,
        HttpFound = 302,
        HttpSeeOther = 303,
        HttpNotModified = 304,
        HttpUseProxy = 305,
        HttpUnused = 306,
        HttpTemporaryRedirect = 307,
        HttpPermanentRedirect = 308,
        HttpBadRequest = 400,
        HttpUnauthorized = 401,
        HttpPaymentRequired = 402,
        HttpForbidden = 403,
        HttpNotFound = 404,
        HttpMethodNotAllowed = 405,
        HttpNotAcceptable = 406,
        HttpProxyAuthenticationRequired = 407,
        HttpRequestTimeout = 408,
        HttpConflict = 409,
        HttpGone = 410,
        HttpLengthRequired = 411,
        HttpPreconditionFailed = 412,
        HttpPayloadTooLarge = 413,
        HttpUriTooLong = 414,
        HttpUnsupportedMediaType = 415,
        HttpRequestRangeNotSatisfiable = 416,
        HttpExpectationFailed = 417,
        HttpMisdirectedRequest = 421,
        HttpUpgradeRequired = 426,
        HttpPreconditionRequired = 428,
        HttpTooManyRequests = 429,
        HttpRequestHeaderFieldsTooLarge = 431,
        HttpUnavailableForLegalReasons = 451,
        HttpInternalServerError = 500,
        HttpNotImplemented = 501,
        HttpBadGateway = 502,
        HttpServiceUnavailable = 503,
        HttpGatewayTimeout = 504,
        HttpVersionNotSupported = 505,
        HttpVariantAlsoNegotiates = 506,
        HttpInsufficientStorage = 507,
        HttpNetworkAuthenticationRequired = 511,

        OtherError = 1024,
    };
    Q_ENUM(ErrorCode)

    Result(Sailfish::Crypto::Result::ResultCode resultCode = Succeeded);
    Result(Sailfish::Crypto::Result::ErrorCode errorCode, const QString &errorMessage);
    Result(Sailfish::Crypto::Result::ErrorCode errorCode, int storageErrorCode, const QString &errorMessage);
    Result(const Result &other);
    ~Result();

    Result &operator=(const Sailfish::Crypto::Result &other);

    void setErrorMessage(const QString &m);
    QString errorMessage() const;

    void setStorageErrorCode(int c);
    int storageErrorCode() const;

    Q_INVOKABLE void setErrorCode(int c);
    void setErrorCode(Sailfish::Crypto::Result::ErrorCode c);
    Sailfish::Crypto::Result::ErrorCode errorCode() const;

    Q_INVOKABLE void setCode(int c);
    void setCode(Sailfish::Crypto::Result::ResultCode c);
    Sailfish::Crypto::Result::ResultCode code() const;

private:
    QSharedDataPointer<ResultPrivate> d_ptr;
    friend class ResultPrivate;
};

bool operator==(const Sailfish::Crypto::Result &lhs, const Sailfish::Crypto::Result &rhs) SAILFISH_CRYPTO_API;
bool operator!=(const Sailfish::Crypto::Result &lhs, const Sailfish::Crypto::Result &rhs) SAILFISH_CRYPTO_API;
bool operator<(const Sailfish::Crypto::Result &lhs, const Sailfish::Crypto::Result &rhs) SAILFISH_CRYPTO_API;

} // Crypto

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Crypto::Result);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::Result, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHCRYPTO_RESULT_H
