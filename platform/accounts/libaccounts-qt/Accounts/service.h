// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2012 Intel Corporation.
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2009-2011 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 * Copyright (C) 2012 Intel Corporation.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
 * Contact: Jussi Laako <jussi.laako@linux.intel.com>
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

#ifndef ACCOUNTS_SERVICE_H
#define ACCOUNTS_SERVICE_H

#include "Accounts/accountscommon.h"

#include <QString>
#include <QSet>
#include <QDomDocument>
#include <QStringList>

extern "C"
{
    typedef struct _AgService AgService;
}

namespace Accounts
{
class ACCOUNTS_EXPORT Service
{
public:
    Service();
    Service(const Service &other);
    Service &operator=(const Service &other);
    ~Service();

    bool isValid() const;

    QString name() const;
    QString description() const;
    QString displayName() const;
    QString trCatalog() const;
    QString serviceType() const;
    QString provider() const;
    QString iconName() const;
    bool hasTag(const QString &tag) const;
    QSet<QString> tags() const;

    const QDomDocument domDocument() const;

    friend inline bool operator==(const Accounts::Service &s1,
                                  const Accounts::Service &s2) {
        return s1.m_service == s2.m_service || s1.name() == s2.name();
    }

private:
    // \cond
    friend class Account;
    friend class AccountService;
    friend class AccountServicePrivate;
    friend class Application;
    friend class Manager;
    Service(AgService *service, ReferenceMode mode = AddReference);
    AgService *service() const;
    AgService *m_service;
    mutable QSet<QString> *m_tags;
    // \endcond
};

typedef QList<Service> ServiceList;

} //namespace Accounts

#endif // ACCOUNTS_SERVICE_H
