// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#ifndef AMBER_WEB_AUTHORIZATION_OAUTH1_H
#define AMBER_WEB_AUTHORIZATION_OAUTH1_H

#include "oauthsymbols.h"
#include "oautherror.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QVariantMap>
#include <QtCore/QString>
#include <QtCore/QUrl>

namespace Amber {

namespace Web {

namespace Authorization {

class OAuth1Private;
class EXPORT_SYMBOL OAuth1 : public QObject
{
    Q_OBJECT
    Q_DECLARE_PRIVATE(OAuth1)

    Q_PROPERTY(FlowType flowType READ flowType WRITE setFlowType NOTIFY flowTypeChanged)

    Q_PROPERTY(QString userAgent READ userAgent WRITE setUserAgent NOTIFY userAgentChanged)
    Q_PROPERTY(QString redirectUri READ redirectUri WRITE setRedirectUri NOTIFY redirectUriChanged)

    Q_PROPERTY(QString requestTokenEndpoint READ requestTokenEndpoint WRITE setRequestTokenEndpoint NOTIFY requestTokenEndpointChanged)
    Q_PROPERTY(QString authorizeTokenEndpoint READ authorizeTokenEndpoint WRITE setAuthorizeTokenEndpoint NOTIFY authorizeTokenEndpointChanged)
    Q_PROPERTY(QString accessTokenEndpoint READ accessTokenEndpoint WRITE setAccessTokenEndpoint NOTIFY accessTokenEndpointChanged)

    Q_PROPERTY(QString consumerKey READ consumerKey WRITE setConsumerKey NOTIFY consumerKeyChanged)
    Q_PROPERTY(QString consumerSecret READ consumerSecret WRITE setConsumerSecret NOTIFY consumerSecretChanged)

    Q_PROPERTY(QVariantMap customParameters READ customParameters WRITE setCustomParameters NOTIFY customParametersChanged)

    Q_PROPERTY(Amber::Web::Authorization::Error error READ error NOTIFY errorChanged)

public:
    OAuth1(QObject *parent = nullptr);
    ~OAuth1();

    Q_INVOKABLE void requestTemporaryToken();
    Q_INVOKABLE QUrl generateAuthorizationUrl(
            const QString &oauthToken);
    Q_INVOKABLE void requestAccessToken(
            const QString &oauthToken,
            const QString &oauthTokenSecret,
            const QString &oauthVerifier);

    Q_INVOKABLE QVariantMap parseRedirectUri(const QString &redirectUri);
    Q_INVOKABLE QString generateAuthorizationHeader(
            const QString &oauthToken,
            const QString &oauthTokenSecret,
            const QString &httpMethod,
            const QString &url);

    enum FlowType {
        InvalidFlow = 0,
        OAuth10aFlow
    };
    Q_ENUM(FlowType)

    FlowType flowType() const;
    void setFlowType(FlowType flow);

    QString userAgent() const;
    void setUserAgent(const QString &ua);

    QString redirectUri() const;
    void setRedirectUri(const QString &uri);

    QString requestTokenEndpoint() const;
    void setRequestTokenEndpoint(const QString &endpoint);

    QString authorizeTokenEndpoint() const;
    void setAuthorizeTokenEndpoint(const QString &endpoint);

    QString accessTokenEndpoint() const;
    void setAccessTokenEndpoint(const QString &endpoint);

    QString consumerKey() const;
    void setConsumerKey(const QString &key);

    QString consumerSecret() const;
    void setConsumerSecret(const QString &secret);

    QVariantMap customParameters() const;
    void setCustomParameters(const QVariantMap &parameters);

    Amber::Web::Authorization::Error error() const;

    static QString hmacSha1(
            const QString &signingKey,
            const QString &baseString);

    static QString authorizationHeader(
            const QString &consumerKey,
            const QString &consumerSecret,
            const QString &oauthToken,
            const QString &oauthTokenSecret,
            const QString &requestMethod,
            const QString &requestUrl,
            const QString &redirectUri,
            const QList<QPair<QString, QString> > &parameters);

Q_SIGNALS:
    void flowTypeChanged();
    void userAgentChanged();
    void redirectUriChanged();
    void requestTokenEndpointChanged();
    void authorizeTokenEndpointChanged();
    void accessTokenEndpointChanged();
    void consumerKeyChanged();
    void consumerSecretChanged();
    void customParametersChanged();
    void errorChanged();
    void redirectParseError(const QString &errorMessage);
    void receivedTemporaryToken(const QString &oauthToken, const QString &oauthTokenSecret);
    void receivedAccessToken(const QString &oauthToken, const QString &oauthTokenSecret);

private:
    QScopedPointer<OAuth1Private> const d_ptr;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

#endif // AMBER_WEB_AUTHORIZATION_OAUTH1_H
