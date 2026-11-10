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

#ifndef PERMISSIONMODEL_H
#define PERMISSIONMODEL_H

#include <QAbstractListModel>
#include <QQmlParserStatus>

#include "permissionmanager.h"

struct Permission
{
    Permission(QString host,
               QString type,
               PermissionManager::Capability capability,
               PermissionManager::Expiration expireType = PermissionManager::Never,
               int expireTime = 0)
        : m_host(host)
        , m_type(type)
        , m_capability(capability)
        , m_expireType(expireType)
        , m_expireTime(expireTime)
    {
    }

    bool operator==(const Permission &other) const
    {
        return (m_host == other.m_host
                && m_type == other.m_type
                && m_capability == other.m_capability
                && m_expireType == other.m_expireType
                && m_expireTime == other.m_expireTime);
    }

    bool operator!=(const Permission &other) const
    {
        return !(*this == other);
    }

    QString m_host;
    QString m_type;
    PermissionManager::Capability m_capability;
    PermissionManager::Expiration m_expireType;
    int m_expireTime;
};

class PermissionModel : public QAbstractListModel, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        Uri = Qt::UserRole,
        Type,
        Capability,
        ExpireType,
        ExpireTime
    };

    PermissionModel(QObject *parent = nullptr);

    // If the user hasn't set host, then you should request for all possible permissions.
    // It is better to do it after we have made sure that all bindings are initialized.
    void classBegin() override;
    void componentComplete() override;

    // Add host to exclusion list. The type property can be "geolocation", "cookie",
    // "desktop-notification", "popup", etc.
    Q_INVOKABLE void add(const QString &host, const QString &type, int capability);
    Q_INVOKABLE void setCapability(QModelIndex index, int capability);

    // Remove all items from model for permission type.
    // It can be "geolocation", "cookie", "popup", etc
    Q_INVOKABLE void removeAllForPermissionType(const QString &type);

    void remove(int index);
    void remove(const Permission &permission);

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString host() const;
    void setHost(const QString &host);

signals:
    void hostChanged(const QString &host);
    void countChanged();

private slots:
    void setPermissionList(const QVariantList &data);
    void requestPermissions(const QString &host);

    void handleRecvObserve(const QString &message, const QVariant &data);

private:
    QList<Permission> m_permissionList;
    QString m_host;
};

#endif // PERMISSIONMODEL_H
