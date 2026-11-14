// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * NgfClient - Qt Non-Graphic Feedback daemon client library
 *
 * Copyright (C) 2012 Jolla Ltd.
 * Contact: juho.hamalainen@tieto.com
 *
 * This work is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1 as published by the Free Software Foundation.
 *
 * This work is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this work; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 */

#ifndef NGF_CLIENT_GLOBAL_H
#define NGF_CLIENT_GLOBAL_H

#include <QtCore/QtGlobal>

#if defined(NGFCLIENT_LIBRARY)
#  define NGFCLIENT_EXPORT Q_DECL_EXPORT
#else
#  define NGFCLIENT_EXPORT Q_DECL_IMPORT
#endif

#endif
