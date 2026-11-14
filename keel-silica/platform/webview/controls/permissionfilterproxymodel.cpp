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

#include "permissionfilterproxymodel.h"
#include "permissionmodel.h"
#include "permissionmanager.h"

PermissionFilterProxyModel::PermissionFilterProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_onlyPermanent(false)
{

}

void PermissionFilterProxyModel::add(const QString &host, const QString &type, int capability)
{
    PermissionModel *permissionModel = qobject_cast<PermissionModel *>(sourceModel());
    if (!permissionModel) {
        return;
    }

    permissionModel->add(host, type, capability);
}

void PermissionFilterProxyModel::remove(const QString &host, const QString &type, int capability)
{
    PermissionModel *permissionModel = qobject_cast<PermissionModel *>(sourceModel());
    if (!permissionModel) {
        return;
    }

    permissionModel->remove(Permission(host, type, PermissionManager::intToCapability(capability)));
}

void PermissionFilterProxyModel::setCapability(int currentIndex, int capability)
{
    QModelIndex proxyIndex = index(currentIndex, 0);
    QModelIndex sourceIndex = mapToSource(proxyIndex);

    PermissionModel *permissionModel = qobject_cast<PermissionModel *>(sourceModel());
    if (!permissionModel) {
        return;
    }

    permissionModel->setCapability(sourceIndex, capability);
}

bool PermissionFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);

    if (onlyPermanent()) {
        int expireType = sourceModel()->data(index, PermissionModel::ExpireType).toInt();
        if (PermissionManager::intToExpiration(expireType) != PermissionManager::Never) {
            return false;
        }
    }

    if (permissionType().isEmpty()) {
        return true;
    }

    if (sourceModel()->data(index, PermissionModel::Type).toString() == permissionType()) {
        return true;
    }
    return false;
}

QString PermissionFilterProxyModel::permissionType() const
{
    return m_permissionType;
}

void PermissionFilterProxyModel::setPermissionType(const QString &permissionType)
{
    if (m_permissionType == permissionType) {
        return;
    }

    m_permissionType = permissionType;
    emit permissionTypeChanged(m_permissionType);
    invalidate();
}

bool PermissionFilterProxyModel::onlyPermanent() const
{
    return m_onlyPermanent;
}

void PermissionFilterProxyModel::setOnlyPermanent(bool onlyPermanent)
{
    if (m_onlyPermanent == onlyPermanent) {
        return;
    }

    m_onlyPermanent = onlyPermanent;
    emit onlyPermanentChanged(m_onlyPermanent);
    invalidate();
}
