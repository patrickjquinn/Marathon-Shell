// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2012 Canonical Ltd.
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
/*!
 * @copyright Copyright (C) 2012 Canonical Ltd.
 * @license LGPL
 */

#ifndef ACCOUNTS_AUTH_DATA_H
#define ACCOUNTS_AUTH_DATA_H

#include "Accounts/accountscommon.h"

#include <QString>
#include <QVariantMap>

extern "C"
{
    typedef struct _AgAuthData AgAuthData;
}

/*!
 * @namespace Accounts
 */
namespace Accounts
{

class AccountService;

class ACCOUNTS_EXPORT AuthData
{
public:
    AuthData(const AuthData &other);
    virtual ~AuthData();

    uint credentialsId() const;

    QString method() const;

    QString mechanism() const;

    QVariantMap parameters() const;

private:
    // Don't include private data in docs: \cond
    friend class AccountService;
    AuthData(AgAuthData *authData);

    AgAuthData *m_authData;
    // \endcond
};

} // namespace

#endif // ACCOUNTS_AUTH_DATA_H
