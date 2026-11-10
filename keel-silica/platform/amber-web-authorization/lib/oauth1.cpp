// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#include "oauth1.h"
#include "redirecturiparser_p.h"

#include <QtCore/QByteArray>
#include <QtCore/QUrlQuery>
#include <QtCore/QUuid>
#include <QtCore/QCryptographicHash>

#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QNetworkReply>

#include <QtMath>

#define BASIC_Q_PROPERTY_SETTER(member, argument, changeSignal) \
        do {                          \
            if (member != argument) { \
                member = argument;    \
                emit changeSignal();  \
            }                         \
        } while (0)

namespace {
    QMap<QString, QString> parseTokenReplyData(const QByteArray &data)
    {
        QMap<QString, QString> response;
        const QList<QByteArray> responseItems = data.split('&');
        for (int i = 0; i < responseItems.size(); ++i) {
            const QByteArray &responseItem(responseItems[i]);
            int equals = responseItem.indexOf('=');
            if (equals != -1) {
                response.insert(responseItem.left(equals),
                                responseItem.mid(equals+1));
            }
        }
        return response;
    }
}

namespace Amber {

namespace Web {

namespace Authorization {

class OAuth1Private
{
    Q_DISABLE_COPY(OAuth1Private)

public:
    explicit OAuth1Private() {}

    QNetworkAccessManager *m_qnam = nullptr;
    Amber::Web::Authorization::OAuth1::FlowType m_flowType = Amber::Web::Authorization::OAuth1::OAuth10aFlow;
    QString m_userAgent;
    QString m_redirectUri;
    QString m_requestTokenEndpoint;
    QString m_authorizeTokenEndpoint;
    QString m_accessTokenEndpoint;
    QString m_consumerKey;
    QString m_consumerSecret;
    QVariantMap m_customParameters;

    Amber::Web::Authorization::Error m_error;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

/*!
  \class Amber::Web::Authorization::OAuth1
  \brief Provides a helper to allow applications to integrate OAuth1 flows.
  \inmodule AmberWebAuthorization

  Applications can use an instance of this type to retrieve an access token
  from an OAuth1-enabled remote service (such as Twitter).
*/

/*!
  \inmodule AmberWebAuthorization
  \enum Amber::Web::Authorization::OAuth1::FlowType

  This enum defines the OAuth1 flow types supported by the helper.

  \value InvalidFlow An invalid or unknown OAuth1 flow
  \value OAuth10aFlow An OAuth1.0a flow
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth1::redirectParseError(const QString &errorMessage)
  \brief This signal is emitted if the helper encounters a (possibly non-fatal) error while parsing the redirect
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth1::receivedTemporaryToken(const QString &oauthToken, const QString &oauthTokenSecret)
  \brief This signal is emitted when the helper receives a temporary token from the remote service.
  \sa requestTemporaryToken()
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth1::receivedAccessToken(const QString &oauthToken, const QString &oauthTokenSecret)
  \brief This signal is emitted when the helper receives an access token from the remote service.
  \sa requestAccessToken()
*/

/*!
  \brief Constructs a new OAuth1 helper instance, with the specified QObject \a parent.
*/
Amber::Web::Authorization::OAuth1::OAuth1(QObject *parent)
    : QObject(parent)
    , d_ptr(new OAuth1Private)
{
}

/*!
  \brief Destroys the OAuth1 helper instance
*/
Amber::Web::Authorization::OAuth1::~OAuth1()
{
}

/*!
  \property Amber::Web::Authorization::OAuth1::flowType
  \brief This property holds the specific OAuth1
         \l{Amber::Web::Authorization::OAuth1::FlowType}{flow type}
         which the client application will use.

  The default (and only supported) value is \c{OAuth10a}.
*/
Amber::Web::Authorization::OAuth1::FlowType Amber::Web::Authorization::OAuth1::flowType() const
{
    Q_D(const OAuth1);
    return d->m_flowType;
}

void Amber::Web::Authorization::OAuth1::setFlowType(Amber::Web::Authorization::OAuth1::FlowType flow)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_flowType, flow, flowTypeChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::userAgent
  \brief This property holds the user agent string which should be specified in
         the request headers when performing the authorization flow.

  It is an optional property.
 */
QString Amber::Web::Authorization::OAuth1::userAgent() const
{
    Q_D(const OAuth1);
    return d->m_userAgent;
}

void Amber::Web::Authorization::OAuth1::setUserAgent(const QString &ua)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_userAgent, ua, userAgentChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::redirectUri
  \brief This property holds the redirect URI to which the system browser will
         be redirected once the authorization step of the flow is complete.

  If the client application is using a \l{RedirectListener} to listen for
  that redirect, then this property should be bound the \c{uri} property
  of the \l{RedirectListener} instance.

  Otherwise, if the client application is using some other mechanism to
  listen for redirects, it should set this property value to the appropriate
  redirect URI value (which the client application is able to handle).

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::redirectUri() const
{
    Q_D(const OAuth1);
    return d->m_redirectUri;
}

void Amber::Web::Authorization::OAuth1::setRedirectUri(const QString &uri)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_redirectUri, uri, redirectUriChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::requestTokenEndpoint
  \brief This property holds the "request token endpoint" OAuth1 parameter
         which should be used by the helper in order to request a temporary
         token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://api.twitter.com/oauth/request_token}.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::requestTokenEndpoint() const
{
    Q_D(const OAuth1);
    return d->m_requestTokenEndpoint;
}

void Amber::Web::Authorization::OAuth1::setRequestTokenEndpoint(const QString &endpoint)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_requestTokenEndpoint, endpoint, requestTokenEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::authorizeTokenEndpoint
  \brief This property holds the "authorize token endpoint" OAuth1 parameter
         which should be used by the helper when generating an authorization
         URL which will then be opened in the system browser, which allows the
         user to authorize the application.

  Once successful, the browser will be redirected to the location specified by
  the \l{redirectUri} property, with query parameters which include the
  verifier code for the temporary token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://api.twitter.com/oauth/authorize}.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::authorizeTokenEndpoint() const
{
    Q_D(const OAuth1);
    return d->m_authorizeTokenEndpoint;
}

void Amber::Web::Authorization::OAuth1::setAuthorizeTokenEndpoint(const QString &endpoint)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_authorizeTokenEndpoint, endpoint, authorizeTokenEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::accessTokenEndpoint
  \brief This property holds the "access token endpoint" OAuth1 parameter
         which should be used by the helper in order to exchange the temporary
         token (and temporary token secret) plus verifier for a valid access
         token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://api.twitter.com/oauth/access_token}.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::accessTokenEndpoint() const
{
    Q_D(const OAuth1);
    return d->m_accessTokenEndpoint;
}

void Amber::Web::Authorization::OAuth1::setAccessTokenEndpoint(const QString &endpoint)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_accessTokenEndpoint, endpoint, accessTokenEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::consumerKey
  \brief This property holds the "consumer_key" OAuth1 parameter which is
         associated with the client application.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::consumerKey() const
{
    Q_D(const OAuth1);
    return d->m_consumerKey;
}

void Amber::Web::Authorization::OAuth1::setConsumerKey(const QString &key)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_consumerKey, key, consumerKeyChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::consumerSecret
  \brief This property holds the "consumer_secret" OAuth1 parameter which is
         associated with the client application.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth1::consumerSecret() const
{
    Q_D(const OAuth1);
    return d->m_consumerSecret;
}

void Amber::Web::Authorization::OAuth1::setConsumerSecret(const QString &secret)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_consumerSecret, secret, consumerSecretChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::customParameters
  \brief This property holds the custom parameters which should be included as
         query parameters in the next request to the server.

  It is a dictionary of key/value pairs, where both the key and value must
  be strings.

  Some services allow (or sometimes, require) clients to pass non-standard
  parameters at various points in the OAuth1 flow, and this property allows
  the client to specify appropriate values for such parameters.

  It is an optional property.
*/
QVariantMap Amber::Web::Authorization::OAuth1::customParameters() const
{
    Q_D(const OAuth1);
    return d->m_customParameters;
}

void Amber::Web::Authorization::OAuth1::setCustomParameters(const QVariantMap &parameters)
{
    Q_D(OAuth1);
    BASIC_Q_PROPERTY_SETTER(d->m_customParameters, parameters, customParametersChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth1::error
  \brief This property holds information associated with the most recent
         operation error encountered by the helper.

  The possible values of the error code are described
  \l{Amber::Web::Authorization::Error}{here}.

  In general, if any error (other than \c{NoError}) occurs, then
  the flow has failed for some reason.
*/
Amber::Web::Authorization::Error Amber::Web::Authorization::OAuth1::error() const
{
    Q_D(const OAuth1);
    return d->m_error;
}

/*!
  \brief Parse the given \a redirectUri and construct a map of key/value pairs.

  Both the URI fragment and the query parameters will be parsed, and the
  key/value pairs will be inserted into the returned dictionary.

  The client can then look for the existence of appropriate entries
  (e.g. "error", "code", "access_token", etc.

  Any errors encountered during parsing are assumed to be non-fatal,
  and so while the \l{redirectParseError} signal will be emitted,
  the \l{error} will not be set.

  The client must determine whether the flow has failed,
  for example by determining whether the output contains the
  appropriate token.
*/
QVariantMap Amber::Web::Authorization::OAuth1::parseRedirectUri(const QString &redirectUri)
{
    Q_D(OAuth1);
    QString errorMessage;
    const QVariantMap data = Amber::Web::Authorization::parseRedirectUri(redirectUri, &errorMessage);
    if (!errorMessage.isEmpty()) {
        // don't emit errorChanged, as the error may not be fatal.
        emit redirectParseError(errorMessage);
    }
    return data;
}

/*!
  \brief Generates an appropriate authorization header for an OAuth10a request

  Once a client application has completed the OAuth1 authorization flow and
  received a valid OAuth1 \c{token} and \c{token_secret}, any requests it
  makes to the server which require this authorization must include an
  appropriate authorization header.

  Clients may call this method to generate an appropriate authorization header
  for the specified \a httpMethod (e.g. \c{"GET"}) on the specified resource
  \a url, given the specified \a oauthToken and \a oauthTokenSecret (and using
  the \l{consumerKey} and \l{consumerSecret} specified via properties).
*/
QString Amber::Web::Authorization::OAuth1::generateAuthorizationHeader(
        const QString &oauthToken,
        const QString &oauthTokenSecret,
        const QString &httpMethod,
        const QString &url)
{
    Q_D(OAuth1);
    QUrl origUrl(url);
    const QString queryString(origUrl.query(QUrl::FullyEncoded));
    const QUrlQuery query(queryString);
    origUrl.setQuery(QString());

    return authorizationHeader(d->m_consumerKey, d->m_consumerSecret,
                               oauthToken, oauthTokenSecret,
                               httpMethod, origUrl.toString(),
                               QString(), query.queryItems());
}

/*!
  \brief Request a temporary token from the server.

  The first step in an OAuth1 flow is to request a temporary token from
  the remote server.  After setting the appropriate properties on the
  helper, the client may call this method to initiate this request.

  On success, the \l{receivedTemporaryToken()} signal will be emitted.
  Otherwise, the \l{error} property will be set, and the \l{errorChanged()}
  signal will be emitted.
*/
void Amber::Web::Authorization::OAuth1::requestTemporaryToken()
{
    Q_D(OAuth1);
    if (d->m_requestTokenEndpoint.isEmpty()
            || d->m_consumerKey.isEmpty()
            || d->m_consumerSecret.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("requestTokenEndpoint, consumerKey, and consumerSecret are required parameters when requesting temporary token"));
        emit errorChanged();
        return;
    }

    // reset error to NoError.
    if (d->m_error.code() != Error::NoError) {
        d->m_error = Amber::Web::Authorization::Error();
        emit errorChanged();
    }

    QList<QPair<QString, QString> > queryItems;
    for (QVariantMap::const_iterator it = d->m_customParameters.constBegin();
            it != d->m_customParameters.constEnd(); ++it) {
        queryItems.append(QPair<QString, QString>(it.key(), it.value().toString()));
    }

    QUrl url(d->m_requestTokenEndpoint);
    QUrlQuery query(url);
    query.setQueryItems(queryItems);
    url.setQuery(query);
    QNetworkRequest request(url);
    if (!d->m_userAgent.isEmpty()) {
        request.setHeader(QNetworkRequest::UserAgentHeader, d->m_userAgent);
    }
    request.setRawHeader("Authorization", authorizationHeader(
            d->m_consumerKey, d->m_consumerSecret,
            QString(), QString(),
            QLatin1String("POST"),
            d->m_requestTokenEndpoint,
            d->m_redirectUri,
            queryItems).toLatin1());

    if (!d->m_qnam) {
        d->m_qnam = new QNetworkAccessManager(this);
    }

    QNetworkReply *accessTokenRequest = d->m_qnam->post(request, QByteArray());
    if (!accessTokenRequest) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::NetworkError,
                QStringLiteral("Could not request temporary token"));
        emit errorChanged();
        return;
    }

    connect(accessTokenRequest, &QNetworkReply::sslErrors,
            [this, accessTokenRequest](const QList<QSslError> &errors) {
        QStringList sslErrors;
        for (const QSslError &error : errors) {
            sslErrors.append(error.errorString());
        }
        accessTokenRequest->setProperty("sslErrors", sslErrors.join(' '));
    });

    connect(accessTokenRequest, &QNetworkReply::finished,
            [this, accessTokenRequest]() {
        accessTokenRequest->deleteLater();
        const QString sslErrors = accessTokenRequest->property("sslErrors").toString();
        if (!sslErrors.isEmpty()) {
            d_ptr->m_error = Amber::Web::Authorization::Error(
                    Amber::Web::Authorization::Error::SslError,
                    QStringLiteral("SSL error: %1").arg(sslErrors));
            emit errorChanged();
        } else if (accessTokenRequest->error() != QNetworkReply::NoError) {
            const bool hasHttpCode = accessTokenRequest->attribute(QNetworkRequest::HttpStatusCodeAttribute).isValid();
            const int httpCode = accessTokenRequest->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray replyData = accessTokenRequest->readAll();
            d_ptr->m_error = Amber::Web::Authorization::Error(
                    Amber::Web::Authorization::Error::HttpError, hasHttpCode
                        ? QStringLiteral("HTTP error: %1: %2: %3")
                                .arg(httpCode)
                                .arg(accessTokenRequest->errorString())
                                .arg(QString::fromUtf8(replyData))
                        : QStringLiteral("HTTP error: %1: %2")
                                .arg(accessTokenRequest->errorString())
                                .arg(QString::fromUtf8(replyData)));
            emit errorChanged();
        } else {
            const QByteArray replyData = accessTokenRequest->readAll();
            const QMap<QString, QString> parsed = parseTokenReplyData(replyData);
            const QString token = parsed.value(QStringLiteral("oauth_token"));
            const QString tokenSecret = parsed.value(QStringLiteral("oauth_token_secret"));
            if (token.isEmpty() || tokenSecret.isEmpty()) {
                d_ptr->m_error = Amber::Web::Authorization::Error(
                        Amber::Web::Authorization::Error::ParseError,
                        QStringLiteral("Unable to parse temporary token response: %1").arg(QString::fromUtf8(replyData)));
                emit errorChanged();
            } else {
                emit receivedTemporaryToken(token, tokenSecret);
            }
        }
    });
}

/*!
  \brief Build an authorization URL to be displayed in the system web browser.

  The second step in an OAuth1 flow is to allow the user to authorize (or
  deny authorization for) the application, which is performed via the
  system web browser.  The client application must generate an appropriate
  authorization URL (which contains parameters identifying the application
  and is signed with the temporary token requested in the first step).

  After setting the appropriate properties on the helper, the client may call
  this method to generate the URL.  This URL can then be displayed in the
  system web browser, and if the user authorizes the application accordingly,
  the web browser will be redirected to the URI specified in the
  \l{redirectUri} property, with a verifier code included as a query parameter.

  On success, this method returns a valid URL.

  Otherwise, an invalid URL is returned, and the \l{error} property will be
  set, and the \l{errorChanged()} signal will be emitted.
*/
QUrl Amber::Web::Authorization::OAuth1::generateAuthorizationUrl(
        const QString &oauthToken)
{
    Q_D(OAuth1);
    if (d->m_authorizeTokenEndpoint.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("authorizeTokenEndpoint is a required parameter when generating the authorization url"));
        emit errorChanged();
        // don't need to return here, can still return the (empty) URL with the query items.
    } else {
        // reset error to NoError.
        if (d->m_error.code() != Error::NoError) {
            d->m_error = Amber::Web::Authorization::Error();
            emit errorChanged();
        }
    }

    QUrl url(d->m_authorizeTokenEndpoint);
    QUrlQuery query(url.query());
    query.addQueryItem(QStringLiteral("oauth_token"), oauthToken);
    query.addQueryItem(QStringLiteral("oauth_callback"),d-> m_redirectUri);
    url.setQuery(query);
    return url;
}

/*!
  \brief Request an access token from the remote service.

  The third step in an OAuth1 flow is to request a full access token from the
  remote service, by providing the temporary \a oauthToken and
  \a oauthTokenSecret (received in step one) along with the \a oauthVerifier
  code (received after step two).

  Note that the verifier code is received by parsing the web browser redirect
  which results from the user authorizing the application via the system web
  browser flow.  That flow is initiated by loading the authorization URL
  (which was generated in step two) in the system web browser.

  After setting the appropriate properties on the helper, the client may call
  this method to request the access token.

  On success, this method will emit the \l{receivedAccessToken()} signal.

  Otherwise, the \l{error} property will be set, and the \l{errorChanged()}
  signal will be emitted.
*/
void Amber::Web::Authorization::OAuth1::requestAccessToken(
        const QString &oauthToken,
        const QString &oauthTokenSecret,
        const QString &oauthVerifier)
{
    Q_D(OAuth1);
    if (d->m_accessTokenEndpoint.isEmpty()
            || d->m_consumerKey.isEmpty()
            || d->m_consumerSecret.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("accessTokenEndpoint, consumerKey, and consumerSecret are required parameters when requesting temporary token"));
        emit errorChanged();
        return;
    }

    // reset error to NoError.
    if (d->m_error.code() != Error::NoError) {
        d->m_error = Amber::Web::Authorization::Error();
        emit errorChanged();
    }

    QList<QPair<QString, QString> > queryItems;
    queryItems.append(QPair<QString, QString>(QStringLiteral("oauth_verifier"),
                                              oauthVerifier));
    for (QVariantMap::const_iterator it = d->m_customParameters.constBegin();
            it != d->m_customParameters.constEnd(); ++it) {
        queryItems.append(QPair<QString, QString>(it.key(), it.value().toString()));
    }

    QUrl url(d->m_accessTokenEndpoint);
    QUrlQuery query(url);
    query.setQueryItems(queryItems);
    url.setQuery(query);
    QNetworkRequest request(url);
    if (!d->m_userAgent.isEmpty()) {
        request.setHeader(QNetworkRequest::UserAgentHeader, d->m_userAgent);
    }
    request.setRawHeader("Authorization", authorizationHeader(
            d->m_consumerKey, d->m_consumerSecret,
            oauthToken, oauthTokenSecret,
            QLatin1String("POST"),
            d->m_accessTokenEndpoint,
            d->m_redirectUri,
            queryItems).toLatin1());

    if (!d->m_qnam) {
        d->m_qnam = new QNetworkAccessManager(this);
    }

    QNetworkReply *accessTokenRequest = d->m_qnam->post(request, QByteArray());
    if (!accessTokenRequest) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::NetworkError,
                QStringLiteral("Could not request access token"));
        emit errorChanged();
        return;
    }

    connect(accessTokenRequest, &QNetworkReply::sslErrors,
            [this, accessTokenRequest](const QList<QSslError> &errors) {
        QStringList sslErrors;
        for (const QSslError &error : errors) {
            sslErrors.append(error.errorString());
        }
        accessTokenRequest->setProperty("sslErrors", sslErrors.join(' '));
    });

    connect(accessTokenRequest, &QNetworkReply::finished,
            [this, accessTokenRequest]() {
        accessTokenRequest->deleteLater();
        const QString sslErrors = accessTokenRequest->property("sslErrors").toString();
        if (!sslErrors.isEmpty()) {
            d_ptr->m_error = Amber::Web::Authorization::Error(
                    Amber::Web::Authorization::Error::SslError,
                    QStringLiteral("SSL error: %1").arg(sslErrors));
            emit errorChanged();
        } else if (accessTokenRequest->error() != QNetworkReply::NoError) {
            const bool hasHttpCode = accessTokenRequest->attribute(QNetworkRequest::HttpStatusCodeAttribute).isValid();
            const int httpCode = accessTokenRequest->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray replyData = accessTokenRequest->readAll();
            d_ptr->m_error = Amber::Web::Authorization::Error(
                    Amber::Web::Authorization::Error::HttpError, hasHttpCode
                    ? QStringLiteral("HTTP error: %1: %2: %3")
                            .arg(httpCode)
                            .arg(accessTokenRequest->errorString())
                            .arg(QString::fromUtf8(replyData))
                    : QStringLiteral("HTTP error: %1: %2")
                            .arg(accessTokenRequest->errorString())
                            .arg(QString::fromUtf8(replyData)));
            emit errorChanged();
        } else {
            const QByteArray replyData = accessTokenRequest->readAll();
            const QMap<QString, QString> parsed = parseTokenReplyData(replyData);
            const QString token = parsed.value(QStringLiteral("oauth_token"));
            const QString tokenSecret = parsed.value(QStringLiteral("oauth_token_secret"));
            if (token.isEmpty() || tokenSecret.isEmpty()) {
                d_ptr->m_error = Amber::Web::Authorization::Error(
                        Amber::Web::Authorization::Error::ParseError,
                        QStringLiteral("Unable to parse temporary token response: %1").arg(QString::fromUtf8(replyData)));
                emit errorChanged();
            } else {
                emit receivedAccessToken(token, tokenSecret);
            }
        }
    });
}

// This function taken from http://qt-project.org/wiki/HMAC-SHA1 which is in the public domain
// and carries no licensing requirements (as at 2013-05-09)
QString Amber::Web::Authorization::OAuth1::hmacSha1(
        const QString &signingKey,
        const QString &baseString)
{
    QByteArray key = signingKey.toLatin1();
    QByteArray baseArray = baseString.toLatin1();

    int blockSize = 64; // HMAC-SHA-1 block size, defined in SHA-1 standard
    if (key.length() > blockSize) { // if key is longer than block size (64), reduce key length with SHA-1 compression
        key = QCryptographicHash::hash(key, QCryptographicHash::Sha1);
    }

    QByteArray innerPadding(blockSize, char(0x36)); // initialize inner padding with char "6"
    QByteArray outerPadding(blockSize, char(0x5c)); // initialize outer padding with char "\"
    // ascii characters 0x36 ("6") and 0x5c ("\") are selected because they have large
    // Hamming distance (http://en.wikipedia.org/wiki/Hamming_distance)

    for (int i = 0; i < key.length(); i++) {
        innerPadding[i] = innerPadding[i] ^ key.at(i); // XOR operation between every byte in key and innerpadding, of key length
        outerPadding[i] = outerPadding[i] ^ key.at(i); // XOR operation between every byte in key and outerpadding, of key length
    }

    // result = hash ( outerPadding CONCAT hash ( innerPadding CONCAT baseArray ) ).toBase64
    QByteArray total = outerPadding;
    QByteArray part = innerPadding;
    part.append(baseArray);
    total.append(QCryptographicHash::hash(part, QCryptographicHash::Sha1));
    QByteArray hashed = QCryptographicHash::hash(total, QCryptographicHash::Sha1);
    return hashed.toBase64();
}

QString Amber::Web::Authorization::OAuth1::authorizationHeader(
        const QString &consumerKey, const QString &consumerSecret,
        const QString &oauthToken, const QString &oauthTokenSecret,
        const QString &requestMethod, const QString &requestUrl,
        const QString &redirectUri, const QList<QPair<QString, QString> > &parameters)
{
    // Twitter requires all requests to be signed with an authorization header.
    // First, construct a list of required authorization header parameters
    QList<QPair<QString, QString> > authParams;
    authParams.append(qMakePair(QStringLiteral("oauth_nonce"),
                                QString::fromLatin1(QUuid::createUuid().toByteArray().toBase64(QByteArray::Base64UrlEncoding))));
    if (!redirectUri.isEmpty()) {
        authParams.append(qMakePair(QStringLiteral("oauth_callback"),
                                    redirectUri));
    }
    authParams.append(qMakePair(QStringLiteral("oauth_signature_method"),
                                QStringLiteral("HMAC-SHA1")));
    authParams.append(qMakePair(QStringLiteral("oauth_timestamp"),
                                QString::number(qFloor(QDateTime::currentMSecsSinceEpoch() / 1000.0))));
    authParams.append(qMakePair(QStringLiteral("oauth_version"),
                                QStringLiteral("1.0")));
    authParams.append(qMakePair(QStringLiteral("oauth_consumer_key"),
                                consumerKey));
    if (!oauthToken.isEmpty()) {
        authParams.append(qMakePair(QStringLiteral("oauth_token"),
                                    oauthToken));
    }

    // then ensure that they are sorted alphabetically, and URL-encoded
    QMap<QString, QString> encodedAuthParams;
    for (int i = 0; i < authParams.size(); ++i) {
        QPair<QString, QString> param = authParams.at(i);
        encodedAuthParams.insert(QUrl::toPercentEncoding(param.first),
                                 QUrl::toPercentEncoding(param.second));
    }

    // now build up a separate map which includes other request parameters
    QMap<QString, QString> encodedParams = encodedAuthParams;
    for (int i = 0; i < parameters.size(); ++i) {
        QPair<QString, QString> param = parameters.at(i);
        encodedParams.insert(QUrl::toPercentEncoding(param.first),
                             QUrl::toPercentEncoding(param.second));
    }

    // now construct the oauth signature base string
    QString parametersString;
    QStringList keys = encodedParams.keys();
    for (int i = 0; i < keys.size(); ++i) {
        parametersString += (i > 0 ? QLatin1String("&") : QString())
                         + keys[i] + QLatin1String("=") + encodedParams.value(keys[i]);
    }

    const QString signatureBaseString = requestMethod.toUpper() + QLatin1String("&")
                                      + QUrl::toPercentEncoding(requestUrl) + QLatin1String("&")
                                      + QUrl::toPercentEncoding(parametersString);

    // and the oauth signature signing key
    const QString signingKey = QUrl::toPercentEncoding(consumerSecret) + QLatin1String("&")
                             + QUrl::toPercentEncoding(oauthTokenSecret);

    // and use the HMAC-SHA1 signing method to generate the oauth signature
    const QString oauthSignature = hmacSha1(signingKey, signatureBaseString);
    encodedAuthParams.insert(QUrl::toPercentEncoding(QStringLiteral("oauth_signature")),
                             QUrl::toPercentEncoding(oauthSignature));

    // now generate the Authorization header from the encoded auth parameters map.
    QString authHeader = QLatin1String("OAuth ");
    keys = encodedAuthParams.keys();
    for (int i = 0; i < keys.size(); ++i) {
        authHeader += (i > 0 ? QLatin1String(", ") : QString())
                   + keys[i] + QLatin1String("=\"") + encodedAuthParams.value(keys[i]) + QLatin1String("\"");
    }
    return authHeader;
}

