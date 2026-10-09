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

#include <QDBusMetaType>

#include "debug.h"
#include "identityimpl.h"
#include "identity.h"
#include "securitycontext.h"
#include "securitycontextpriv.h"

namespace SignOn {

Identity::Identity(const quint32 id, QObject *parent):
    QObject(parent)
{
    initDebug();

    qRegisterMetaType<Error>("SignOn::Error");
    qRegisterMetaType<Error>("Error");
    qDBusRegisterMetaType<SecurityContext>();

    if (qMetaTypeId<Error>() < QMetaType::User)
        BLAME() << "Identity::Identity() - "
            "SignOn::Error meta type not registered.";

    impl = new IdentityImpl(this, id);
}

Identity *Identity::newIdentity(const IdentityInfo &info, QObject *parent)
{
    Identity *identity = new Identity(SSO_NEW_IDENTITY, parent);
    identity->impl->copyInfo(info);
    return identity;
}

Identity *Identity::existingIdentity(const quint32 id, QObject *parent)
{
    if (id == 0)
        return NULL;
    return new Identity(id, parent);
}

Identity::~Identity()
{
}

quint32 Identity::id() const
{
    return impl->id();
}

void Identity::queryAvailableMethods()
{
    impl->queryAvailableMethods();
}

AuthSessionP Identity::createSession(const QString &methodName)
{
    if (methodName.isEmpty())
        return NULL;

    return AuthSessionP(impl->createSession(methodName, this));
}

void Identity::destroySession(const AuthSessionP &session)
{
    if (session.isNull())
        return;

    impl->destroySession(session.data());
}

void Identity::requestCredentialsUpdate(const QString &message)
{
    impl->requestCredentialsUpdate(message);
}

void Identity::storeCredentials(const IdentityInfo &info)
{
    impl->storeCredentials(info);
}

void Identity::remove()
{
    impl->remove();
}

void Identity::addReference(const QString &reference)
{
    impl->addReference(reference);
}

void Identity::removeReference(const QString &reference)
{
    impl->removeReference(reference);
}

void Identity::queryInfo()
{
    impl->queryInfo();
}

void Identity::verifyUser(const QString &message)
{
    impl->verifyUser(message);
}

void Identity::verifyUser(const QVariantMap &params)
{
    impl->verifyUser(params);
}

void Identity::verifySecret(const QString &secret)
{
    impl->verifySecret(secret);
}

void Identity::signOut()
{
    impl->signOut();
}

} //namespace SignOn
