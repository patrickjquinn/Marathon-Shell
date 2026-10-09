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
#include "authservice.h"
#include "authserviceimpl.h"
#include "debug.h"

namespace SignOn {

AuthService::AuthService(QObject *parent): QObject(parent),
    impl(new AuthServiceImpl(this))
{
    initDebug();

    qRegisterMetaType<Error>("SignOn::Error");
    qRegisterMetaType<Error>("Error");

    if (qMetaTypeId<Error>() < QMetaType::User)
        BLAME() << "AuthService::AuthService() - "
            "SignOn::Error meta type not registered.";
}

AuthService::~AuthService()
{
}

void AuthService::queryMethods()
{
    impl->queryMethods();
}

void AuthService::queryMechanisms(const QString &method)
{
    impl->queryMechanisms(method);
}

void AuthService::queryIdentities(const IdentityFilter &filter)
{
    impl->queryIdentities(filter);
}

void AuthService::clear()
{
    impl->clear();
}

} //namespace SignOn
