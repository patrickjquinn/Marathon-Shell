/*
 * SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_H
#define SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_H

#include <QObject>
#include <QVariantMap>

class AccountAuthenticatorPrivate;

class Q_DECL_EXPORT AccountAuthenticatorCredentials
{
    Q_GADGET
    Q_PROPERTY(QString username MEMBER username)
    Q_PROPERTY(QString password MEMBER password)
    Q_PROPERTY(QString accessToken MEMBER accessToken)
    Q_PROPERTY(QVariantMap serviceSettings MEMBER serviceSettings)

public:
    QString username;
    QString password;
    QString accessToken;
    QVariantMap serviceSettings;
};

Q_DECLARE_METATYPE(AccountAuthenticatorCredentials)

class Q_DECL_EXPORT AccountAuthenticator : public QObject
{
    Q_OBJECT

public:
    AccountAuthenticator(QObject *parent = nullptr);

    Q_INVOKABLE void signIn(int accountId, const QString &serviceName);

    Q_INVOKABLE void sendAuthenticatedRequest(const QUrl &url,
                                              const AccountAuthenticatorCredentials &credentials,
                                              bool ignoreSslErrors);
    Q_INVOKABLE void sendOcsUserRequest(int accountId,
                                        const QString &serviceName,
                                        const AccountAuthenticatorCredentials &credentials,
                                        bool ignoreSslErrors);
    Q_INVOKABLE bool setCredentialsNeedUpdate(int accountId, const QString &serviceName);

Q_SIGNALS:
    void signInCompleted(int accountId,
                         const QString &serviceName,
                         const AccountAuthenticatorCredentials &credentials);
    void signInError(int accountId, const QString &serviceName, const QString &errorString);

    void authenticatedRequestFinished(bool success, const QString &errorString);
    void ocsUserRequestFinished(bool success, const QString &errorString);

private:
    friend class AccountAuthenticatorPrivate;
    AccountAuthenticatorPrivate *d;
};

#endif // SAILFISH_ACCOUNTS__ACCOUNTAUTHENTICATOR_H
