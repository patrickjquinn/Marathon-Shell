// SPDX-FileCopyrightText: 2015-2016 Canonical Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
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

#ifndef LIBSIGNON_DEBUG_H
#define LIBSIGNON_DEBUG_H

#include <QDebug>

#ifdef TRACE
    #undef TRACE
#endif

#ifdef BLAME
    #undef BLAME
#endif

#ifdef DEBUG_ENABLED
extern int libsignon_logging_level;
static inline bool debugEnabled() {
        return libsignon_logging_level >= 2;
}

static inline bool criticalsEnabled() {
        return libsignon_logging_level >= 1;
}
#define TRACE() \
        if (debugEnabled()) qDebug()
#define BLAME() \
        if (criticalsEnabled()) qCritical()

#else // DEBUG_ENABLED
    #define TRACE() while (0) qDebug()
    #define BLAME() while (0) qDebug()
#endif

namespace SignOn {

void setLoggingLevel(int level);
void initDebug();

}

#endif // LIBSIGNON_DEBUG_H
