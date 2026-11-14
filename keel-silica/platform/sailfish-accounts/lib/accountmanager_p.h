/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTMANAGER_P_H
#define SAILFISH_ACCOUNTS__ACCOUNTMANAGER_P_H

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QString>

// libaccounts-qt
#include <Accounts/Manager>
#include <Accounts/Account>

class AccountManager;
class AccountManagerPrivate : public QObject
{
    Q_OBJECT

public:
    AccountManagerPrivate(AccountManager *parent);
    ~AccountManagerPrivate();

public Q_SLOTS:
    void updateEverything();
    void createAccountSynced();
    void createAccountError(const Accounts::Error &error);

public:
    AccountManager *q;
    Accounts::Manager *manager;

    QStringList serviceTypeNames;
    QStringList providerNames;
    QStringList serviceNames;
    QList<int> accountIdentifiers;

    bool componentComplete;
    bool busy;

    QMap<Accounts::Account*, QString> creatingAccounts;
};

#endif
