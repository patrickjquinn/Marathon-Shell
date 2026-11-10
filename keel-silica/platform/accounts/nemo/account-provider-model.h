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

#ifndef ACCOUNTPROVIDERMODEL_H
#define ACCOUNTPROVIDERMODEL_H

//accounts-qt
#include<Accounts/Manager>

//Qt
#include <QAbstractTableModel>
#include <QDomDocument>
#include <QString>

class ProviderInterface;
// Modified by Shipwright for Qt 6 (this copy builds for Qt 6 only): moc
// needs the complete pointer types.
Q_MOC_INCLUDE("providerinterface.h")

/*!
 * The AccountProviderModel is a model that creates list of available providers.
 * It fetches the provider xml and creates the list view
 */
class AccountProviderModel : public QAbstractTableModel
{
    Q_OBJECT
    class AccountProviderModelPrivate;

public:

    enum Columns{
        ProviderNameColumn,
        ProviderDisplayNameColumn,
        ProviderDescriptionColumn,
        ProviderIconColumn,
        ColumnCount
    };

    enum Roles{
        ProviderNameRole = Qt::UserRole + 1,
        ProviderDisplayNameRole,
        ProviderDescriptionRole,
        ProviderIconRole,
        ColumnCountRole
    };

    /*!
     * The Constructor
     */
    AccountProviderModel(QObject* parent = 0);

    /*!
     * The Destructor.
     */
    ~AccountProviderModel();

    /*!
     * To get the domDocument of the provider xml
     */
    QDomDocument domDocument(const QModelIndex& index);

    /*!
     *  Derived from QAbstractListModel - gives the number of rows in the model.
     */
    int rowCount( const QModelIndex & index = QModelIndex() ) const;

    /*!
     *  Derived from QAbstractListModel - gives the number of columns in the model.
     */
    int columnCount( const QModelIndex & index ) const;

    /*!
     *  Fetches data depending on the index and the role provided.
     */
    QVariant data( const QModelIndex &index, int role ) const;

    /*!
     *  Derived from QAbstractTableModel - provides QModelIndex
     */
    QModelIndex index( int row, int column, const QModelIndex &parent = QModelIndex() ) const;

    /*!
    *  Maps all the roles with a QString so that qmlList can access the model
    */
    QVariant headerData(int section, Qt::Orientation orientation, int role) const;

    /*!
     * Returns the Provider with the given name.  The returned Provider
     * will be owned by the specified \a parent or by the model if no parent
     * is specified.
     */
    Q_INVOKABLE ProviderInterface *provider(const QString &providerName, QObject *parent = 0);

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
protected:
    QHash<int, QByteArray> roleNames() const;
#endif

private:
    AccountProviderModelPrivate* d_ptr;
    Q_DISABLE_COPY(AccountProviderModel)
    Q_DECLARE_PRIVATE(AccountProviderModel);
};

#endif // ACCOUNTPROVIDERMODEL_H
