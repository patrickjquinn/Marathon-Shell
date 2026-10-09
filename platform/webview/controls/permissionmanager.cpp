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

#include "permissionmanager.h"
#include "permissionmodel.h"
#include "keelwebenginelink.h" // Modified by Shipwright for Keel: WebEngine through the QML engine

PermissionManager::PermissionManager(QObject *parent)
    : QObject(parent)
{
    // Modified by Shipwright for Keel: through the QML engine (the plugin
    // resolves the WebEngine singleton when it creates this one).
    KeelWebEngineLink::addObserver(QStringLiteral("embed:perms:all"));
    KeelWebEngineLink::addObserver(QStringLiteral("embed:perms:all-for-uri"));
}

void PermissionManager::add(const Permission &permission)
{
    sendRequest(QStringLiteral("add"),
                permission.m_host,
                permission.m_type,
                permission.m_capability,
                permission.m_expireType);
}

void PermissionManager::remove(const QString &host, const QString &type)
{
    sendRequest(QStringLiteral("remove"), host, type);
}

void PermissionManager::add(const QString &host,
                            const QString &type,
                            Capability capability,
                            Expiration expireType)
{
    add(Permission(host, type, capability, expireType));
}

void PermissionManager::sendRequest(const QString &message,
                                    const QString &host,
                                    const QString &type,
                                    Capability capability,
                                    Expiration expireType)
{
    QVariantMap data;
    data.insert(QStringLiteral("msg"), message);
    data.insert(QStringLiteral("uri"), host);
    data.insert(QStringLiteral("type"), type);
    data.insert(QStringLiteral("permission"), QVariant::fromValue(capabilityToInt(capability)));
    data.insert(QStringLiteral("expireType"), QVariant::fromValue(expirationToInt(expireType)));
    KeelWebEngineLink::notifyObservers(QStringLiteral("embedui:perms"), QVariant(data)); // Modified by Shipwright for Keel
}

int PermissionManager::capabilityToInt(PermissionManager::Capability capability)
{
    return static_cast<int>(capability);
}

PermissionManager::Capability PermissionManager::intToCapability(int value)
{
    return static_cast<Capability>(value);
}

int PermissionManager::expirationToInt(PermissionManager::Expiration expireType)
{
    return static_cast<int>(expireType);
}

PermissionManager::Expiration PermissionManager::intToExpiration(int value)
{
    return static_cast<Expiration>(value);
}
