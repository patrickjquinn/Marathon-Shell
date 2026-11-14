// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd.  <chris.adams@jollamobile.com>
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
#include <algorithm> // Modified by Shipwright for Qt 6
#include "service-account-model.h"
#include "serviceaccountinterface.h"
#include "providerinterface.h"

//Qt
#include <QtDebug>

//libaccounts-qt
#include <Accounts/Manager>
#include <Accounts/Account>
#include <Accounts/Provider>

struct DisplayData {
    DisplayData(Accounts::AccountService *acct) : account(acct), enabledWithService(false) {}
    ~DisplayData() { delete account; }
    Accounts::AccountService *account;
    QString providerName;
    QString providerDisplayName;
    QString accountIcon;
    QString serviceName;
    QString serviceDisplayName;
    QString serviceIcon;
    bool enabledWithService;
    Q_DISABLE_COPY(DisplayData);
};

class ServiceAccountModel::ServiceAccountModelPrivate
{
public:
    ~ServiceAccountModelPrivate()
    {
        qDeleteAll(accountsList);
    }

    QHash<int, QByteArray> headerData;
    Accounts::Manager *manager;
    QList<DisplayData *> accountsList;
};

ServiceAccountModel::ServiceAccountModel(QObject* parent)
    : QAbstractListModel(parent)
    , d_ptr(new ServiceAccountModelPrivate())
{
    Q_D(ServiceAccountModel);
    d->manager = new Accounts::Manager();
    Accounts::ServiceList allServices = d->manager->serviceList(); // force reload of service files.
    d->headerData.insert(AccountIdRole, "accountId");
    d->headerData.insert(AccountDisplayNameRole, "accountDisplayName");
    d->headerData.insert(AccountIconRole, "accountIcon" );
    d->headerData.insert(ServiceNameRole, "serviceName");
    d->headerData.insert(ServiceDisplayNameRole, "serviceDisplayName");
    d->headerData.insert(ServiceIconRole, "serviceIcon" );
    d->headerData.insert(ProviderNameRole, "providerName");
    d->headerData.insert(ProviderDisplayNameRole, "providerDisplayName");
    d->headerData.insert(EnabledWithServiceRole, "enabledWithService");
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
        connect(account, SIGNAL(displayNameChanged(QString)),
                this, SLOT(accountDisplayNameChanged()));
        Accounts::ServiceList accountServices = account->services();
        foreach (const Accounts::Service &srv, accountServices) {
            Accounts::AccountService *srvAcc = new Accounts::AccountService(account, srv);
            d->accountsList.append(new DisplayData(srvAcc));
        }
    }
}

ServiceAccountModel::~ServiceAccountModel()
{
}

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
QHash<int, QByteArray> ServiceAccountModel::roleNames() const
{
    Q_D(const ServiceAccountModel);
    return d->headerData;
}
#endif

int ServiceAccountModel::rowCount(const QModelIndex &parent) const
{
    Q_D(const ServiceAccountModel);
    if (parent.isValid())
        return 0;
    return d->accountsList.length();
}

int ServiceAccountModel::columnCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return ColumnCount;
}

QVariant ServiceAccountModel::data(const QModelIndex &index, int role) const
{
    Q_D(const ServiceAccountModel);
    if (!index.isValid() || index.row() >= d->accountsList.length())
        return QVariant();

    DisplayData *data = d->accountsList[index.row()];
    Accounts::AccountService *account = data->account;

    if (!account || !account->account()) {
        // When this occurs, it means that the accounts db is out of sync with
        // our local data structure (perhaps due to not receiving a removed() signal).
        qWarning() << Q_FUNC_INFO << "Invalid account at row" << index.row();
        return QVariant();
    }

    if (role == AccountIdRole ||
            (role == Qt::DisplayRole && index.column() == AccountIdColumn))
        return QVariant::fromValue(account->account()->id());

    if (role == AccountDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == AccountDisplayNameColumn))
        return QVariant::fromValue(account->account()->displayName());

    if (role == AccountIconRole ||
            (role == Qt::DisplayRole && index.column() == AccountIconColumn)) {
        if (data->accountIcon.isNull()) {
            Accounts::Provider provider = d->manager->provider(account->account()->providerName());
            data->accountIcon = provider.iconName();
        }
        return QVariant::fromValue(data->accountIcon);
    }

    if (role == ServiceNameRole ||
            (role == Qt::DisplayRole && index.column() == ServiceNameColumn)) {
        data->serviceName = account->service().name();
        return QVariant::fromValue(data->serviceName);
    }

    if (role == ServiceDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == ServiceDisplayNameColumn)) {
        data->serviceDisplayName = account->service().displayName();
        return QVariant::fromValue(data->serviceDisplayName);
    }

    if (role == ServiceIconRole ||
            (role == Qt::DisplayRole && index.column() == ServiceIconColumn)) {
        if (data->serviceIcon.isNull())
            data->serviceIcon = account->service().iconName();
        return QVariant::fromValue(data->serviceIcon);
    }

    if (role == ProviderNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderNameColumn)) {
        Accounts::Provider provider = d->manager->provider(account->account()->providerName());
        data->providerName = provider.name();
        return QVariant::fromValue(data->providerName);
    }

    if (role == ProviderDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderDisplayNameColumn)) {
        Accounts::Provider provider = d->manager->provider(account->account()->providerName());
        data->providerDisplayName = provider.displayName();
        return QVariant::fromValue(data->providerDisplayName);
    }

    if (role == EnabledWithServiceRole ||
            (role == Qt::DisplayRole && index.column() == EnabledWithServiceColumn)) {
        data->enabledWithService = account->enabled();
        return QVariant::fromValue(data->enabledWithService);
    }

    return QVariant();
}

QVariant ServiceAccountModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    Q_D(const ServiceAccountModel);
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

void ServiceAccountModel::accountCreated(Accounts::AccountId id)
{
    Q_D(ServiceAccountModel);
    QModelIndex index;
    Accounts::Account *account = d->manager->account(id);

    if (account != 0) {
        Accounts::ServiceList srvList = account->services();
        int count = srvList.size();
        beginInsertRows(index, 0, count - 1);
        for (int i = 0; i < count; ++i) {
            Accounts::AccountService *accSrv = new Accounts::AccountService(account, srvList.at(i));
            d->accountsList.insert(0, new DisplayData(accSrv));
        }
        endInsertRows();
    }
}

void ServiceAccountModel::accountRemoved(Accounts::AccountId id)
{
    Q_D(ServiceAccountModel);

    QList<int> indexes = getAccountIndexes(id);
    if (!indexes.size()) {
        qWarning() << Q_FUNC_INFO << "Account not present in the list:" << id;
        return;
    }

    QModelIndex parent;
    QList<DisplayData *> cleanupList;

    // remove them in contiguous chunks if possible.
    std::sort(indexes.begin(), indexes.end()); // Modified by Shipwright for Qt 6: qSort() is gone.
    int maxIdx = indexes.last();
    int firstIdx = indexes.first();
    int lastIdx = firstIdx;
    int which = 0;
    while (lastIdx < maxIdx) {
        int currIdx = indexes.at(++which);
        if (currIdx == (lastIdx + 1)) {
            // contiguous
            lastIdx += 1;
        } else {
            // noncontiguous.  Remove the chunk.
            beginRemoveRows(parent, firstIdx, lastIdx);
            for (int i = firstIdx; i < lastIdx; ++i) {
                DisplayData *data = d->accountsList[i];
                d->accountsList.removeAt(i);
                cleanupList.append(data);
            }
            endRemoveRows();
            qDeleteAll(cleanupList);
            cleanupList.clear();

            // prepare for next chunk.
            firstIdx = currIdx;
            lastIdx = currIdx;
        }
    }

    // remove the last (or possibly only) chunk
    beginRemoveRows(parent, firstIdx, lastIdx);
    for (int i = firstIdx; i <= lastIdx; ++i)
        cleanupList.append(d->accountsList.at(i));
    foreach (DisplayData *data, cleanupList)
        d->accountsList.removeOne(data);
    endRemoveRows();
    qDeleteAll(cleanupList);
}

void ServiceAccountModel::accountUpdated(Accounts::AccountId id)
{
    QList<int> indexes = getAccountIndexes(id);
    if (!indexes.size()) {
        qWarning() << Q_FUNC_INFO << "Account not present in the list:" << id;
        return;
    }

    // emit change signals for contiguous chunks
    std::sort(indexes.begin(), indexes.end()); // Modified by Shipwright for Qt 6: qSort() is gone.
    int maxIdx = indexes.last();
    int firstIdx = indexes.first();
    int lastIdx = firstIdx;
    int which = 0;
    while (lastIdx < maxIdx) {
        int currIdx = indexes.at(++which);
        if (currIdx == (lastIdx + 1)) {
            // contiguous
            lastIdx += 1;
        } else {
            // noncontiguous.  Emit change signal for the chunk.
            emit dataChanged(index(firstIdx, 0), index(lastIdx, 0));

            // prepare for next chunk.
            firstIdx = currIdx;
            lastIdx = currIdx;
        }
    }

    // emit change signal for the last (or possibly only) chunk
    emit dataChanged(index(firstIdx, 0), index(lastIdx, 0));
}

void ServiceAccountModel::accountDisplayNameChanged()
{
    Accounts::Account *account = qobject_cast<Accounts::Account*>(sender());
    if (account)
        accountUpdated(account->id());
}

// Each Account can be represented multiple times in the list (as it may support multiple services)
QList<int> ServiceAccountModel::getAccountIndexes(Accounts::AccountId id) const
{
    Q_D(const ServiceAccountModel);
    QList<int> indexes;
    for (int i = 0; i < d->accountsList.count(); ++i) {
        if (!d->accountsList.at(i)->account->account()) {
            // the account has been removed, and our local datastructure is out of sync with the accounts db.
            continue;
        } else if (d->accountsList.at(i)->account->account()->id() == id) {
            indexes.append(i);
        }
    }
    return indexes;
}

/*!
    \qmltype ServiceAccountModel
    \instantiates ServiceAccountModel
    \inqmlmodule org.nemomobile.accounts 1
    \brief Provides a model of existing per-service accounts

    The ServiceAccountModel can be used to provide service account data to a view.
    For each account in the database, it exposes:
    \list
    \li accountId
    \li accountDisplayName
    \li accountIcon
    \li serviceName
    \li serviceDisplayName
    \li serviceIcon
    \li providerName
    \li providerDisplayName
    \li enabledWithService
    \endlist

    It also provides invokable methods to retrieve a Provider
    associated with an account.
*/

/*!
    \qmlmethod Provider* ServiceAccountModel::provider(const QString &providerName, QObject *parent)
    Returns the Provider with the given \a providerName, or zero if no such
    provider exists.  The returned Provider will be owned by the specified
    \a parent.
 */
ProviderInterface *ServiceAccountModel::provider(const QString &providerName, QObject *parent)
{
    Q_D(ServiceAccountModel);

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
    \qmlmethod Provider* ServiceAccountModel::provider(const QString &providerName, QObject *parent)
    Returns the Provider which provides the account identified by the given
    \a accountId, or zero if no such account exists.  The returned Provider
    will be owned by the specified \a parent.
 */
ProviderInterface *ServiceAccountModel::provider(int accountId, QObject *parent)
{
    Q_D(ServiceAccountModel);

    if (accountId == 0)
        return 0;

    for (int i = 0; i < d->accountsList.size(); ++i) {
        DisplayData *data = d->accountsList.at(i);
        int intAccountId = data->account->account()->id();
        if (intAccountId == accountId) {
            return provider(data->account->account()->providerName(), parent);
        }
    }

    return 0;
}

