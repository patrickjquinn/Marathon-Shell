// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_RESULT_H
#define LIBSAILFISHSECRETS_RESULT_H

#include "Secrets/secretsglobal.h"

#include <QtCore/QString>
#include <QtCore/QMetaType>
#include <QtCore/QSharedDataPointer>

namespace Sailfish {

namespace Secrets {

class ResultPrivate;
class SAILFISH_SECRETS_API Result
{
    Q_GADGET
    Q_PROPERTY(QString errorMessage READ errorMessage WRITE setErrorMessage)
    Q_PROPERTY(Sailfish::Secrets::Result::ErrorCode errorCode READ errorCode WRITE setErrorCode)
    Q_PROPERTY(Sailfish::Secrets::Result::ResultCode code READ code WRITE setCode)

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
        DaemonError = 5,
        DiscoveryError = 6,

        PermissionsError = 10,
        IncorrectAuthenticationCodeError,
        AuthenticationTimeoutError,
        OperationNotSupportedError,
        OperationRequiresUserInteraction,
        OperationRequiresApplicationUserInteraction,
        OperationRequiresSystemUserInteraction,
        SecretManagerNotInitializedError,

        SecretsDaemonRequestPidError = 20,
        SecretsDaemonRequestQueueFullError,
        SecretsDaemonLockedError,
        SecretsDaemonNotLockedError,

        SecretsPluginEncryptionError = 30,
        SecretsPluginDecryptionError,
        SecretsPluginKeyDerivationError,
        SecretsPluginIsLockedError,

        InvalidSecretError = 40,
        InvalidSecretIdentifierError,
        InvalidFilterError,
        InvalidCollectionError,
        InvalidExtensionPluginError,
        InvalidApplicationIdError,
        CollectionAlreadyExistsError,
        SecretAlreadyExistsError,

        CollectionIsLockedError = 60,
        CollectionIsBusyError,

        DatabaseQueryError = 70,
        DatabaseTransactionError,
        DatabaseError,

        InteractionServiceUnknownError = 80,
        InteractionServiceUnavailableError,
        InteractionServiceRequestInvalidError,
        InteractionServiceRequestFailedError,
        InteractionServiceRequestBusyError,
        InteractionServiceResponseInvalidError,

        InteractionViewUnavailableError = 90,
        InteractionViewRequestError,
        InteractionViewParentError,
        InteractionViewChildError,
        InteractionViewError,
        InteractionViewUserCanceledError,

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

    Result(Sailfish::Secrets::Result::ResultCode resultCode = Succeeded);
    Result(Sailfish::Secrets::Result::ErrorCode errorCode, const QString &errorMessage);
    Result(const Result &other);
    ~Result();

    Result &operator=(const Sailfish::Secrets::Result &other);

    void setErrorMessage(const QString &m);
    QString errorMessage() const;

    Q_INVOKABLE void setErrorCode(int c);
    void setErrorCode(Sailfish::Secrets::Result::ErrorCode c);
    Sailfish::Secrets::Result::ErrorCode errorCode() const;

    Q_INVOKABLE void setCode(int c);
    void setCode(Sailfish::Secrets::Result::ResultCode c);
    Sailfish::Secrets::Result::ResultCode code() const;

private:
    QSharedDataPointer<ResultPrivate> d_ptr;
    friend class ResultPrivate;
};

bool operator==(const Sailfish::Secrets::Result &lhs, const Sailfish::Secrets::Result &rhs) SAILFISH_SECRETS_API;
bool operator!=(const Sailfish::Secrets::Result &lhs, const Sailfish::Secrets::Result &rhs) SAILFISH_SECRETS_API;
bool operator<(const Sailfish::Secrets::Result &lhs, const Sailfish::Secrets::Result &rhs) SAILFISH_SECRETS_API;

} // Secrets

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Secrets::Result);
Q_DECLARE_TYPEINFO(Sailfish::Secrets::Result, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHSECRETS_RESULT_H
