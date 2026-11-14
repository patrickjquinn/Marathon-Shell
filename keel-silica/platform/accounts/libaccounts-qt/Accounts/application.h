// SPDX-FileCopyrightText: 2012 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2012 Nokia Corporation.
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

#ifndef ACCOUNTS_APPLICATION_H
#define ACCOUNTS_APPLICATION_H

#include "Accounts/accountscommon.h"

#include <QString>

extern "C"
{
    typedef struct _AgApplication AgApplication;
}

namespace Accounts
{
class Service;

class ACCOUNTS_EXPORT Application
{
public:
    Application();
    Application(const Application &other);
    Application &operator=(const Application &other);
    ~Application();

    bool isValid() const;

    QString name() const;
    QString displayName() const;
    QString description() const;
    QString iconName() const;
    QString desktopFilePath() const;
    QString trCatalog() const;

    bool supportsService(const Service &service) const;
    QString serviceUsage(const Service &service) const;

private:
    // Don't include private data in docs: \cond
    friend class Manager;
    Application(AgApplication *application);
    AgApplication *application() const;

    AgApplication *m_application;
    // \endcond
};

} //namespace

#endif // ACCOUNTS_APPLICATION_H
