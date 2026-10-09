// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef PERMISSIONFILTERPROXYMODEL_H
#define PERMISSIONFILTERPROXYMODEL_H

#include <QSortFilterProxyModel>

class PermissionFilterProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString permissionType READ permissionType WRITE setPermissionType NOTIFY permissionTypeChanged)
    Q_PROPERTY(bool onlyPermanent READ onlyPermanent WRITE setOnlyPermanent NOTIFY onlyPermanentChanged)

public:
    PermissionFilterProxyModel(QObject *parent = nullptr);

    Q_INVOKABLE void add(const QString &host, const QString &type, int capability);
    Q_INVOKABLE void remove(const QString &host, const QString &type, int capability);
    Q_INVOKABLE void setCapability(int currentIndex, int capability);

    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

    QString permissionType() const;
    void setPermissionType(const QString &permissionType);

    bool onlyPermanent() const;
    void setOnlyPermanent(bool onlyPermanent);

signals:
    void permissionTypeChanged(QString permissionType);
    void onlyPermanentChanged(bool onlyPermanent);

private:
    QString m_permissionType;
    bool m_onlyPermanent;
};

#endif // PERMISSIONFILTERPROXYMODEL_H
