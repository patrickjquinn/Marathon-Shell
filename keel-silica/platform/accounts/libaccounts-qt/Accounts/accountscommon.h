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
#ifndef ACCOUNTSCOMMON_H_
#define ACCOUNTSCOMMON_H_

#ifdef BUILDING_ACCOUNTS_QT

#include <QDebug>

// String conversion

#ifdef ASCII
    #undef ASCII
#endif
#define ASCII(s) QLatin1String(s)

#ifdef UTF8
    #undef UTF8
#endif
#define UTF8(s) QString::fromUtf8(s)

// Symbol visibility
#if __GNUC__ >= 4
    #define ACCOUNTS_EXPORT __attribute__ ((visibility("default")))
#endif

#endif // BUILDING_ACCOUNTS_QT

#ifndef ACCOUNTS_EXPORT
    #define ACCOUNTS_EXPORT
#endif

namespace Accounts {

enum ReferenceMode {
    AddReference = 0,
    StealReference,
};

} // namespace

#endif /* ACCOUNTSCOMMON_H_ */
