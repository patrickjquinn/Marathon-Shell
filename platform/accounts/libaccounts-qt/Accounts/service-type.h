// SPDX-FileCopyrightText: 2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2012 Intel Corporation.
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2011 Nokia Corporation.
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

#ifndef ACCOUNTS_SERVICE_TYPE_H
#define ACCOUNTS_SERVICE_TYPE_H

#include "Accounts/accountscommon.h"

#include <QObject>
#include <QSet>
#include <QString>
#include <QDomDocument>

extern "C"
{
    typedef struct _AgServiceType AgServiceType;
}

namespace Accounts
{

class ACCOUNTS_EXPORT ServiceType
{
public:
    ServiceType();
    ServiceType(const ServiceType &other);
    ServiceType &operator=(const ServiceType &other);
    ~ServiceType();

    bool isValid() const;

    QString name() const;
    QString description() const;
    QString displayName() const;
    QString trCatalog() const;
    QString iconName() const;
    bool hasTag(const QString &tag) const;
    QSet<QString> tags() const;

    const QDomDocument domDocument() const;

    friend inline bool operator==(const Accounts::ServiceType &s1,
                                  const Accounts::ServiceType &s2) {
        return s1.m_serviceType == s2.m_serviceType || s1.name() == s2.name();
    }

private:
    // \cond
    friend class Manager;
    ServiceType(AgServiceType *serviceType, ReferenceMode mode = AddReference);
    AgServiceType *m_serviceType;
    mutable QSet<QString> *m_tags;
    // \endcond
};

} //namespace Accounts

#endif // ACCOUNTS_SERVICE_TYPE_H
