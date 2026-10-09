// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
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

#include "auth-data.h"
#include "utils.h"

#undef signals
#include <libaccounts-glib.h>
#include <QtDebug>
#include <QtGlobal>


using namespace Accounts;

namespace Accounts {
/*!
 * @class AuthData
 * @headerfile auth-data.h Accounts/AuthData
 *
 * @brief Information for account authentication.
 *
 * @details The AuthData class holds information on the authentication
 * parameters used by an account. It is an implicitly shared object which can
 * be created with the AccountService::authData method.
 */
}; // namespace

AuthData::AuthData(AgAuthData *authData):
    m_authData(ag_auth_data_ref(authData))
{
}

/*!
 * Copy constructor. Copying an AuthData object is very cheap, because the data
 * is shared among copies.
 */
AuthData::AuthData(const AuthData &other):
    m_authData(ag_auth_data_ref(other.m_authData))
{
}

/*!
 * Destructor.
 */
AuthData::~AuthData()
{
    ag_auth_data_unref(m_authData);
    m_authData = nullptr;
}

/*!
 * @return The ID of the credentials associated with this account.
 */
uint AuthData::credentialsId() const
{
    return ag_auth_data_get_credentials_id(m_authData);
}

/*!
 * Get the authentication method which must be used when logging in with this
 * account.
 * @return The authentication method.
 */
QString AuthData::method() const
{
    return UTF8(ag_auth_data_get_method(m_authData));
}

/*!
 * Get the authentication mechanism which must be used when logging in with
 * this account.
 * @return The authentication mechanism.
 */
QString AuthData::mechanism() const
{
    return UTF8(ag_auth_data_get_mechanism(m_authData));
}

/*!
 * Get the dictionary of authentication parameters which must be used when
 * logging in with this account.
 * @return The authentication parameters.
 */
QVariantMap AuthData::parameters() const
{
    GVariant *glibParameters;

    glibParameters = ag_auth_data_get_login_parameters(m_authData, NULL);
    if (glibParameters == nullptr) return QVariantMap();

    QVariant variant = gVariantToQVariant(glibParameters);
    g_variant_unref(glibParameters);
    if (!variant.isValid()) return QVariantMap();

    return variant.toMap();
}
