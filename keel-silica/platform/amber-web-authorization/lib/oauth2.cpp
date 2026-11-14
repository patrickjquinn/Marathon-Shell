// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#include "oauth2.h"
#include "redirecturiparser_p.h"

#include <QtCore/QUuid>
#include <QtCore/QCryptographicHash>
#include <QtCore/QByteArray>
#include <QtCore/QUrlQuery>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonValue>

#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QNetworkReply>

#define BASIC_Q_PROPERTY_SETTER(member, argument, changeSignal) \
        do {                          \
            if (member != argument) { \
                member = argument;    \
                emit changeSignal();  \
            }                         \
        } while (0)

namespace {
    QJsonObject parseJsonObjectReplyData(const QByteArray &replyData, bool *ok)
    {
        QJsonDocument jsonDocument = QJsonDocument::fromJson(replyData);
        *ok = !jsonDocument.isEmpty();
        if (*ok && jsonDocument.isObject()) {
            return jsonDocument.object();
        }
        *ok = false;
        return QJsonObject();
    }
}

namespace Amber {

namespace Web {

namespace Authorization {

class OAuth2Private
{
    Q_DISABLE_COPY(OAuth2Private)

public:
    explicit OAuth2Private() {}

    QNetworkAccessManager *m_qnam = nullptr;
    QNetworkReply *m_currentRequest = nullptr;
    Amber::Web::Authorization::OAuth2::FlowType m_flowType = Amber::Web::Authorization::OAuth2::AuthorizationCodeWithPkceFlow;
    QString m_userAgent;
    QString m_redirectUri;
    QString m_authorizationEndpoint;
    QString m_tokenEndpoint;
    QString m_refreshEndpoint;
    QString m_clientId;
    QString m_clientSecret;
    QString m_scope;
    QString m_state;
    QString m_codeVerifier;
    QString m_codeChallenge;
    QString m_codeChallengeMethod = QStringLiteral("S256");
    QVariantMap m_customParameters;
    QList<QSslError> m_ignorableSslErrors;

    Amber::Web::Authorization::Error m_error;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

/*!
  \class Amber::Web::Authorization::OAuth2
  \brief Provides a helper to allow applications to integrate OAuth2 flows.
  \inmodule AmberWebAuthorization

  Applications can use an instance of this type to retrieve an access token
  from an OAuth2-enabled remote service (such as Google).

  Note: QML applications will most likely use one of the flow-specific helper
  types (e.g. \c{OAuth2AcPkce}) rather than using this type directly, so this
  class is mostly of interest to C++ applications or applications which make
  use of an unusual OAuth2 flow.

  \sa amberwebauthcppexample, amberwebauthqmlexample
*/

/*!
  \inmodule AmberWebAuthorization
  \enum Amber::Web::Authorization::OAuth2::FlowType

  This enum defines the OAuth2 flow types supported by the helper.

  Most client applications should use the \c{AuthorizationCodeWithPkceFlow} type,
  as it does not require the user to trust the application (as the authorization
  step is done via the system web browser).

  \value InvalidFlow An invalid or unknown OAuth2 flow
  \value ImplicitFlow A legacy OAuth2 flow (deprecated, should not be used by new clients)
  \value ClientCredentialsFlow A machine-to-machine grant, where the requester is the resource owner
  \value AuthorizationCodeFlow For web-apps running on a trusted web-server
  \value AuthorizationCodeWithPkceFlow For most apps running on a device
  \value ResourceOwnerPasswordFlow For trusted client apps, where the user provides the app their credentials
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth2::redirectParseError(const QString &errorMessage)
  \brief This signal is emitted if the helper encounters a (possibly non-fatal) error while parsing the redirect
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth2::sslErrors(const QList<QSslError> &errors)
  \brief This signal is emitted when the helper encounters SSL errors when performing a request.

  The application may wish to show the errors to the user, to provide them the
  opportunity to allow the operation to continue, if they know that the errors
  are insignificant.  In that case, the application can set the
  \l{ignorableSslErrors} property to the given \a errors and then retry the
  operation.

  \sa ignorableSslErrors()
*/

/*!
  \inmodule AmberWebAuthorization
  \fn void Amber::Web::Authorization::OAuth2::receivedAccessToken(const QVariantMap &token)
  \brief This signal is emitted when the helper receives an access token from the remote service.

  The \a token will be a dictionary of key/value pairs which should include the
  \c{"access_token"} but may also include other values, including \c{"expires_in"}
  and \c{"refresh_token"} depending on the flow used.

  \sa requestAccessToken()
*/

/*!
  \brief Constructs a new OAuth2 helper instance, with the specified QObject \a parent.
*/
Amber::Web::Authorization::OAuth2::OAuth2(QObject *parent)
    : QObject(parent)
    , d_ptr(new OAuth2Private)
{
}

/*!
  \brief Destroys the OAuth2 helper instance
*/
Amber::Web::Authorization::OAuth2::~OAuth2()
{
}

/*!
  \property Amber::Web::Authorization::OAuth2::flowType
  \brief This property holds the specific OAuth2
         \l{Amber::Web::Authorization::OAuth2::FlowType}{flow type}
         which the client application will use.

  Most clients should use the \c{AuthorizationCodeWithPkceFlow} type.
*/
Amber::Web::Authorization::OAuth2::FlowType Amber::Web::Authorization::OAuth2::flowType() const
{
    Q_D(const OAuth2);
    return d->m_flowType;
}

void Amber::Web::Authorization::OAuth2::setFlowType(FlowType flow)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_flowType, flow, flowTypeChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::userAgent
  \brief This property holds the user agent string which should be specified in
         the request headers when performing the authorization flow.

  It is an optional property.
 */
QString Amber::Web::Authorization::OAuth2::userAgent() const
{
    Q_D(const OAuth2);
    return d->m_userAgent;
}

void Amber::Web::Authorization::OAuth2::setUserAgent(const QString &ua)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_userAgent, ua, userAgentChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::redirectUri
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
QString Amber::Web::Authorization::OAuth2::redirectUri() const
{
    Q_D(const OAuth2);
    return d->m_redirectUri;
}

void Amber::Web::Authorization::OAuth2::setRedirectUri(const QString &uri)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_redirectUri, uri, redirectUriChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::authorizationEndpoint
  \brief This property holds the "authorization endpoint" OAuth2 parameter
         which should be used by the helper when generating an authorization
         URL which will then be opened in the system browser, which allows the
         user to authorize the application.

  Once successful, the browser will be redirected to the location specified by
  the \l{redirectUri} property, with query parameters which include the
  verifier code for the temporary token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://accounts.google.com/o/oauth2/auth}.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth2::authorizationEndpoint() const
{
    Q_D(const OAuth2);
    return d->m_authorizationEndpoint;
}

void Amber::Web::Authorization::OAuth2::setAuthorizationEndpoint(const QString &endpoint)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_authorizationEndpoint, endpoint, authorizationEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::tokenEndpoint
  \brief This property holds the "token endpoint" OAuth2 parameter
         which should be used by the helper in order to request an
         access token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://accounts.google.com/o/oauth2/token}.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth2::tokenEndpoint() const
{
    Q_D(const OAuth2);
    return d->m_tokenEndpoint;
}

void Amber::Web::Authorization::OAuth2::setTokenEndpoint(const QString &endpoint)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_tokenEndpoint, endpoint, tokenEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::refreshEndpoint
  \brief This property holds the "refresh endpoint" OAuth2 parameter
         which should be used by the helper in order to request a
         refreshed access token given a valid refresh token.

  It must be a full, valid URL which is specified by the remote service,
  e.g. \c{https://accounts.google.com/o/oauth2/token}.

  If no value is specified for this property, the helper will attempt
  to use the \c{tokenEndpoint} as the refresh endpoint.

  Most clients will never need to set this property, as by default
  the refresh endpoint should be identical to the token endpoint.
  Clients will only need to set this property if the service with
  which they interact does not conform to the OAuth2 specification.

  It is an optional property.
*/
QString Amber::Web::Authorization::OAuth2::refreshEndpoint() const
{
    Q_D(const OAuth2);
    return d->m_refreshEndpoint;
}

void Amber::Web::Authorization::OAuth2::setRefreshEndpoint(const QString &endpoint)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_refreshEndpoint, endpoint, refreshEndpointChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::clientId
  \brief This property holds the "client_id" OAuth2 parameter which is
         associated with the client application.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth2::clientId() const
{
    Q_D(const OAuth2);
    return d->m_clientId;
}

void Amber::Web::Authorization::OAuth2::setClientId(const QString &clientId)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_clientId, clientId, clientIdChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::clientSecret
  \brief This property holds the "client_secret" OAuth2 parameter which is
         associated with the client application.

  It is a mandatory property.
*/
QString Amber::Web::Authorization::OAuth2::clientSecret() const
{
    Q_D(const OAuth2);
    return d->m_clientSecret;
}

void Amber::Web::Authorization::OAuth2::setClientSecret(const QString &clientSecret)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_clientSecret, clientSecret, clientSecretChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::scope
  \brief This property holds the "scope" OAuth2 parameter which defines the
         types of resources or operations to which the application is
         requesting access.

  Different services may require this to be formatted in different ways,
  e.g. with different separators, if the scope is a list of values.

  It is a mandatory property.

  \sa generateScope()
*/
QString Amber::Web::Authorization::OAuth2::scope() const
{
    Q_D(const OAuth2);
    return d->m_scope;
}

void Amber::Web::Authorization::OAuth2::setScope(const QString &scope)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_scope, scope, scopeChanged);
}

/*!
  \brief Sets the \l{scope} property value to a string generated
         by joining the given list of \a scopes with the given \a separator
 */
void Amber::Web::Authorization::OAuth2::setScope(const QStringList &scopes, const QString &separator)
{
    setScope(scopes.join(separator));
}

/*!
  \property Amber::Web::Authorization::OAuth2::state
  \brief This property holds the "state" OAuth2 parameter which helps
         to prevent certain types of integrity attacks during the
         authorization process.

  It should contain a cryptographically random string, and
  clients should generally set this property to the value
  returned by \l{generateState()}.

  It is an optional property.

  \sa generateState()
*/
QString Amber::Web::Authorization::OAuth2::state() const
{
    Q_D(const OAuth2);
    return d->m_state;
}

void Amber::Web::Authorization::OAuth2::setState(const QString &state)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_state, state, stateChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::codeVerifier
  \brief This property holds the "verifier" OAuth2 parameter which is
         required for \c{AuthorizationCodeWithPkceFlow} type flows.

  It should contain a cryptographically random string, and
  clients should generally set this property to the value
  returned by \l{generateCodeVerifier()}.

  It is a mandatory property for \c{AuthorizationCodeWithPkceFlow} flows.

  \sa generateCodeVerifier()
*/
QString Amber::Web::Authorization::OAuth2::codeVerifier() const
{
    Q_D(const OAuth2);
    return d->m_codeVerifier;
}

void Amber::Web::Authorization::OAuth2::setCodeVerifier(const QString &verifier)
{
    Q_D(OAuth2);
    if (d->m_codeVerifier != verifier) {
        d->m_codeVerifier = verifier;
        d->m_codeChallenge = QString::fromLatin1(
                QCryptographicHash::hash(
                        verifier.toUtf8(),
                        QCryptographicHash::Sha256).toBase64(
                                QByteArray::Base64UrlEncoding
                              | QByteArray::OmitTrailingEquals));
        emit codeVerifierChanged();
        emit codeChallengeChanged();
    }
}

/*!
  \property Amber::Web::Authorization::OAuth2::codeChallenge
  \brief This property holds the "code_challenge" OAuth2 parameter which is
         sent to the remote server for \c{AuthorizationCodeWithPkceFlow} type
         flows.

  The \c{codeChallenge} value is automatically generated (via secure hash)
  from the \c{codeVerifier} specified by the client.

  Clients generally do not need to care about this value themselves, as the
  helper will generate and send it as appropriate during the flow.

  \sa codeVerifier()
*/
QString Amber::Web::Authorization::OAuth2::codeChallenge() const
{
    Q_D(const OAuth2);
    return d->m_codeChallenge;
}

/*!
  \property Amber::Web::Authorization::OAuth2::codeChallengeMethod
  \brief This property holds the "code_challenge_method" OAuth2 parameter
         which is sent to the remote server for
         \c{AuthorizationCodeWithPkceFlow} type flows.

  The \c{codeChallengeMethod} value is always \c{"S256"} currently as that
  is the only hashing method which the helper currently supports.

  Clients generally do not need to care about this value themselves, as the
  helper will generate and send it as appropriate during the flow.

  \sa codeChallenge()
*/
QString Amber::Web::Authorization::OAuth2::codeChallengeMethod() const
{
    Q_D(const OAuth2);
    return d->m_codeChallengeMethod;
}

/*!
  \property Amber::Web::Authorization::OAuth2::customParameters
  \brief This property holds the custom parameters which should be included as
         query parameters in the next request to the server.

  It is a dictionary of key/value pairs, where both the key and value must
  be strings.

  Some services allow (or sometimes, require) clients to pass non-standard
  parameters at various points in the OAuth2 flow, and this property allows
  the client to specify appropriate values for such parameters.

  It is an optional property.
*/
QVariantMap Amber::Web::Authorization::OAuth2::customParameters() const
{
    Q_D(const OAuth2);
    return d->m_customParameters;
}

void Amber::Web::Authorization::OAuth2::setCustomParameters(const QVariantMap &parameters)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_customParameters, parameters, customParametersChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::networkAccessManager
  \brief This property holds the network access manager instance which will
         be used when performing requests to the server.

  If the client does not provide a specific network access manager to use,
  a default-constructed network access manager will be creating when performing
  the first request, and set as the value of this property.

  Most clients will not usually need to provide a network access manager,
  but it might be useful if custom headers need to be provided to the
  remote service during requests.

  If the client provides the network access manager, it retains ownership
  of it, and must delete it after the OAuth2 instance is deleted (or set
  its QObject parent to be the OAuth2 instance) to avoid leaking memory.

  It is an optional property.
*/
QNetworkAccessManager* Amber::Web::Authorization::OAuth2::networkAccessManager() const
{
    Q_D(const OAuth2);
    return d->m_qnam;
}

void Amber::Web::Authorization::OAuth2::setNetworkAccessManager(QNetworkAccessManager *manager)
{
    Q_D(OAuth2);

    if (d->m_qnam == manager) {
        return;
    }

    if (d->m_qnam) {
        d->m_qnam->deleteLater();
    }

    d->m_qnam = manager;
    emit networkAccessManagerChanged();
}

/*!
  \property Amber::Web::Authorization::OAuth2::ignorableSslErrors
  \brief This property holds the SSL errors which should be ignored
         if encountered in the next request to the server.

  If a request fails due to an SSL error, the user can be shown the
  errors and given the opportunity to allow the operation to continue
  (e.g. if they know that the server is safe, despite using a
  self-signed certificate, etc).  If the user allows it, the application
  can then set this property to contain the errors which were encountered,
  and then retry the request (which should then succeed, as it will
  ignore the specified errors).  Note that the application should then
  set this property to an empty list value, to avoid accidentally ignoring
  future errors.

  This property is difficult to use properly from a QML context, as the
  \c{QSslError} type is opaque to QML; as such, this property is mostly
  useful for C++ clients.

  It is an optional property.

  \sa sslErrors()
*/
QList<QSslError> Amber::Web::Authorization::OAuth2::ignorableSslErrors() const
{
    Q_D(const OAuth2);
    return d->m_ignorableSslErrors;
}

void Amber::Web::Authorization::OAuth2::setIgnorableSslErrors(const QList<QSslError> &errors)
{
    Q_D(OAuth2);
    BASIC_Q_PROPERTY_SETTER(d->m_ignorableSslErrors, errors, ignorableSslErrorsChanged);
}

/*!
  \property Amber::Web::Authorization::OAuth2::error
  \brief This property holds information associated with the most recent
         operation error encountered by the helper.

  The possible values of the error code are described
  \l{Amber::Web::Authorization::Error}{here}.

  In general, if any error (other than \c{NoError}) occurs, then
  the flow has failed for some reason.
*/
Amber::Web::Authorization::Error Amber::Web::Authorization::OAuth2::error() const
{
    Q_D(const OAuth2);
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
QVariantMap Amber::Web::Authorization::OAuth2::parseRedirectUri(const QString &redirectUri)
{
    Q_D(OAuth2);
    QString errorMessage;
    const QVariantMap data = Amber::Web::Authorization::parseRedirectUri(redirectUri, &errorMessage);
    if (!errorMessage.isEmpty()) {
        // don't emit errorChanged, as the error may not be fatal.
        emit redirectParseError(errorMessage);
    }
    return data;
}

/*!
  \brief Joins the specified \a scopes with the specified \a separator and returns the result as a valid \c{scope} string
*/
QString Amber::Web::Authorization::OAuth2::generateScope(
        const QStringList &scopes,
        const QString &separator) const
{
    return scopes.join(separator);
}

/*!
  \brief Generates cryptographically-secure random data for use as the \c{state} property value
*/
QString Amber::Web::Authorization::OAuth2::generateState() const
{
    return QString::fromLatin1(
            QCryptographicHash::hash(
                    QUuid::createUuid().toByteArray(),
                    QCryptographicHash::Sha256).toBase64(
                            QByteArray::Base64UrlEncoding
                          | QByteArray::OmitTrailingEquals));
}

/*!
  \brief Generates cryptographically-secure random data for use as the \c{codeVerifier} property value
*/
QString Amber::Web::Authorization::OAuth2::generateCodeVerifier() const
{
    return QString::fromLatin1(
            QCryptographicHash::hash(
                    QUuid::createUuid().toByteArray(),
                    QCryptographicHash::Sha512).toBase64(
                            QByteArray::Base64UrlEncoding
                          | QByteArray::OmitTrailingEquals));
}

/*!
  \brief Build an authorization URL to be displayed in the system web browser.

  The first step in an \c{ImplicitFlow}, \c{AuthorizationCodeFlow}, or
  \c{AuthorizationCodeWithPkceFlow} is to allow the user to authorize (or
  deny authorization for) the application, which is performed via the
  system web browser.  The client application must generate an appropriate
  authorization URL (which contains parameters identifying the application
  and the scope of access being requested).

  After setting the appropriate properties on the helper, the client may call
  this method to generate the URL.  This URL can then be displayed in the
  system web browser, and if the user authorizes the application accordingly,
  the web browser will be redirected to the URI specified in the
  \l{redirectUri} property, with a verifier code included as a query parameter.

  On success, this method returns a valid URL.

  Otherwise, an invalid URL is returned, and the \l{error} property will be
  set, and the \l{errorChanged()} signal will be emitted.
*/
QUrl Amber::Web::Authorization::OAuth2::generateAuthorizationUrl()
{
    Q_D(OAuth2);
    if (d->m_flowType != ImplicitFlow
            && d->m_flowType != AuthorizationCodeFlow
            && d->m_flowType != AuthorizationCodeWithPkceFlow) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidOperationError,
                QStringLiteral("Can only generate authorization URL for implicit or authorization code flows"));
        emit errorChanged();
        return QUrl();
    }

    if (d->m_authorizationEndpoint.isEmpty()
            || d->m_clientId.isEmpty()
            || d->m_redirectUri.isEmpty()
            || d->m_scope.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("authorizationEndpoint, clientId, redirectUri, and scope are required parameters"));
        emit errorChanged();
        return QUrl();
    } else if (d->m_flowType == AuthorizationCodeWithPkceFlow
            && d->m_codeChallenge.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("codeVerifier is a required parameter for authorization_code_pkce flow"));
        emit errorChanged();
        return QUrl();
    }

    // reset error to NoError.
    if (d->m_error.code() != Error::NoError) {
        d->m_error = Amber::Web::Authorization::Error();
        emit errorChanged();
    }

    QUrlQuery query;
    query.addQueryItem("client_id", d->m_clientId);
    query.addQueryItem("redirect_uri", d->m_redirectUri);
    query.addQueryItem("scope", d->m_scope);
    if (!d->m_state.isEmpty()) {
        query.addQueryItem("state", d->m_state);
    }

    switch (d->m_flowType) {
        case AuthorizationCodeFlow: {
            query.addQueryItem("response_type", "code");
            break;
        }
        case AuthorizationCodeWithPkceFlow: {
            query.addQueryItem("response_type", "code");
            query.addQueryItem("code_challenge", d->m_codeChallenge);
            query.addQueryItem("code_challenge_method", d->m_codeChallengeMethod);
            break;
        }
        default: { // ImplicitFlow
            query.addQueryItem("response_type", "token");
            break;
        }
    }

    for (QVariantMap::const_iterator it = d->m_customParameters.constBegin();
            it != d->m_customParameters.constEnd(); ++it) {
        query.addQueryItem(it.key(), it.value().toString());
    }

    QUrl url(d->m_authorizationEndpoint);
    url.setQuery(query);
    return url;
}

/*!
  \brief Request an access token from the server.

  The second step in an \c{ImplicitFlow}, \c{AuthorizationCodeFlow}, or
  \c{AuthorizationCodeWithPkceFlow}, and the first step in a
  \c{ClientCredentialsFlow} or \c{ResourceOwnerPassword} flow, is to
  request an access token from the remote server.

  For the former cases, a bearer \a code (received from the server via a
  captured redirect from the system web browser) must be provided (and
  a \a state value which is similarly received may optionally also be
  provided and can be checked to protect against some types of attacks).

  For the latter two flow types, these parameters are ignored.

  On success, the \l{receivedAccessToken()} signal will be emitted.
  Otherwise, the \l{error} property will be set, and the \l{errorChanged()}
  signal will be emitted.
*/
void Amber::Web::Authorization::OAuth2::requestAccessToken(const QString &code, const QString &state)
{
    Q_D(OAuth2);
    if (d->m_flowType != ClientCredentialsFlow
            && d->m_flowType != AuthorizationCodeFlow
            && d->m_flowType != AuthorizationCodeWithPkceFlow
            && d->m_flowType != ResourceOwnerPasswordFlow) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidOperationError,
                QStringLiteral("Cannot request access token directly in implicit flow"));
        emit errorChanged();
        return;
    }

    if (d->m_tokenEndpoint.isEmpty() || d->m_clientId.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("tokenEndpoint and clientId are required parameters"));
        emit errorChanged();
        return;
    } else if (d->m_flowType == ClientCredentialsFlow
            && d->m_clientSecret.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("clientSecret is a required parameter for client_credentials flow"));
        emit errorChanged();
        return;
    } else if (d->m_flowType == AuthorizationCodeFlow
            && (d->m_redirectUri.isEmpty() || d->m_clientSecret.isEmpty())) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("redirectUri and clientSecret are required parameters for authorization_code flow"));
        emit errorChanged();
        return;
    } else if (d->m_flowType == AuthorizationCodeWithPkceFlow
            && (d->m_redirectUri.isEmpty() || d->m_codeVerifier.isEmpty())) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("redirectUri and codeVerifier are required parameters for authorization_code_pkce flow"));
        emit errorChanged();
        return;
    } else if (d->m_flowType == ResourceOwnerPasswordFlow
            && (!d->m_customParameters.contains("username") || !d->m_customParameters.contains("password"))) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("username and password are required custom parameters for password flow"));
        emit errorChanged();
        return;
    }

    if (state != d->m_state) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::StateMismatchError,
                QStringLiteral("The state data received from the server doesn't match the expected state"));
        emit errorChanged();
        return;
    }

    // reset error to NoError.
    if (d->m_error.code() != Error::NoError) {
        d->m_error = Amber::Web::Authorization::Error();
        emit errorChanged();
    }

    QUrlQuery query;
    query.addQueryItem("client_id", d->m_clientId);

    switch (d->m_flowType) {
        case ClientCredentialsFlow: {
            query.addQueryItem("grant_type", "client_credentials");
            query.addQueryItem("client_secret", d->m_clientSecret);
            break;
        }
        case AuthorizationCodeFlow: {
            query.addQueryItem("grant_type", "authorization_code");
            query.addQueryItem("redirect_uri", d->m_redirectUri);
            query.addQueryItem("code", code);
            query.addQueryItem("client_secret", d->m_clientSecret);
            break;
        }
        case AuthorizationCodeWithPkceFlow: {
            query.addQueryItem("grant_type", "authorization_code");
            query.addQueryItem("redirect_uri", d->m_redirectUri);
            query.addQueryItem("code", code);
            query.addQueryItem("code_verifier", d->m_codeVerifier);
            if (!d->m_clientSecret.isEmpty()) {
                // some services, such as Google (when using Native App type)
                // require the client secret...
                query.addQueryItem("client_secret", d->m_clientSecret);
            }
            break;
        }
        default: { // ResourceOwnerPasswordFlow
            query.addQueryItem("grant_type", "password");
            // username and password should be passed in customParameters.
            break;
        }
    }

    for (QVariantMap::const_iterator it = d->m_customParameters.constBegin();
            it != d->m_customParameters.constEnd(); ++it) {
        query.addQueryItem(it.key(), it.value().toString());
    }

    performAccessTokenRequest(query);
}

/*!
  \brief Request a refreshed access token from the server

  If the client application has received a refresh token from the server,
  it can request a refreshed access token periodically without requiring
  further user interaction.

  This method allows the client application to trigger such a request with
  the remote server, by providing the previously returned \a refreshToken.

  The request will be directed to the \l{refreshEndpoint} if a value has
  been specified for that property, otherwise the \l{tokenEndpoint} will
  be used instead.

  On success, the \l{receivedAccessToken()} signal will be emitted.
  Otherwise, the \l{error} property will be set, and the \l{errorChanged()}
  signal will be emitted.
*/
void Amber::Web::Authorization::OAuth2::refreshAccessToken(const QString &refreshToken)
{
    Q_D(OAuth2);
    if (d->m_flowType != AuthorizationCodeFlow
            && d->m_flowType != AuthorizationCodeWithPkceFlow) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidOperationError,
                QStringLiteral("Can only refresh access tokens received via authorization_code flow"));
        emit errorChanged();
        return;
    }

    if ((d->m_refreshEndpoint.isEmpty() && d->m_tokenEndpoint.isEmpty())
            || d->m_clientId.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("tokenEndpoint and clientId are required parameters for refresh_token flow"));
        emit errorChanged();
        return;
    }

    if (d->m_flowType == AuthorizationCodeFlow
            && d->m_clientSecret.isEmpty()) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::InvalidParametersError,
                QStringLiteral("clientSecret is a required parameter for refresh_token flow without PKCE"));
        emit errorChanged();
        return;
    }

    // reset error to NoError.
    if (d->m_error.code() != Error::NoError) {
        d->m_error = Amber::Web::Authorization::Error();
        emit errorChanged();
    }

    QUrlQuery query;
    query.addQueryItem("grant_type", "refresh_token");
    query.addQueryItem("refresh_token", refreshToken);
    query.addQueryItem("client_id", d->m_clientId);
    if (!d->m_clientSecret.isEmpty()) {
        // some services, such as Google (when using Native App type)
        // require the client secret in PKCE flow...
        query.addQueryItem("client_secret", d->m_clientSecret);
    }

    performAccessTokenRequest(query);
}

/*!
  \brief Aborts the current ongoing network request, if possible.

  Returns true if there is a current ongoing network request which
  was able to be aborted, otherwise returns false.
*/
bool Amber::Web::Authorization::OAuth2::abortCurrentRequest()
{
    Q_D(OAuth2);

    if (d->m_currentRequest) {
        d->m_currentRequest->abort();
        return true;
    }

    return false;
}

void Amber::Web::Authorization::OAuth2::performAccessTokenRequest(const QUrlQuery &query)
{
    Q_D(OAuth2);
    const QString endpoint = (query.hasQueryItem("refresh_token") && !d->m_refreshEndpoint.isEmpty())
                           ? d->m_refreshEndpoint : d->m_tokenEndpoint;
    QUrl url(endpoint);
    url.setQuery(query);
    const QByteArray postData = url.query(QUrl::FullyEncoded).toUtf8();
    const QUrl tokenUrl(endpoint);
    QNetworkRequest request(tokenUrl);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    request.setHeader(QNetworkRequest::ContentLengthHeader, postData.size());
    if (!d->m_userAgent.isEmpty()) {
        request.setHeader(QNetworkRequest::UserAgentHeader, d->m_userAgent);
    }

    if (!d->m_qnam) {
        setNetworkAccessManager(new QNetworkAccessManager(this));
    }

    QNetworkReply *accessTokenRequest = d->m_qnam->post(request, postData);
    if (!accessTokenRequest) {
        d->m_error = Amber::Web::Authorization::Error(
                Amber::Web::Authorization::Error::NetworkError,
                QStringLiteral("Could not request access token"));
        emit errorChanged();
        return;
    }

    if (!d->m_ignorableSslErrors.isEmpty()) {
        accessTokenRequest->ignoreSslErrors(d->m_ignorableSslErrors);
    }

    connect(accessTokenRequest, &QNetworkReply::sslErrors,
            [this, accessTokenRequest](const QList<QSslError> &errors) {
        QStringList sslErrors;
        for (const QSslError &error : errors) {
            sslErrors.append(error.errorString());
        }
        accessTokenRequest->setProperty("sslErrors", sslErrors.join(' '));
        emit this->sslErrors(errors);
    });

    connect(accessTokenRequest, &QNetworkReply::finished,
            [this, accessTokenRequest]() {
        accessTokenRequest->deleteLater();
        if (d_ptr->m_currentRequest == accessTokenRequest) {
            // note: might be different if the client started a new request
            // on receiving sslErrors() but prior to finished().
            d_ptr->m_currentRequest = nullptr;
        }
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
            bool ok = false;
            const QByteArray replyData = accessTokenRequest->readAll();
            const QJsonObject obj = parseJsonObjectReplyData(replyData, &ok);
            if (!ok) {
                d_ptr->m_error = Amber::Web::Authorization::Error(
                        Amber::Web::Authorization::Error::ParseError,
                        QStringLiteral("Unable to parse access token response: %1").arg(QString::fromUtf8(replyData)));
                emit errorChanged();
            } else {
                emit receivedAccessToken(obj.toVariantMap());
            }
        }
    });

    d->m_currentRequest = accessTokenRequest;
}

