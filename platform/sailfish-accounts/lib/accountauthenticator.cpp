// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 - 2024 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "accountauthenticator_p.h"
#include "globalaccountmanager_p.h"
#include "globaltranslatorcache_p.h"

#include <QtDebug>
#include <QMetaObject>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonObject>
#include <QJsonValue>


#ifdef USE_SAILFISHKEYPROVIDER
#include <sailfishkeyprovider.h>
#endif // USE_SAILFISHKEYPROVIDER

namespace {
    const QString SettingsKeyWebdavPath = QStringLiteral("webdav_path");
    const QString SettingsKeyServerAddress = QStringLiteral("server_address");

#ifdef USE_SAILFISHKEYPROVIDER
    QString skp_storedKey(const QString &provider, const QString &service, const QString &key)
    {
        QString retn;
        char *value = NULL;
        int success = SailfishKeyProvider_storedKey(provider.toLatin1(), service.toLatin1(), key.toLatin1(), &value);
        if (value) {
            if (success == 0) {
                retn = QString::fromLatin1(value);
            }
            free(value);
        }
        return retn;
    }
#endif // USE_SAILFISHKEYPROVIDER
}


AccountAuthenticator::AccountAuthenticator(QObject *parent)
    : QObject(parent)
    , d(new AccountAuthenticatorPrivate(this))
{
    SailfishAccounts::initLibTranslator();
}

void AccountAuthenticator::signIn(int accountId, const QString &serviceName)
{
    d->signIn(accountId, serviceName);
}

void AccountAuthenticator::sendAuthenticatedRequest(const QUrl &url,
                                                    const AccountAuthenticatorCredentials &credentials,
                                                    bool ignoreSslErrors)
{
    d->sendAuthenticatedRequest(url, credentials, ignoreSslErrors);
}

void AccountAuthenticator::sendOcsUserRequest(int accountId, const QString &serviceName,
                                              const AccountAuthenticatorCredentials &credentials,
                                              bool ignoreSslErrors)
{
    d->sendOcsUserRequest(accountId, serviceName, credentials, ignoreSslErrors);
}

bool AccountAuthenticator::setCredentialsNeedUpdate(int accountId, const QString &serviceName)
{
    return d->setCredentialsNeedUpdate(accountId, serviceName);
}


AccountAuthenticatorPrivate::AccountAuthenticatorPrivate(AccountAuthenticator *parent)
    : QObject(parent)
    , q(parent)
{
}

AccountAuthenticatorPrivate::~AccountAuthenticatorPrivate()
{
    while (m_authData.size()) {
        AuthData authData = m_authData.takeFirst();
        authData.identity->destroySession(authData.authSession);
        authData.identity->deleteLater();
        authData.account->deleteLater();
    }
}

void AccountAuthenticatorPrivate::signIn(int accountId, const QString &serviceName)
{
    Accounts::Account *account = Accounts::Account::fromId(globalAccountManager(), accountId, this);
    if (!account) {
        emit q->signInError(accountId,
                            serviceName,
                            //% "Cannot load account for sign-in."
                            qtTrId("sailfishaccounts-la-account_load_error"));
        return;
    }

    // determine which service to sign in with.
    Accounts::Service srv;
    Accounts::ServiceList services = account->services();
    Q_FOREACH (const Accounts::Service &s, services) {
        if (s.name() == serviceName) {
            srv = s;
            break;
        }
    }

    if (!srv.isValid()) {
        account->deleteLater();

        //% "Cannot find '%1' service for this account."
        const QString errorString = qtTrId("sailfishaccounts-la-service_load_error").arg(serviceName);
        emit q->signInError(accountId, serviceName, errorString);
        return;
    }

    account->selectService(srv);
    if (!account->isEnabled()) {
        account->deleteLater();

        //% "Cannot authenticate, '%1' service is not enabled."
        const QString errorString = qtTrId("sailfishaccounts-la-service_not_enabled").arg(srv.name());
        emit q->signInError(accountId, serviceName, errorString);
        return;
    }

    const QStringList &serviceKeys = account->allKeys();
    QVariantMap serviceSettings;
    for (const QString &key: serviceKeys) {
        serviceSettings.insert(key, account->value(key));
    }

    const QString serverAddress = serviceSettings.value(SettingsKeyServerAddress).toString();
    if (serverAddress.isEmpty()) {
        account->deleteLater();

        //% "Server address %1 for '%2' service is invalid."
        const QString errorString = qtTrId("sailfishaccounts-la-invalid_url").arg(serverAddress).arg(serviceName);
        emit q->signInError(accountId, serviceName, errorString);
        return;
    }

    SignOn::Identity *ident = account->credentialsId() > 0
            ? SignOn::Identity::existingIdentity(account->credentialsId())
            : 0;
    if (!ident) {
        account->deleteLater();
        emit q->signInError(accountId,
                            serviceName,
                            //% "Cannot find valid sign-in credentials for this account."
                            qtTrId("sailfishaccounts-la-invalid_credentials"));
        return;
    }

    Accounts::AccountService accountService(account, srv);
    QString method = accountService.authData().method();
    QString mechanism = accountService.authData().mechanism();
    SignOn::AuthSession *session = ident->createSession(method);
    if (!session) {
        account->deleteLater();
        ident->deleteLater();
        emit q->signInError(accountId,
                            serviceName,
                            //% "Cannot create an authentication session for this account."
                            qtTrId("sailfishaccounts-la-auth_session_error"));
        return;
    }

    QString clientId;
    QString clientSecret;
    QString consumerKey;
    QString consumerSecret;
#ifdef USE_SAILFISHKEYPROVIDER
    QString providerName = account->providerName();
    clientId = skp_storedKey(providerName, QString(), QStringLiteral("client_id"));
    clientSecret = skp_storedKey(providerName, QString(), QStringLiteral("client_secret"));
    consumerKey = skp_storedKey(providerName, QString(), QStringLiteral("consumer_key"));
    consumerSecret = skp_storedKey(providerName, QString(), QStringLiteral("consumer_secret"));
#endif

    QVariantMap signonSessionData = accountService.authData().parameters();
    signonSessionData.insert("UiPolicy", SignOn::NoUserInteractionPolicy);
    if (!clientId.isEmpty()) signonSessionData.insert("ClientId", clientId);
    if (!clientSecret.isEmpty()) signonSessionData.insert("ClientSecret", clientSecret);
    if (!consumerKey.isEmpty()) signonSessionData.insert("ConsumerKey", consumerKey);
    if (!consumerSecret.isEmpty()) signonSessionData.insert("ConsumerSecret", consumerSecret);

    connect(session, &SignOn::AuthSession::response,
            this, &AccountAuthenticatorPrivate::signOnResponse,
            Qt::UniqueConnection);
    connect(session, &SignOn::AuthSession::error,
            this, &AccountAuthenticatorPrivate::signOnError,
            Qt::UniqueConnection);

    AuthData authData;
    authData.accountId = accountId;
    authData.serviceName = serviceName;
    authData.mechanism = mechanism;
    authData.signonSessionData = signonSessionData;
    authData.account = account;
    authData.identity = ident;
    authData.authSession = session;
    authData.credentials.serviceSettings = serviceSettings;
    m_authData.append(authData);

    session->setProperty("accountId", accountId);
    session->process(SignOn::SessionData(signonSessionData), mechanism);
}

void AccountAuthenticatorPrivate::signOnResponse(const SignOn::SessionData &response)
{
    QString username, password, accessToken;
    Q_FOREACH (const QString &key, response.propertyNames()) {
        if (key.toLower() == QStringLiteral("username")) {
            username = response.getProperty(key).toString();
        } else if (key.toLower() == QStringLiteral("secret")) {
            password = response.getProperty(key).toString();
        } else if (key.toLower() == QStringLiteral("password")) {
            password = response.getProperty(key).toString();
        } else if (key.toLower() == QStringLiteral("accesstoken")) {
            accessToken = response.getProperty(key).toString();
        }
    }

    const int accountId = sender()->property("accountId").toInt();
    const int authDataSize = m_authData.size();
    for (int i = 0; i < authDataSize; ++i) {
        if (m_authData[i].accountId == accountId) {
            AuthData authData = m_authData.takeAt(i);
            authData.identity->destroySession(authData.authSession);
            authData.identity->deleteLater();
            authData.account->deleteLater();

            // we need both username+password, OR accessToken.
            if (!accessToken.isEmpty()) {
                authData.credentials.accessToken = accessToken;
                emit q->signInCompleted(accountId, authData.serviceName, authData.credentials);
            } else if (!username.isEmpty() && !password.isEmpty()) {
                authData.credentials.username = username;
                authData.credentials.password = password;
                emit q->signInCompleted(accountId, authData.serviceName, authData.credentials);
            } else {
                emit q->signInError(accountId,
                                    authData.serviceName,
                                    //% "Cannot find valid sign-in credentials for the new account."
                                    qtTrId("sailfishaccounts-la-invalid_credentials_after_auth"));
            }
            return;
        }
    }

    emit q->signInError(accountId,
                        QString(),
                        //% "Cannot find authentication details for the new account."
                        qtTrId("sailfishaccounts-la-invalid_auth_session_on_sign_in"));
}

void AccountAuthenticatorPrivate::signOnError(const SignOn::Error &error)
{
    const int accountId = sender()->property("accountId").toInt();
    const int authDataSize = m_authData.size();
    for (int i = 0; i < authDataSize; ++i) {
        if (m_authData[i].accountId == accountId) {
            AuthData authData = m_authData.takeAt(i);

            // Signon failed due to credentials not existing in the database.
            // Set the CredentialsNeedUpdate key to force user to update credentials.
            if (error.type() == SignOn::Error::UserInteraction) {
                setCredentialsNeedUpdate(accountId, authData.serviceName);
            }

            authData.identity->destroySession(authData.authSession);
            authData.identity->deleteLater();
            authData.account->deleteLater();

            //% "Authentication error: %1"
            const QString errorString = qtTrId("sailfishaccounts-la-auth_error").arg(error.message());
            emit q->signInError(accountId, authData.serviceName, errorString);
            return;
        }
    }

    //% "Authentication error (for unknown service): %1"
    const QString errorString = qtTrId("sailfishaccounts-la-auth_error_no_service").arg(error.message());
    emit q->signInError(accountId, QString(), errorString);
}

void AccountAuthenticatorPrivate::sendAuthenticatedRequest(const QUrl &url,
                                                           const AccountAuthenticatorCredentials &credentials,
                                                           bool ignoreSslErrors)
{
    if (!m_networkAccessManager) {
        m_networkAccessManager = new QNetworkAccessManager(this);
    }

    if (!url.isValid()) {
        QMetaObject::invokeMethod(q,
                                  "authenticatedRequestFinished",
                                  Qt::QueuedConnection,
                                  Q_ARG(bool, true),
                                  //% "Invalid URL. Check the server address and try again."
                                  Q_ARG(QString, qtTrId("sailfish_components_accounts_qt5-la-invalid_server_url")));
        return;
    }

    QNetworkRequest request;
    QUrl authUrl(url);

    if (!credentials.accessToken.isEmpty()) {
        request.setRawHeader("Authorization", "Bearer " + credentials.accessToken.toLatin1());
    } else {
        authUrl.setUserName(credentials.username);
        authUrl.setPassword(credentials.password);
    }
    request.setUrl(authUrl);

    QNetworkReply *reply = m_networkAccessManager->head(request);
    reply->setProperty("ignoreSslErrors", ignoreSslErrors);
    reply->setProperty("credentialsUsername", credentials.username);
    reply->setProperty("credentialsPassword", credentials.password);
    reply->setProperty("credentialsAccessToken", credentials.accessToken);
    connect(reply, &QNetworkReply::finished,
            this, &AccountAuthenticatorPrivate::authenticatedRequestFinished);
    connect(reply, &QNetworkReply::sslErrors,
            this, &AccountAuthenticatorPrivate::authenticatedRequestSslErrors);
}

void AccountAuthenticatorPrivate::authenticatedRequestFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    const int httpCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const bool ignoreSslErrors = reply->property("ignoreSslErrors").toBool();
    const bool isWellKnown = reply->url().toString().contains(QStringLiteral(".well-known"));

    if (reply->error() == QNetworkReply::NoError) {
        emit q->authenticatedRequestFinished(true, QString());
    } else if (!isWellKnown) {
        // the url we tried didn't support authenticated requests.
        // try the .well-known redirect endpoint.
        AccountAuthenticatorCredentials credentials;
        credentials.username = reply->property("credentialsUsername").toString();
        credentials.password = reply->property("credentialsPassword").toString();
        credentials.accessToken = reply->property("credentialsAccessToken").toString();
        QUrl url = reply->url();
        url.setPath(QStringLiteral("/.well-known"));
        sendAuthenticatedRequest(url, credentials, ignoreSslErrors);
    } else {
        // the credentials are probably wrong.
        QUrl url = reply->url();
        url.setUserName(QString());
        url.setPassword(QString());
        qWarning() << "sendAuthenticatedRequest(): request error:" << reply->error()
                   << "response code:" << httpCode
                   << "url:" << url.toString();
        //% "Check the sign-in details and try again. Authentication failed for url: %1"
        const QString errorString = qtTrId("sailfish_components_accounts_qt5-la-request_auth_failed").arg(url.toString());
        emit q->authenticatedRequestFinished(false, errorString);
    }
}

void AccountAuthenticatorPrivate::authenticatedRequestSslErrors(const QList<QSslError> &errors)
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (reply->property("ignoreSslErrors").toBool()) {
        reply->ignoreSslErrors(errors);
    }
}

void AccountAuthenticatorPrivate::sendOcsUserRequest(int accountId, const QString &serviceName,
                                                     const AccountAuthenticatorCredentials &credentials,
                                                     bool ignoreSslErrors)
{
    if (!m_networkAccessManager) {
        m_networkAccessManager = new QNetworkAccessManager(this);
    }

    const QString serverAddress = credentials.serviceSettings.value(SettingsKeyServerAddress).toString();

    if (serverAddress.isEmpty()) {
        QMetaObject::invokeMethod(q,
                                  "ocsUserRequestFinished",
                                  Qt::QueuedConnection,
                                  Q_ARG(bool, true),
                                  //% "Invalid URL. Check the server address and try again."
                                  Q_ARG(QString, qtTrId("sailfish_components_accounts_qt5-la-invalid_server_url")));
        return;
    }

    QNetworkRequest request = networkRequest(serverAddress, credentials, "/ocs/v2.php/cloud/user");
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkAccessManager->sendCustomRequest(request, "GET");
    reply->setProperty("accountId", accountId);
    reply->setProperty("serviceName", serviceName);
    reply->setProperty("serviceSettings", credentials.serviceSettings);
    reply->setProperty("username", credentials.username);
    reply->setProperty("ignoreSslErrors", ignoreSslErrors);

    connect(reply, &QNetworkReply::finished,
            this, &AccountAuthenticatorPrivate::ocsUserRequestFinished);
    connect(reply, &QNetworkReply::sslErrors,
            this, &AccountAuthenticatorPrivate::ocsUserRequestSslErrors);
}

void AccountAuthenticatorPrivate::ocsUserRequestFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    const int httpCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (reply->error() == QNetworkReply::NoError) {
        const QVariantMap serviceSettings = reply->property("serviceSettings").toMap();
        const QString userName = reply->property("username").toString();

        const QString userId = parseUserIdFromOcsUserResponse(reply->readAll());
        qDebug() << "User info request returned userId" << userId << "for username:" << userName;

        if (userId.isEmpty()) {
            qWarning() << "Error: User info request returned empty user ID!";
        } else {
            if (userId != userName) {
                // If the default WebDAV path contains the username and it is different from the userId,
                // subsequent requests will fail. Fix any setting that uses the invalid path.

                const QString defaultPathPartTemplate = QStringLiteral("remote.php/dav/files/%1");
                const QString pathWithUserName = defaultPathPartTemplate.arg(userName);
                const QString pathWithUserId = defaultPathPartTemplate.arg(userId);
                const int accountId = reply->property("accountId").toInt();

                Accounts::Account *account = globalAccountManager()->account(accountId);
                if (account) {
                    Accounts::Service srv;
                    const Accounts::ServiceList services = account->services();
                    bool settingsChanged = false;
                    for (const Accounts::Service &srv: services) {
                        account->selectService(srv);
                        const QStringList &serviceKeys = account->allKeys();
                        for (const QString &key: serviceKeys) {
                            const QVariant value = account->value(key);
                            if (value.type() != QVariant::String) {
                                continue;
                            }
                            const QString prevSettingValue = value.toString();
                            QString newSettingValue = prevSettingValue;
                            newSettingValue.replace(pathWithUserName, pathWithUserId);
                            if (prevSettingValue != newSettingValue) {
                                account->setValue(key, newSettingValue);
                                settingsChanged = true;
                            }
                        }
                        account->selectService(Accounts::Service());
                    }
                    if (settingsChanged) {
                        account->syncAndBlock();
                    }
                }
            }

            emit q->ocsUserRequestFinished(true, QString());
            return;
        }
    }

    QUrl url = reply->url();
    url.setUserName(QString());
    url.setPassword(QString());
    qWarning() << "sendOcsUserRequest(): request error:" << reply->error()
               << "response code:" << httpCode
               << "url:" << url.toString();
    //% "Check the sign-in details and try again. Authentication failed for url: %1"
    const QString errorString = qtTrId("sailfish_components_accounts_qt5-la-request_auth_failed").arg(url.toString());
    emit q->ocsUserRequestFinished(false, errorString);
}

void AccountAuthenticatorPrivate::ocsUserRequestSslErrors(const QList<QSslError> &errors)
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (reply->property("ignoreSslErrors").toBool()) {
        reply->ignoreSslErrors(errors);
    }
}

bool AccountAuthenticatorPrivate::setCredentialsNeedUpdate(int accountId, const QString &serviceName)
{
    Accounts::Account *account = globalAccountManager()->account(accountId);
    if (account) {
        Accounts::Service service(globalAccountManager()->service(serviceName));
        if (service.isValid()) {
            account->selectService(service);
            account->setValue(QStringLiteral("CredentialsNeedUpdate"), QVariant::fromValue<bool>(true));
            account->setValue(QStringLiteral("CredentialsNeedUpdateFrom"), QVariant::fromValue<QString>(serviceName));
            account->selectService(Accounts::Service());
            account->syncAndBlock();
            return true;
        }
    }
    return false;
}

QNetworkRequest AccountAuthenticatorPrivate::networkRequest(const QUrl &serverAddress,
                                                            const AccountAuthenticatorCredentials &credentials,
                                                            const QString &path)
{
    const bool isOcsRequest = path.startsWith(QStringLiteral("/ocs/"));

    QUrl url(serverAddress);
    if (!path.isEmpty()) {
        QString modifiedPath(path);

        // common case: the path may contain %40 instead of @ symbol,
        // if the server returns paths in percent-encoded form.
        // QUrl::setPath() will automatically percent-encode the input,
        // so if we have received percent-encoded path, we need to undo
        // the percent encoding first.  This is suboptimal but works
        // at least for the common case.
        if (modifiedPath.contains(QStringLiteral("%40"))) {
            modifiedPath = QUrl::fromPercentEncoding(modifiedPath.toUtf8());
        }

        if (isOcsRequest) {
            // Append the request path instead of overwriting the existing url.path() in case the
            // server url ends with a subdirectory path.
            QString serverPath = url.path();
            if (serverPath.endsWith('/')) {
                serverPath = serverPath.mid(0, serverPath.length() - 1);
            }
            url.setPath(serverPath + modifiedPath);
        } else {
            url.setPath(modifiedPath.startsWith('/') ? modifiedPath : '/' + modifiedPath);
        }
    }

    QNetworkRequest request(url);

    if (isOcsRequest) {
        // Nextcloud OCS APIs require Basic Authentication. Qt 5.6 QNetworkAccessManager does not
        // generate the expected request headers for this if user/pass are set in the URL, so
        // set them manually instead.
        QByteArray credentialBytes((credentials.username + ':' + credentials.password).toUtf8());
        request.setRawHeader("Authorization", QByteArray("Basic ") + credentialBytes.toBase64());

        // Nextcloud APIs require this to avoid "CSRF check failed" error.
        request.setRawHeader("OCS-APIRequest", "true");

    } else if (!credentials.username.isEmpty() && !credentials.password.isEmpty()) {
        QUrl authenticatedUrl = url;
        authenticatedUrl.setUserName(credentials.username);
        authenticatedUrl.setPassword(credentials.password);
        request.setUrl(authenticatedUrl);
    }

    if (!credentials.accessToken.isEmpty()) {
        request.setRawHeader("Authorization", QString(QLatin1String("Bearer ") + credentials.accessToken).toUtf8());
    }

    return request;
}

QString AccountAuthenticatorPrivate::parseUserIdFromOcsUserResponse(const QByteArray &ocsUserResponse)
{
    QJsonParseError err;

    const QJsonDocument doc = QJsonDocument::fromJson(ocsUserResponse, &err);
    if (err.error != QJsonParseError::NoError) {
        qWarning() << "JSON parsing failed:" << err.errorString();
        return QString();
    }

    const QJsonObject ocs = doc.object().value(QLatin1String("ocs")).toObject();
    const QJsonObject data = ocs.value(QLatin1String("data")).toObject();
    return data.value(QLatin1String("id")).toString();
}
