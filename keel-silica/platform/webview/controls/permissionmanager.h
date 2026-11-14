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

#ifndef PERMISSIONMANAGER_H
#define PERMISSIONMANAGER_H

#include <QObject>

class Permission;

class PermissionManager : public QObject
{
    Q_OBJECT
public:
    PermissionManager(QObject *parent = nullptr);

    // See https://developer.mozilla.org/en-US/docs/Mozilla/Tech/XPCOM/Reference/Interface/nsIPermissionManager
    // And https://git.sailfishos.org/mer-core/gecko-dev/blob/master/netwerk/base/nsIPermissionManager.idl
    enum Capability {
        Unknown = 0,
        Allow = 1,
        Deny = 2,
        Prompt = 3
    };
    Q_ENUM(Capability)

    enum Expiration {
        Never = 0,
        Session = 1,
        Time = 2
    };
    Q_ENUM(Expiration)

    /* Add host to exclusion list. The type property can be "geolocation", "cookie",
     * "desktop-notification", "popup", etc. */
    Q_INVOKABLE void add(const QString &host,
                         const QString &type,
                         Capability capability,
                         Expiration expireType = Never);

    // Create a PermissionManager object before using the PermissionModel
    Q_INVOKABLE void instance() {}

    static void add(const Permission &permission);
    static void remove(const QString &host, const QString &type);
    static void sendRequest(const QString &message,
                            const QString &host = QString(),
                            const QString &type = QString(),
                            Capability capability = Unknown,
                            Expiration expireType = Never);

    static int capabilityToInt(Capability capability);
    static Capability intToCapability(int value);

    static int expirationToInt(Expiration expireType);
    static Expiration intToExpiration(int value);
};

#endif // PERMISSIONMANAGER_H
