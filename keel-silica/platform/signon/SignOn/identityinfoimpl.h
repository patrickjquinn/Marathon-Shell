// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */
/*!
 * @copyright Copyright (C) 2009-2011 Nokia Corporation.
 * @license LGPL
 */

#ifndef IDENTITYINFOIMPL_H
#define IDENTITYINFOIMPL_H

#include "QtCore/qglobal.h"
#include <QMap>
#include <QVariantMap>

#include "identityinfo.h"
#include "signond/signoncommon.h"

namespace SignOn {

typedef QMap<MethodName, MechanismsList> MethodMap;

/*!
 * @class IdentityInfoImpl
 * IdentityInfo class implementation.
 * @sa IdentityInfo
 */
class IdentityInfoImpl: public QVariantMap
{
    friend class IdentityInfo;
    friend class IdentityImpl;

public:
    IdentityInfoImpl();
    ~IdentityInfoImpl();

    void setId(quint32 id) { insert(SIGNOND_IDENTITY_INFO_ID, id); }
    quint32 id() const { return value(SIGNOND_IDENTITY_INFO_ID, 0).toUInt(); }

    void setUserName(const QString &userName) {
        insert(SIGNOND_IDENTITY_INFO_USERNAME, userName);
    }

    QString userName() const {
        return value(SIGNOND_IDENTITY_INFO_USERNAME).toString();
    }

    void setCaption(const QString &caption) {
        insert(SIGNOND_IDENTITY_INFO_CAPTION, caption);
    }

    QString caption() const {
        return value(SIGNOND_IDENTITY_INFO_CAPTION).toString();
    }

    void setMethods(const MethodMap &methods) {
        insert(SIGNOND_IDENTITY_INFO_AUTHMETHODS, QVariant::fromValue(methods));
    }

    MethodMap methods() const {
        return value(SIGNOND_IDENTITY_INFO_AUTHMETHODS).value<MethodMap>();
    }

    void setRealms(const QStringList &realms) {
        insert(SIGNOND_IDENTITY_INFO_REALMS, realms);
    }

    QStringList realms() const {
        return value(SIGNOND_IDENTITY_INFO_REALMS).toStringList();
    }

    void setOwners(const QStringList &owners) {
        insert(SIGNOND_IDENTITY_INFO_OWNER, owners);
    }

    QStringList owners() const {
        return value(SIGNOND_IDENTITY_INFO_OWNER).toStringList();
    }

    void setAccessControlList(const SecurityContextList &accessControlList) {
        insert(SIGNOND_IDENTITY_INFO_ACL, QVariant::fromValue(accessControlList));
    }

    SecurityContextList accessControlList() const {
        return value(SIGNOND_IDENTITY_INFO_ACL).value<SecurityContextList>();
    }

    void setSecret(const QString &secret) {
        insert(SIGNOND_IDENTITY_INFO_SECRET, secret);
    }

    QString secret() const {
        return value(SIGNOND_IDENTITY_INFO_SECRET).toString();
    }

    void setStoreSecret(bool storeSecret) {
        insert(SIGNOND_IDENTITY_INFO_STORESECRET, storeSecret);
    }

    bool storeSecret() const {
        return value(SIGNOND_IDENTITY_INFO_STORESECRET).toBool();
    }

    void updateMethod(const MethodName &method,
                      const MechanismsList &mechanismsList);
    void removeMethod(const MethodName &method);

    void setType(IdentityInfo::CredentialsType type) {
        insert(SIGNOND_IDENTITY_INFO_TYPE, quint32(type));
    }

    IdentityInfo::CredentialsType type() const {
        quint32 typeUInt = value(SIGNOND_IDENTITY_INFO_TYPE).toUInt();
        return IdentityInfo::CredentialsType(typeUInt);
    }

    qint32 refCount() const {
        return value(SIGNOND_IDENTITY_INFO_REFCOUNT).toInt();
    }

    bool hasMethod(const MethodName &method) const;
    QVariantMap toMap() const { return *this; }
    void updateFromMap(const QVariantMap &map);
};

} //namespace SignOn

Q_DECLARE_METATYPE(SignOn::MethodMap)

#endif // IDENTITYINFOIMPL_H
