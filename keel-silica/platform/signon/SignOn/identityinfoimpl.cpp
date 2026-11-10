// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2011-2016 Canonical Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2011-2016 Canonical Ltd.
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
#include "debug.h"
#include "identityinfoimpl.h"
#include "identityinfo.h"
#include "securitycontext.h"
#include "securitycontextpriv.h"

#include <QDBusMetaType>
#include <QVariant>
#include <QVariantMap>

namespace SignOn {

IdentityInfoImpl::IdentityInfoImpl():
    QVariantMap()
{
    qDBusRegisterMetaType<SignOn::MethodMap>();
    qDBusRegisterMetaType<SignOn::SecurityContextList>();
}

IdentityInfoImpl::~IdentityInfoImpl()
{
}

void IdentityInfoImpl::updateMethod(const MethodName &method,
                                    const MechanismsList &mechanismsList)
{
    MethodMap methodMap = methods();
    methodMap.insert(method, mechanismsList);
    setMethods(methodMap);
}

void IdentityInfoImpl::removeMethod(const MethodName &method)
{
    MethodMap methodMap = methods();
    if (methodMap.contains(method)) {
        methodMap.remove(method);
        setMethods(methodMap);
    }
}

bool IdentityInfoImpl::hasMethod(const MethodName &method) const
{
    return methods().contains(method);
}

void IdentityInfoImpl::updateFromMap(const QVariantMap &map)
{
    clear();
    /* We just need to expand any QDBusArguments which might be present, since
     * the map is likely to be coming from QDBus. */
    QVariantMap::const_iterator i;
    for (i = map.constBegin(); i != map.constEnd(); i++) {
        if (qstrcmp(i.value().typeName(), "QDBusArgument") == 0) {
            QDBusArgument container = i.value().value<QDBusArgument>();

            if (i.key() == SIGNOND_IDENTITY_INFO_AUTHMETHODS) {
                MethodMap methodMap = qdbus_cast<MethodMap>(container);
                setMethods(methodMap);
            } else if (i.key() == SIGNOND_IDENTITY_INFO_ACL) {
                SecurityContextList list = qdbus_cast<SecurityContextList>(container);
                setAccessControlList(list);
            } else {
                BLAME() << "Found unsupported QDBusArgument in key" << i.key();
            }
        } else {
            insert(i.key(), i.value());
        }
    }
}

} //namespace SignOn
