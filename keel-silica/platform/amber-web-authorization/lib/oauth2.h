// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#ifndef AMBER_WEB_AUTHORIZATION_OAUTH2_H
#define AMBER_WEB_AUTHORIZATION_OAUTH2_H

#include "oauthsymbols.h"
#include "oautherror.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QVariantMap>
#include <QtCore/QStringList>
#include <QtCore/QString>
#include <QtCore/QUrl>

#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QSslError>

namespace Amber {

namespace Web {

namespace Authorization {

class OAuth2Private;
class EXPORT_SYMBOL OAuth2 : public QObject
{
    Q_OBJECT
    Q_DECLARE_PRIVATE(OAuth2)

    Q_PROPERTY(FlowType flowType READ flowType WRITE setFlowType NOTIFY flowTypeChanged)

    Q_PROPERTY(QString userAgent READ userAgent WRITE setUserAgent NOTIFY userAgentChanged)
    Q_PROPERTY(QString redirectUri READ redirectUri WRITE setRedirectUri NOTIFY redirectUriChanged)

    Q_PROPERTY(QString authorizationEndpoint READ authorizationEndpoint WRITE setAuthorizationEndpoint NOTIFY authorizationEndpointChanged)
    Q_PROPERTY(QString tokenEndpoint READ tokenEndpoint WRITE setTokenEndpoint NOTIFY tokenEndpointChanged)
    Q_PROPERTY(QString refreshEndpoint READ refreshEndpoint WRITE setRefreshEndpoint NOTIFY refreshEndpointChanged)

    Q_PROPERTY(QString clientId READ clientId WRITE setClientId NOTIFY clientIdChanged)
    Q_PROPERTY(QString clientSecret READ clientSecret WRITE setClientSecret NOTIFY clientSecretChanged)
    Q_PROPERTY(QString scope READ scope WRITE setScope NOTIFY scopeChanged)

    Q_PROPERTY(QString state READ state WRITE setState NOTIFY stateChanged)
    Q_PROPERTY(QString codeVerifier READ codeVerifier WRITE setCodeVerifier NOTIFY codeVerifierChanged)
    Q_PROPERTY(QString codeChallenge READ codeChallenge NOTIFY codeChallengeChanged)
    Q_PROPERTY(QString codeChallengeMethod READ codeChallengeMethod NOTIFY codeChallengeMethodChanged)

    Q_PROPERTY(QVariantMap customParameters READ customParameters WRITE setCustomParameters NOTIFY customParametersChanged)

    Q_PROPERTY(QNetworkAccessManager* networkAccessManager READ networkAccessManager WRITE setNetworkAccessManager NOTIFY networkAccessManagerChanged)

    Q_PROPERTY(QList<QSslError> ignorableSslErrors READ ignorableSslErrors WRITE setIgnorableSslErrors NOTIFY ignorableSslErrorsChanged)

    Q_PROPERTY(Amber::Web::Authorization::Error error READ error NOTIFY errorChanged)

public:
    OAuth2(QObject *parent = nullptr);
    ~OAuth2();

    Q_INVOKABLE QUrl generateAuthorizationUrl();
    Q_INVOKABLE void requestAccessToken(const QString &code = QString(), const QString &state = QString());
    Q_INVOKABLE void refreshAccessToken(const QString &refreshToken);
    Q_INVOKABLE bool abortCurrentRequest();

    Q_INVOKABLE QString generateScope(const QStringList &scopes, const QString &separator) const;
    Q_INVOKABLE QString generateState() const;
    Q_INVOKABLE QString generateCodeVerifier() const;
    Q_INVOKABLE QVariantMap parseRedirectUri(const QString &redirectUri);

    enum FlowType {
        InvalidFlow = 0,
        ImplicitFlow,                  // legacy flow; should not be used by new clients.
        ClientCredentialsFlow,         // for machine-to-machine grant; where the requester is the resource owner.
        AuthorizationCodeFlow,         // for web-app running on trusted web-server.
        AuthorizationCodeWithPkceFlow, // for most apps; user gives credentials to system browser only.
        ResourceOwnerPasswordFlow,     // for trusted client app; user has to give that app their credentials.
    };
    Q_ENUM(FlowType)

    FlowType flowType() const;
    void setFlowType(FlowType flow);

    QString userAgent() const;
    void setUserAgent(const QString &ua);

    QString redirectUri() const;
    void setRedirectUri(const QString &uri);

    QString authorizationEndpoint() const;
    void setAuthorizationEndpoint(const QString &endpoint);

    QString tokenEndpoint() const;
    void setTokenEndpoint(const QString &endpoint);

    QString refreshEndpoint() const;
    void setRefreshEndpoint(const QString &endpoint);

    QString clientId() const;
    void setClientId(const QString &clientId);

    QString clientSecret() const;
    void setClientSecret(const QString &clientSecret);

    QString scope() const;
    void setScope(const QString &scope);
    Q_INVOKABLE void setScope(const QStringList &scopes, const QString &separator = QString::fromLatin1(","));

    QString state() const;
    void setState(const QString &state);

    QString codeVerifier() const;
    void setCodeVerifier(const QString &verifier);

    QString codeChallenge() const;
    QString codeChallengeMethod() const;

    QVariantMap customParameters() const;
    void setCustomParameters(const QVariantMap &parameters);

    QNetworkAccessManager* networkAccessManager() const;
    void setNetworkAccessManager(QNetworkAccessManager *manager);

    QList<QSslError> ignorableSslErrors() const;
    void setIgnorableSslErrors(const QList<QSslError> &errors);

    Amber::Web::Authorization::Error error() const;

Q_SIGNALS:
    void flowTypeChanged();
    void userAgentChanged();
    void redirectUriChanged();
    void authorizationEndpointChanged();
    void tokenEndpointChanged();
    void refreshEndpointChanged();
    void clientIdChanged();
    void clientSecretChanged();
    void scopeChanged();
    void stateChanged();
    void codeVerifierChanged();
    void codeChallengeChanged();
    void codeChallengeMethodChanged();
    void customParametersChanged();
    void networkAccessManagerChanged();
    void ignorableSslErrorsChanged();
    void errorChanged();
    void redirectParseError(const QString &errorMessage);
    void sslErrors(const QList<QSslError> &errors);
    void receivedAccessToken(const QVariantMap &token);

private:
    void performAccessTokenRequest(const QUrlQuery &query);
    QScopedPointer<OAuth2Private> const d_ptr;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

#endif // AMBER_WEB_AUTHORIZATION_OAUTH2_H
