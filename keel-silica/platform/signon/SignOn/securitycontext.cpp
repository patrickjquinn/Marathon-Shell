// SPDX-FileCopyrightText: 2018 elementary, Inc
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2018 elementary, Inc
 *
 * Contact: Corentin Noël <corentin@elementary.io>
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

#include <QMetaType>
#include <QStringList>

#include "debug.h"
#include "securitycontext.h"
#include "securitycontextpriv.h"

namespace SignOn {

SecurityContext::SecurityContext()
{
}

SecurityContext::SecurityContext(const QString &systemContext,
                                 const QString &applicationContext):
    m_systemContext(systemContext),
    m_applicationContext(applicationContext)
{
}

QDBusArgument &operator<<(QDBusArgument &argument,
                          const SecurityContext &securityContext)
{
    argument.beginStructure();
    argument << securityContext.systemContext()
             << securityContext.applicationContext();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument,
                                SecurityContext &securityContext)
{
    QString systemContext;
    QString applicationContext;

    argument.beginStructure();
    argument >> systemContext >> applicationContext;
    securityContext.setSystemContext(systemContext);
    securityContext.setApplicationContext(applicationContext);
    argument.endStructure();
    return argument;
}

void SecurityContext::setSystemContext(const QString &systemContext)
{
    m_systemContext = systemContext;
}

QString SecurityContext::systemContext() const
{
    return m_systemContext;
}

void SecurityContext::setApplicationContext(const QString &applicationContext)
{
    m_applicationContext = applicationContext;
}

QString SecurityContext::applicationContext() const
{
    return m_applicationContext;
}

}  // namespace SignOn
