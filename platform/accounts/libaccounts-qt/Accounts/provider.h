// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
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
/*!
 * @copyright Copyright (C) 2009-2011 Nokia Corporation.
 * @license LGPL
 */

#ifndef ACCOUNTS_PROVIDER_H
#define ACCOUNTS_PROVIDER_H

#include "Accounts/accountscommon.h"

#include <QStringList>
#include <QDomDocument>

extern "C"
{
    typedef struct _AgProvider AgProvider;
}

namespace Accounts
{
class Provider;

typedef QList<Provider> ProviderList;

class ACCOUNTS_EXPORT Provider
{
public:
    Provider();
    Provider(const Provider &other);
    Provider &operator=(const Provider &other);
    ~Provider();

    bool isValid() const;

    QString name() const;
    QString displayName() const;
    QString description() const;
    QString pluginName() const;
    QString trCatalog() const;
    QString iconName() const;
    QString domainsRegExp() const;
    bool isSingleAccount() const;
    bool hasTag(const QString &tag) const;
    QSet<QString> tags() const;
    const QDomDocument domDocument() const;

    friend inline bool operator==(const Accounts::Provider &p1,
                                  const Accounts::Provider &p2) {
        return p1.m_provider == p2.m_provider || p1.name() == p2.name();
    }

private:
    // \cond
    friend class Manager;
    Provider(AgProvider *provider, ReferenceMode mode = AddReference);
    AgProvider *provider() const;
    AgProvider *m_provider;
    mutable QSet<QString> *m_tags;
    // \endcond
};

} //namespace Accounts

#endif // ACCOUNTS_PROVIDER_H
