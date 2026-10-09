// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Modified by Shipwright for Keel (marked at the changes).
/****************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "permissionmodel.h"
#include "keelwebenginelink.h" // Modified by Shipwright for Keel: WebEngine through the QML engine

static const auto PERMS_ALL = QStringLiteral("embed:perms:all");
static const auto PERMS_ALL_FOR_URI = QStringLiteral("embed:perms:all-for-uri");

/*
 * The model stores a list of permissions for the host(m_host).
 * If host is empty, the model will have all hosts with permissions.
 * It has no watcher(real-time update), so please,
 * don't use PermissionManager::add() and PermissionManager::remove()
 * methods outside for this model.
*/
PermissionModel::PermissionModel(QObject *parent)
    : QAbstractListModel(parent)
{
    // Modified by Shipwright for Keel: connected to WebEngine in classBegin(),
    // where the QML engine that has it is known.
    connect(this, &PermissionModel::hostChanged, this, &PermissionModel::requestPermissions);
}

void PermissionModel::classBegin()
{
    // Modified by Shipwright for Keel: WebEngine through the QML engine.
    if (QObject *webEngine = KeelWebEngineLink::instance(qmlEngine(this)))
        connect(webEngine, SIGNAL(recvObserve(QString,QVariant)), this, SLOT(handleRecvObserve(QString,QVariant)));
}

void PermissionModel::componentComplete()
{
    if (host().isEmpty()) {
        requestPermissions(host());
    }
}

void PermissionModel::add(const QString &host, const QString &type, int capability)
{
    int it = 0;
    for (const auto &perm : m_permissionList) {
        if (perm.m_host == host && perm.m_type == type) {
            setCapability(index(it), capability);
            return;
        }
        it++;
    }

    int count = m_permissionList.count();
    beginInsertRows(QModelIndex(), count, count);

    Permission permission(host, type, PermissionManager::intToCapability(capability));
    PermissionManager::add(permission);

    m_permissionList.append(permission);

    endInsertRows();
    emit countChanged();
}

QVariant PermissionModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_permissionList.count())
        return QVariant();

    switch (role) {
    case Uri:
        return m_permissionList.at(index.row()).m_host;
    case Type:
        return m_permissionList.at(index.row()).m_type;
    case Capability:
        return m_permissionList.at(index.row()).m_capability;
    case ExpireType:
        return m_permissionList.at(index.row()).m_expireType;
    case ExpireTime:
        return m_permissionList.at(index.row()).m_expireTime;
    default:
        return QVariant();
    }
}

int PermissionModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_permissionList.count();
}

QHash<int, QByteArray> PermissionModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[Uri] = "uri";
    roles[Type] = "type";
    roles[Capability] = "capability";
    roles[ExpireType] = "expireType";
    roles[ExpireTime] = "expireTime";
    return roles;
}

QString PermissionModel::host() const
{
    return m_host;
}

void PermissionModel::setHost(const QString &host)
{
    if (m_host == host) {
        return;
    }

    m_host = host;
    emit hostChanged(m_host);
}

void PermissionModel::handleRecvObserve(const QString &message, const QVariant &data)
{
    if (m_host.isEmpty() && message == PERMS_ALL_FOR_URI) {
        return;
    }

    if (!m_host.isEmpty() && message == PERMS_ALL) {
        return;
    }

    if (message == PERMS_ALL || message == PERMS_ALL_FOR_URI) {
        setPermissionList(qvariant_cast<QVariantList>(data));
    }
}

void PermissionModel::setPermissionList(const QVariantList &data)
{
    static const QStringList knownPermissions {
        QStringLiteral("geolocation"),
        QStringLiteral("cookie"),
        QStringLiteral("popup"),
        QStringLiteral("camera"),
        QStringLiteral("microphone"),
    };

    QList<Permission> permissions;

    for (const auto &iter : data) {
        QVariantMap varMap = iter.toMap();
        if (!knownPermissions.contains(varMap.value("type").toString()))
            continue;

        permissions.append(Permission(varMap.value("uri").toString(),
                                      varMap.value("type").toString(),
                                      PermissionManager::intToCapability(varMap.value("capability").toInt()),
                                      PermissionManager::intToExpiration(varMap.value("expireType").toInt())));
    }

    int startIndex = -1;
    for (int i = 0; i < permissions.count() && i < m_permissionList.count(); i++) {
        if (m_permissionList.at(i) != permissions.at(i)) {
            m_permissionList[i] = permissions.at(i);
            if (startIndex < 0) {
                startIndex = i;
            }
        } else if (startIndex >= 0) {
            emit dataChanged(index(startIndex), index(i - 1));
            startIndex = -1;
        }
    }

    if (startIndex >= 0) {
        emit dataChanged(index(startIndex), index(qMin(m_permissionList.count(), permissions.count()) - 1));
    }

    int difference = permissions.count() - m_permissionList.count();
    if (difference != 0) {
        if (difference < 0) {
            beginRemoveRows(QModelIndex(), permissions.count(), m_permissionList.count() - 1);
            m_permissionList.erase(m_permissionList.begin() + permissions.count(), m_permissionList.end());
            endRemoveRows();
        } else {
            beginInsertRows(QModelIndex(), m_permissionList.count(), permissions.count() - 1);
            m_permissionList.append(permissions.mid(m_permissionList.count()));
            endInsertRows();
        }
        emit countChanged();
    }
}

void PermissionModel::requestPermissions(const QString &host)
{
    if (host.isEmpty()) {
        PermissionManager::sendRequest(QStringLiteral("get-all"));
    } else {
        PermissionManager::sendRequest(QStringLiteral("get-all-for-uri"), host);
    }
}

void PermissionModel::remove(int index)
{
    beginRemoveRows(QModelIndex(), index, index);

    Permission permission = m_permissionList.at(index);
    PermissionManager::remove(permission.m_host, permission.m_type);
    m_permissionList.removeAt(index);

    endRemoveRows();
    emit countChanged();
}

void PermissionModel::remove(const Permission &permission)
{
    int index = 0;
    for (const auto &perm : m_permissionList) {
        if (perm == permission) {
            remove(index);
            return;
        }
        index++;
    }
}

void PermissionModel::setCapability(QModelIndex index, int capability)
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_permissionList.count()) {
        return;
    }

    Permission &permission = m_permissionList[index.row()];
    permission.m_capability = PermissionManager::intToCapability(capability);
    PermissionManager::add(permission);
    QVector<int> roles = {Capability};
    dataChanged(index, index, roles);
}

void PermissionModel::removeAllForPermissionType(const QString &type)
{
    QList<Permission> permissions;
    for (const auto &perm : m_permissionList) {
        if (perm.m_type == type) {
            permissions.append(perm);
        }
    }
    for (const auto &perm : permissions) {
        remove(perm);
    }
}
