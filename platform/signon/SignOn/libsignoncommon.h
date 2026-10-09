// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2015-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2015-2016 Canonical Ltd.
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

#ifndef LIBSIGNONCOMMON_H
#define LIBSIGNONCOMMON_H

#ifdef SIGNON_EXPORT
    #undef SIGNON_EXPORT
#endif

#if __GNUC__ >= 4
    #define SIGNON_EXPORT __attribute__ ((visibility("default")))
#endif

#ifndef SIGNON_EXPORT
    #define SIGNON_EXPORT
#endif

#endif // LIBSIGNONCOMMON_H
