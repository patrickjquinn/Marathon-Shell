/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNT_P_H
#define SAILFISH_ACCOUNTS__ACCOUNT_P_H

#include "account.h"

#include <QtCore/QObject>
#include <QStringList>
#include <QString>

// libaccounts-qt
#include <Accounts/Account>
#include <Accounts/Manager>

// libsignon-qt
#include <SignOn/Identity>
#include <SignOn/IdentityInfo>
#include <SignOn/AuthSession>

static const auto AccountReadOnlyKey = QStringLiteral("readonly");
static const auto AccountProvisionedKey = QStringLiteral("provisioned"); // created by MDM.
static const auto AccountLimitedKey = QStringLiteral("limited");

struct SignInCredentials
{
    bool creatingSignInCredentials;
    bool updatingSignInCredentials;
    bool signingInWithCredentials;
    bool storingEncryptedTokens;
    bool forcingCredentialsRefresh;
    bool haveForcedCredentialsExpiry;
    bool canceling;

    SignOn::Identity *identity;
    SignOn::AuthSession *session;

    SignOn::IdentityInfo identityInfo;

    QString applicationName;
    QString symmetricKey;
    QString serviceName;
    QString method;
    QString mechanism;
    QVariantMap sessionData;
    QString credentialsName;
    QString username;
    QString password;

    QVariantMap responseData;

    void cleanup(bool removeIdentity = false);
};

class AccountPrivate : public QObject
{
    Q_OBJECT

public:
    enum ConfigState {
        Default,
        Change,
        Remove
    };
    typedef QMap<QString, ConfigState> ConfigStateMap;

    AccountPrivate(Account *parent, Accounts::Account *acc, bool queryInfo = true);
    ~AccountPrivate();

    void setAccount(Accounts::Account *acc, bool queryInfo);
    void setStatus(Account::Status newStatus);
    bool prepareSync();

    void cancelCredentialsOperation(bool removeIdentity);

    void setUserName(const QString &user);

    void updateStoreRepositories(bool enable);

    void updateServiceKeys(const Accounts::Service &service, ConfigStateMap &states,
                           const QVariantMap &values, QVariantMap &baseline);
    void updateServiceKey(const ConfigStateMap &states, const QVariantMap &values,
                          QVariantMap &baseline, const QString &key);

    Account *q;
    Accounts::Manager *manager;
    Accounts::Account *account;

    SignInCredentials signInCredentials;

    bool pendingSync;
    bool pendingInitModifications;

    int identifier;
    QString providerName;
    bool enabled;
    QString displayName;
    QString defaultCredentialsUserName;
    QVariantMap configurationValues;
    QMap<QString, QVariantMap> serviceConfigurationValues;

    QVariantMap baselineValues;
    QMap<QString, QVariantMap> serviceBaselineValues;
    ConfigStateMap configurationStates;
    QMap<QString, ConfigStateMap> serviceConfigurationStates;

    QStringList supportedServiceNames;
    QMap<QString, bool> serviceEnabledChanges;
    bool enabledPendingInit;
    bool displayNamePendingInit;
    bool displayNameModified;
    bool configurationValuesPendingInit;
    bool constructedWithAccountPtr;

    bool provisioned;
    bool readonly;
    bool limited;

    Account::Status status;
    Account::ErrorType error;
    SignOn::AuthSession::AuthSessionState sessionState;
    QString errorMessage;

public:
    QVariantMap plainTextResponseData(const QString &method,
                                      const QVariantMap &encryptedResponseData,
                                      const QString &symmetricKey,
                                      const QString &applicationName,
                                      bool *succeeded) const;
    bool serviceReadyForEdits(const QString &serviceName) const;
    void setModified(bool &pendingInit);

public Q_SLOTS:
    void enabledHandler(const QString &, bool);
    void displayNameChangedHandler();
    void invalidate();
    void handleRemoved();
    void handleSynced();
    void asyncQueryInfo();

    // for credentials creation / sign-in
    void handleCredentialsStored(quint32);
    void handleCredentialsInfo(const SignOn::IdentityInfo &info);
    void handleCredentialsFailed(const SignOn::Error &err);
    void handleResponse(const SignOn::SessionData &data);
    void handleExpiryTimeout();
    void handleSignOnError(const SignOn::Error &err);
    void handleStateChanged(SignOn::AuthSession::AuthSessionState state, const QString &message);
    void handleAccountError();
};

#endif
