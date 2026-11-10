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
#include "account-provider-model.h"
#include "providerinterface.h"

//Qt
#include <QDebug>
#include <QStringList>
#include <QDir>
#include <QPointer>
#include <QCoreApplication>
#include <QMap>
#include <QtAlgorithms>

//libaccounts-qt
#include <Accounts/Manager>

class AccountProviderModel::AccountProviderModelPrivate
{
public:
    ~AccountProviderModelPrivate() {}
    QList<Accounts::Provider> providerList;
    QHash<int, QByteArray> headerData;
};

static QString retrieveDescription(const Accounts::Provider &provider)
{
    QDomElement root = provider.domDocument().documentElement();
    QDomElement descriptionElement = root.firstChildElement("description");
    if (!descriptionElement.text().isEmpty())
        return descriptionElement.text();
    else
        return QString();
}

AccountProviderModel::AccountProviderModel(QObject* parent)
    : QAbstractTableModel(parent)
    , d_ptr(new AccountProviderModelPrivate())
{
    Q_D(AccountProviderModel);

    d->headerData.insert(ProviderNameRole, "providerName");
    d->headerData.insert(ProviderDisplayNameRole, "providerDisplayName");
    d->headerData.insert(ProviderDescriptionRole, "providerDescription" );
    d->headerData.insert(ProviderIconRole, "providerIcon");
    d->headerData.insert(ColumnCountRole, "columncount");

#if QT_VERSION < QT_VERSION_CHECK(5, 0, 0)
    setRoleNames(d->headerData);
#endif
    Accounts::Manager m;
    Accounts::ServiceList allServices = m.serviceList(); // force reload of service files.
    Accounts::ProviderList providers = m.providerList();

    for (int i = 0; i < providers.size(); i++)
    {
        QDomDocument domDocument = providers[i].domDocument();
        d->providerList << providers[i];
    }
}

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
QHash<int, QByteArray> AccountProviderModel::roleNames() const
{
    Q_D(const AccountProviderModel);
    return d->headerData;
}
#endif

QVariant AccountProviderModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    Q_D(const AccountProviderModel);

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


AccountProviderModel::~AccountProviderModel()
{
    Q_D(AccountProviderModel);

    delete d;
}

QDomDocument AccountProviderModel::domDocument(const QModelIndex& currentIndex)
{
    Q_D(AccountProviderModel);

    if (!currentIndex.isValid() || currentIndex.row() >= d->providerList.length())
        return QDomDocument();

    Accounts::Provider provider = d->providerList.at(currentIndex.row());
    if (!provider.isValid())
        return QDomDocument();

    return provider.domDocument();
}


QModelIndex AccountProviderModel::index(int row, int column, const QModelIndex& parent) const
{

    if (row < 0 || column < 0 || !hasIndex(row, column, parent))
        return QModelIndex();

    return createIndex(row, column);
}

int AccountProviderModel::rowCount(const QModelIndex& parent) const
{
    Q_D(const AccountProviderModel);
    if (parent.isValid())
        return 0;
    return d->providerList.count();
}

int AccountProviderModel::columnCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return ColumnCount;
}

QVariant AccountProviderModel::data(const QModelIndex& index, int role) const
{
    Q_D(const AccountProviderModel);
    if (!index.isValid() || index.row() >= d->providerList.length())
        return QVariant();

    Accounts::Provider provider = d->providerList.at(index.row());
    if (!provider.isValid())
        return QVariant();

    if (role == ProviderNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderNameColumn))
        return provider.name();

    if (role == ProviderDisplayNameRole ||
            (role == Qt::DisplayRole && index.column() == ProviderDisplayNameColumn))
        return provider.displayName();

    if (role == ProviderDescriptionRole ||
        (role == Qt::DisplayRole && index.column() == ProviderDescriptionColumn))
        return retrieveDescription(provider);

    if (role == ProviderIconRole ||
            (role == Qt::DisplayRole && index.column() == ProviderIconColumn))
        return provider.iconName();

    return QVariant();
}

ProviderInterface *AccountProviderModel::provider(const QString &providerName, QObject *parent)
{
    Q_D(AccountProviderModel);

    Accounts::Provider retnProvider;
    foreach (const Accounts::Provider &p, d->providerList) {
        if (p.name() == providerName) {
            retnProvider = p;
            break;
        }
    }

    if (!retnProvider.isValid())
        return 0;

    QObject *pp = parent == 0 ? this : parent;
    return new ProviderInterface(retnProvider, pp);
}

Q_DECLARE_METATYPE(Accounts::Provider)
