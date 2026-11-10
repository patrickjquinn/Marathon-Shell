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

#ifndef LIBSIGNON_SECURITY_CONTEXT_H
#define LIBSIGNON_SECURITY_CONTEXT_H

#include <QMetaType>
#include <QStringList>

#include "libsignoncommon.h"

namespace SignOn {

/*!
 * @class SecurityContext
 * @headerfile securitycontext.h SignOn/SecurityContext
 *
 * Contains access security context information.
 * @see accessControlListFull()
 */
class SIGNON_EXPORT SecurityContext
{

public:
    /*!
     * Creates a new SecurityContext object.
     */
    SecurityContext();

    /*!
     * Creates a new SecurityContext object.
     * @param systemContext
     * @param applicationContext
     */
    SecurityContext(const QString &systemContext, const QString &applicationContext);

    /*!
     * Sets the system context.
     *
     * @param systemContext
     */
    void setSystemContext(const QString &systemContext);

    /*!
     * Gets the system context.
     * @return The system context, or an empty string.
     */
    QString systemContext() const;

    /*!
     * Sets the application context.
     *
     * @param applicationContext
     */
    void setApplicationContext(const QString &applicationContext);

    /*!
     * Gets the application context.
     * @return The application context, or an empty string.
     */
    QString applicationContext() const;
    
private:
    QString m_systemContext;
    QString m_applicationContext;
};

/*!
 * @typedef QList<SecurityContext> SecurityContextList
 * Defines a list of security contexts.
 */
typedef QList<SecurityContext> SecurityContextList;

}  // namespace SignOn

Q_DECLARE_METATYPE(SignOn::SecurityContext)

#endif /* LIBSIGNON_SECURITY_CONTEXT_H */
