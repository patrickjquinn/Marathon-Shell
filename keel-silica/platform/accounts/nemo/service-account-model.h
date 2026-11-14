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

#ifndef SERVICEACCOUNTMODEL_H
#define SERVICEACCOUNTMODEL_H

//accounts-qt
#include <Accounts/Manager>
#include <Accounts/AccountService>

//Qt
#include <QAbstractTableModel>
#include <QMap>
#include <QVariant>

class ServiceAccountInterface;
class ProviderInterface;
// Modified by Shipwright for Qt 6 (this copy builds for Qt 6 only): moc
// needs the complete pointer types.
Q_MOC_INCLUDE("providerinterface.h")

/*!
 * The Service Account Model is the model for per-service accounts
 */

class ServiceAccountModel : public QAbstractListModel
{
    Q_OBJECT
    class ServiceAccountModelPrivate;

public:

    enum Columns {
        AccountIdColumn,
        AccountDisplayNameColumn,
        AccountIconColumn,
        ServiceNameColumn,
        ServiceDisplayNameColumn,
        ServiceIconColumn,
        ProviderNameColumn,
        ProviderDisplayNameColumn,
        EnabledWithServiceColumn,
        ColumnCount
    };

    enum Roles{
        AccountIdRole = Qt::UserRole + 1,
        AccountDisplayNameRole,
        AccountIconRole,
        ServiceNameRole,
        ServiceDisplayNameRole,
        ServiceIconRole,
        ProviderNameRole,
        ProviderDisplayNameRole,
        EnabledWithServiceRole,
        ColumnCountRole
    };


    ServiceAccountModel(QObject *parent = 0);
    virtual ~ServiceAccountModel();

    int rowCount(const QModelIndex &index = QModelIndex()) const;
    int columnCount(const QModelIndex &index) const;
    QVariant data(const QModelIndex &index, int role) const;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role) const;

    Q_INVOKABLE ProviderInterface *provider(const QString &providerName, QObject *parent = 0);
    Q_INVOKABLE ProviderInterface *provider(int accountId, QObject *parent = 0);

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
protected:
    QHash<int, QByteArray> roleNames() const;
#endif

private slots:
    void accountCreated(Accounts::AccountId id);
    void accountRemoved(Accounts::AccountId id);
    void accountUpdated(Accounts::AccountId id);
    void accountDisplayNameChanged();

private:
    QList<int> getAccountIndexes(Accounts::AccountId id) const;

private:
    ServiceAccountModelPrivate* d_ptr;
    Q_DISABLE_COPY(ServiceAccountModel)
    Q_DECLARE_PRIVATE(ServiceAccountModel);
};
Q_DECLARE_METATYPE(Accounts::AccountService *)

#endif // SERVICEACCOUNTMODEL_H
