// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2011 Nokia Corporation.
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

#include "account.h"
#include "manager.h"

#include <QHash>
#include <QPointer>
#include <libaccounts-glib.h>

namespace Accounts {

class Manager::Private
{
    Q_DECLARE_PUBLIC(Manager)

public:
    Private():
        q_ptr(0),
        m_manager(0)
    {
    }

    ~Private() {
    }

    void init(Manager *q, AgManager *manager);

    mutable Manager *q_ptr;
    AgManager *m_manager; //real manager
    Error lastError;
    QHash<AccountId,QPointer<Account> > m_accounts;

    static void on_account_created(Manager *self, AgAccountId id);
    static void on_account_deleted(Manager *self, AgAccountId id);
    static void on_account_updated(Manager *self, AgAccountId id);
    static void on_enabled_event(Manager *self, AgAccountId id);
};

} //namespace Accounts
