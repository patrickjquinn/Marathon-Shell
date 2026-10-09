// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd.
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

//project
#include "account-model.h"
#include "serviceaccountinterface.h"
#include "providerinterface.h"

//Qt
#include <QtDebug>

//libaccounts-qt
#include <Accounts/Manager>
#include <Accounts/Account>
#include <Accounts/Provider>

struct DisplayData {
    DisplayData(Accounts::Account *acct) : account(acct) {}
    ~DisplayData() { delete account; }
    Accounts::Account *account;
    QString providerName;
    QString providerDisplayName;
    QString accountIcon;
    Q_DISABLE_COPY(DisplayData);
};

class AccountModel::AccountModelPrivate
{
public:
    ~AccountModelPrivate()
    {
        qDeleteAll(accountsList);
    }

    QHash<int, QByteArray> headerData;
    Accounts::Manager *manager;
    QList<DisplayData *> accountsList;
};

AccountModel::AccountModel(QObject* parent)
    : QAbstractListModel(parent)
    , d_ptr(new AccountModelPrivate())
{
    Q_D(AccountModel);
    d->manager = new Accounts::Manager();
    Accounts::ServiceList allServices = d->manager->serviceList(); // force reload of service files.
    d->headerData.insert(AccountIdRole, "accountId");
    d->headerData.insert(AccountDisplayNameRole, "accountDisplayName");
    d->headerData.insert(AccountIconRole, "accountIcon" );
    d->headerData.insert(ProviderNameRole, "providerName");
    d->headerData.insert(ProviderDisplayNameRole, "providerDisplayName");
    d->headerData.insert(ColumnCountRole, "columncount");
    QObject::connect(d->manager, SIGNAL(accountCreated(Accounts::AccountId)),
                     this, SLOT(accountCreated(Accounts::AccountId)));
    QObject::connect(d->manager, SIGNAL(accountRemoved(Accounts::AccountId)),
                     this, SLOT(accountRemoved(Accounts::AccountId)));
    QObject::connect(d->manager, SIGNAL(accountUpdated(Accounts::AccountId)),
                     this, SLOT(accountUpdated(Accounts::AccountId)));
    QObject::connect(d->manager, SIGNAL(enabledEvent(Accounts::AccountId)),
                     this, SLOT(accountUpdated(Accounts::AccountId)));
#if QT_VERSION < QT_VERSION_CHECK(5, 0, 0)
    setRoleNames(d->headerData);
#endif
    Accounts::AccountIdList idList = d->manager->accountList();
    foreach (Accounts::AccountId id, idList)
    {
        Accounts::Account *account = d->manager->account(id);
        addedAccount(account);
        d->accountsList.append(new DisplayData(account));
    }
}

AccountModel::~AccountModel()
{
}

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
QHash<int, QByteArray> AccountModel::roleNames() const
{
    Q_D(const AccountModel);
    return d->headerData;
}
#endif

int AccountModel::rowCount(const QModelIndex &parent) const
{
    Q_D(const AccountModel);
    if (parent.isValid())
        return 0;
    return d->accountsList.length();
}

int AccountModel::columnCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return ColumnCount;
}

QVariant AccountModel::data(const QModelIndex &index, int role) const
{
    Q_D(const AccountModel);
    if (!index.isValid() || index.row() >= d->accountsList.length())
        return QVariant();

    DisplayData *data = d->accountsList[index.row()];
    Accounts::Account *account = data->account;

    if (role == AccountIdRole ||
            (role == Qt::DisplayRole && index.column() == AccountIdColumn))
        return QVariant::fromValue(account->id());

    if (role == AccountDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == AccountDisplayNameColumn))
        return QVariant::fromValue(account->displayName());

    if (role == AccountIconRole ||
            (role == Qt::DisplayRole && index.column() == AccountIconColumn)) {
        if (data->accountIcon.isNull()) {
            Accounts::Provider provider = d->manager->provider(account->providerName());
            data->accountIcon = provider.iconName();
        }
        return QVariant::fromValue(data->accountIcon);
    }

    if (role == ProviderNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderNameColumn)) {
        Accounts::Provider provider = d->manager->provider(account->providerName());
        data->providerName = provider.name();
        return QVariant::fromValue(data->providerName);
    }

    if (role == ProviderDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderDisplayNameColumn)) {
        Accounts::Provider provider = d->manager->provider(account->providerName());
        data->providerDisplayName = provider.displayName();
        return QVariant::fromValue(data->providerDisplayName);
    }

    if (role == AccountEnabledRole ||
            (role == Qt::DisplayRole && index.column() == AccountEnabledColumn)) {
        return QVariant::fromValue(account->enabled());
    }

    return QVariant();
}

QVariant AccountModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    Q_D(const AccountModel);
    if (orientation != Qt::Horizontal) {
        return QVariant();
    }
    Columns column = static_cast<Columns>(section);

    if (role == Qt::DisplayRole) {
        if (section < d->headerData.size()) {
            return d->headerData.value(column);
        }
    }
    return QVariant();
}

void AccountModel::accountCreated(Accounts::AccountId id)
{
    Q_D(AccountModel);
    QModelIndex index;
    Accounts::Account *account = d->manager->account(id);
    addedAccount(account);

    if (account != 0) {
        beginInsertRows(index, 0, 0);
        d->accountsList.insert(0, new DisplayData(account));
        endInsertRows();
    }
}

void AccountModel::accountRemoved(Accounts::AccountId id)
{
    Q_D(AccountModel);

    int index = getAccountIndex(id);

    if (index < 0) {
        qWarning() << Q_FUNC_INFO << "Account not present in the list:" << id;
        return;
    }

    QModelIndex parent;
    beginRemoveRows(parent, index, index);
    DisplayData *data = d->accountsList.takeAt(index);
    endRemoveRows();

    removedAccount(data->account);
    delete data;
}

void AccountModel::accountUpdated(Accounts::AccountId id)
{
    int accountIndex = getAccountIndex(id);
    if (accountIndex < 0) {
        qWarning() << Q_FUNC_INFO << "Account not present in the list:" << id;
        return;
    }

    emit dataChanged(index(accountIndex, 0), index(accountIndex, 0));
}

void AccountModel::accountDisplayNameChanged()
{
    Accounts::Account *account = qobject_cast<Accounts::Account*>(sender());
    if (account)
        accountUpdated(account->id());
}

int AccountModel::getAccountIndex(Accounts::AccountId id) const
{
    Q_D(const AccountModel);
    for (int i = 0; i < d->accountsList.count(); ++i) {
        if (d->accountsList.at(i)->account->id() == id) {
            return i;
        }
    }

    return -1;
}

void AccountModel::addedAccount(Accounts::Account *account)
{
    if (account) {
        QObject::connect(account, SIGNAL(displayNameChanged(QString)),
                this, SLOT(accountDisplayNameChanged()));
    }
}

void AccountModel::removedAccount(Accounts::Account *account)
{
    if (account) {
        QObject::disconnect(account, SIGNAL(displayNameChanged(QString)),
                this, SLOT(accountDisplayNameChanged()));
    }
}

/*!
    \qmltype AccountModel
    \instantiates AccountModel
    \inqmlmodule org.nemomobile.accounts 1
    \brief Provides a model of existing accounts

    The AccountModel can be used to provide account data to a view.
    For each account in the database, it exposes:
    \list
    \li accountId
    \li accountDisplayName
    \li accountIcon
    \li providerName
    \li providerDisplayName
    \endlist

    It also provides invokable methods to retrieve a Provider
    associated with an account, or a client-usable ServiceAccount.
*/

/*!
    \qmlmethod ServiceAccount* AccountModel::serviceAccount(int accountId, const QString &serviceName, QObject *parent)
    Returns the ServiceAccount for a given id and service name, or zero
    if the account doesn't support the service.  The returned ServiceAccount
    will be owned by the specified \a parent.
 */
ServiceAccountInterface *AccountModel::serviceAccount(int accountId, const QString &serviceName, QObject *parent)
{
    Q_D(AccountModel);

    if (accountId == 0)
        return 0;

    Accounts::Service s = d->manager->service(serviceName);
    if (!s.isValid())
        return 0;

    Accounts::AccountService *sa = 0;
    for (int i = 0; i < d->accountsList.size(); ++i) {
        DisplayData *data = d->accountsList.at(i);
        int currId = data->account->id();
        if (currId == accountId) {
            sa = new Accounts::AccountService(data->account, s);
            break;
        }
    }

    if (!sa)
        return 0;

    return new ServiceAccountInterface(sa, ServiceAccountInterface::HasOwnership, parent);
}

/*!
    \qmlmethod Provider* AccountModel::provider(const QString &providerName, QObject *parent)
    Returns the Provider with the given \a providerName, or zero if no such
    provider exists.  The returned Provider will be owned by the specified
    \a parent.
 */
ProviderInterface *AccountModel::provider(const QString &providerName, QObject *parent)
{
    Q_D(AccountModel);

    if (providerName.isEmpty())
        return 0;

    Accounts::Provider retnProv;
    Accounts::ProviderList providers = d->manager->providerList();
    foreach (const Accounts::Provider &p, providers) {
        if (p.name() == providerName) {
            retnProv = p;
            break;
        }
    }

    if (!retnProv.isValid())
        return 0;

    return new ProviderInterface(retnProv, parent);
}

/*!
    \qmlmethod Provider* AccountModel::provider(const QString &providerName, QObject *parent)
    Returns the Provider which provides the account identified by the given
    \a accountId, or zero if no such account exists.  The returned Provider
    will be owned by the specified \a parent.
 */
ProviderInterface *AccountModel::provider(int accountId, QObject *parent)
{
    Q_D(AccountModel);

    if (accountId == 0)
        return 0;

    for (int i = 0; i < d->accountsList.size(); ++i) {
        DisplayData *data = d->accountsList.at(i);
        int intAccountId = data->account->id();
        if (intAccountId == accountId) {
            return provider(data->account->providerName(), parent);
        }
    }

    return 0;
}

