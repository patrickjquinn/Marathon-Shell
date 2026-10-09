/*
 * SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_P_H
#define SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_P_H

#include "accountauthenticator.h"

#include <Accounts/Account>
#include <Accounts/Manager>
#include <Accounts/Service>
#include <Accounts/AccountService>
#include <SignOn/Identity>
#include <SignOn/Error>
#include <SignOn/SessionData>
#include <SignOn/AuthSession>

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkAccessManager>
#include <QObject>
#include <QVector>

class AccountAuthenticatorPrivate : public QObject
{
    Q_OBJECT

public:
    AccountAuthenticatorPrivate(AccountAuthenticator *parent);
    ~AccountAuthenticatorPrivate();

    void signIn(int accountId, const QString &serviceName);
    void sendAuthenticatedRequest(const QUrl &url, const AccountAuthenticatorCredentials &credentials,
                                  bool ignoreSslErrors);
    void sendOcsUserRequest(int accountId,
                            const QString &serviceName,
                            const AccountAuthenticatorCredentials &credentials,
                            bool ignoreSslErrors);
    bool setCredentialsNeedUpdate(int accountId, const QString &serviceName);

private:
    void signOnResponse(const SignOn::SessionData &response);
    void signOnError(const SignOn::Error &error);

    void authenticatedRequestFinished();
    void authenticatedRequestSslErrors(const QList<QSslError> &errors);

    void ocsUserRequestFinished();
    void ocsUserRequestSslErrors(const QList<QSslError> &errors);

    QNetworkRequest networkRequest(const QUrl &serverAddress, const AccountAuthenticatorCredentials &credentials,
                                   const QString &path);
    QString parseUserIdFromOcsUserResponse(const QByteArray &ocsUserResponse);

    class AuthData
    {
    public:
        int accountId;
        QString serviceName;
        QString mechanism;
        QVariantMap signonSessionData;
        Accounts::Account *account;
        SignOn::Identity *identity;
        SignOn::AuthSession *authSession;
        AccountAuthenticatorCredentials credentials;
    };

    AccountAuthenticator *q;
    QNetworkAccessManager *m_networkAccessManager = nullptr;
    QVector<AuthData> m_authData;
};

#endif // SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_P_H
