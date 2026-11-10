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

#include "debug.h"
#include <QByteArray>

int libsignon_logging_level = 1;

namespace SignOn {

void setLoggingLevel(int level) {
    libsignon_logging_level = level;
}

void initDebug() {
    QByteArray loggingLevelVar = qgetenv("LIBSIGNON_LOGGING_LEVEL");
    if (!loggingLevelVar.isEmpty()) {
        setLoggingLevel(loggingLevelVar.toInt());
    }
}

}
