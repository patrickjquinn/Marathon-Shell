// SPDX-FileCopyrightText: 2011 Nokia Corporation.
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation.
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2011 Nokia Corporation.
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

#ifndef ACCOUNTS_ERROR_H
#define ACCOUNTS_ERROR_H

#include <QMetaType>
#include <QString>

#include <Accounts/accountscommon.h>

extern "C"
{
    typedef struct _GError GError;
}

namespace Accounts {

class ACCOUNTS_EXPORT Error
{
public:
    /*!
     * @enum ErrorType Error codes for all the accounts errors.
     */
    enum ErrorType {
        NoError = 0,
        Unknown,
        Database,                   /**< Generic database error */
        Deleted,                    /**< The account object refers to an
                                      account which has been deleted */
        DatabaseLocked,             /**< The database is locked */
        AccountNotFound,            /**< The account couldn't be found */
    };

    /*!
     * Basic constructor.
     */
    Error(): m_type(NoError), m_message(QString()) { registerType(); }

    /*!
     * Copy constructor
     * @param src Error object to be copied.
     */
    Error(const Error &src):
        m_type(src.type()), m_message(src.message()) {}

    /*!
     * Constructor.
     * @param type The error's type.
     * @param message The error's message.
     */
    Error(ErrorType type, const QString &message = QString()):
        m_type(type), m_message(message)
        { registerType(); }

    /*!
     * Assignment operator.
     * @param src The error object to be assigned to this instance.
     */
    Error &operator=(const Error &src)
        { m_type = src.type(); m_message = src.message(); return *this; }

    /*!
     * Destructor.
     */
    virtual ~Error() {}

    /*!
     * @return The error's type.
     */
    ErrorType type() const { return m_type; }

    /*!
     * @return The error's message.
     */
    QString message() const { return m_message; }

private:
    // Don't include in docs: \cond
    friend class Account;
    friend class Manager;
    Error(const GError *error);

    inline void registerType();
    // \endcond

private:
    // Don't include private data in docs: \cond
    ErrorType m_type;
    QString m_message;
    // \endcond
};

} //namespace

Q_DECLARE_METATYPE(Accounts::Error)

void Accounts::Error::registerType()
{
    qRegisterMetaType<Accounts::Error>("Accounts::Error");
}

#endif // ACCOUNTS_ERROR_H
