// SPDX-FileCopyrightText: 2011 Nokia Corporation
// SPDX-FileCopyrightText: 2011-2016 Canonical Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2011 Nokia Corporation.
 * Copyright (C) 2011-2016 Canonical Ltd.
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

#include "dbusinterface.h"
#include "debug.h"
#include "libsignoncommon.h"

#include <climits>

using namespace SignOn;

static bool connIsP2P(const QDBusConnection &connection)
{
    return connection.name().startsWith(QLatin1String("libsignon-qt"));
}

DBusInterface::DBusInterface(const QString &service,
                             const QString &path,
                             const char *interface,
                             const QDBusConnection &connection,
                             QObject *parent):
    /* Use empty service name for p2p connections. This is a workaround for
     * https://bugreports.qt-project.org/browse/QTBUG-32374
     */
    QDBusAbstractInterface(connIsP2P(connection) ? QLatin1String("") : service,
                           path, interface, connection, parent)
{
    setTimeout(INT_MAX);
}

DBusInterface::~DBusInterface()
{
}

bool DBusInterface::connect(const char *name,
                            QObject *receiver,
                            const char *slot)
{
    return connection().connect(service(), path(), interface(),
                                QLatin1String(name), receiver, slot);
}
