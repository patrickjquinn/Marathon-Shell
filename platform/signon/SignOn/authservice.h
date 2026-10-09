// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
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

#ifndef AUTHSERVICE_H
#define AUTHSERVICE_H

#include <QObject>
#include <QStringList>
#include <QMap>

#include "libsignoncommon.h"
#include "identityinfo.h"
#include "signonerror.h"

namespace SignOn {

/*!
 * @class AuthService
 * @headerfile authservice.h SignOn/AuthService
 *
 * Represents signon for client application.
 * The class is for managing identities.
 * Most applications can use this by using widgets from libSignOnUI.
 */
class SIGNON_EXPORT AuthService: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(AuthService)

    friend class AuthServiceImpl;

public:
    /*!
     * @enum ServiceError
     * Codes for errors that may be reported by AuthService objects.
     * @deprecated This enum is deprecated. Replaced by Error::ErrorType.
     */
    enum ServiceError {
        UnknownError = 1,               /**< Catch-all for errors not distinguished by another code. */
        InternalServerError = 2,        /**< Signon Daemon internal error. */
        InternalCommunicationError = 3, /**< Communication with Signon Daemon error. */
        PermissionDeniedError = 4,      /**< The operation cannot be performed due to insufficient client permissions. */
        AuthServiceErr = 100,           /* Placeholder to rearrange enumeration */
        MethodNotKnownError,            /**< The method with this name is not found. */
        NotAvailableError,              /**< The service is temporarily unavailable. */
        InvalidQueryError               /**< Parameters for the query are invalid. */
    };

    /*!
     * @enum IdentityFilterCriteria
     * Criterias for idetity query filtering.
     * @see AuthService::queryIdentities()
     */
    typedef enum {
        AuthMethod = 0,
        Username,
        Realm,
        Caption
    } IdentityFilterCriteria;

    /*!
     * @class IdentityRegExp
     * The class represents a regular expression.
     * It is used for filtering identity querying.
     * @see queryIdentities()
     * @note This is for internal use only.
     */
    class IdentityRegExp
    {
    public:
        /*!
         * Constructor creates an IdentityRegExp, as a specified by pattern.
         * @param pattern The regular expression as a string
         */
        IdentityRegExp(const QString &pattern);

        /*!
         * Copy constructor, creates a copy of src.
         * @param src The IdentityRegExp to be copied
         */
        IdentityRegExp(const IdentityRegExp &src);

        /*!
         * Returns the validity of regular expression.
         * @return Always false, validity check not implemented.
         */
        bool isValid() const;

        /*!
         * Returns the pattern of regular expression as string.
         * @return The pattern of this regular expression as string.
         */
        QString pattern() const;

    private:
        QString m_pattern;
    };

public:
    /*!
     * @typedef IdentityFilter
     * Map to hold different filtering options.
     */
    typedef QMap<IdentityFilterCriteria, IdentityRegExp> IdentityFilter;

    /*!
     * Basic constructor
     * @param parent Parent object
     */
    AuthService(QObject *parent = 0);

    /*!
     * Destructor
     */
    ~AuthService();

    /*!
     * Requests the information on available authentication methods.
     * The list of service types retrieved
     * is emitted with signal methodsAvailable().
     * Error is reported by emitting signal error().
     *
     * @see AuthService::methodsAvailable()
     * @see AuthService::error()
     */
    void queryMethods();

    /*!
     * Requests the information on mechanisms which are available
     * for certain authentication type.
     * The list of mechanisms retrieved from the service
     * is emitted with signal mechanismsAvailable().
     * Error is reported by emitting signal error().
     * If method is not a valid method, Error::type() is
     * Error::MethodNotKnown.
     *
     * @see AuthService::mechanismsAvailable()
     * @see AuthService::error()
     * @param method authetication method name
     */
    void queryMechanisms(const QString &method);

    /*!
     * Requests information on identities which are stored.
     * The list of identities retrieved from the service
     * is emitted with signal identities().
     * Error is reported by emitting signal error().
     * If filter is not valid, Error::type() is
     * Error::InvalidQuery.
     * If the application does not have keychain-access credential,
     * Error::type() is Error::PermissionDenied.
     *
     * @see AuthService::identities()
     * @see AuthService::error()
     * @param filter Shows only identities specified in filter - filtering not implemented for the moment.
     * If default parameter is passed, all the identities are returned.
     * @credential keychain-access key-chain application can access list of identities.
     */
    void queryIdentities(const IdentityFilter &filter = IdentityFilter());

    /*!
     * Clears credentials database. All identity entries are removed from database.
     * Signal cleared() is emitted when operation is completed.
     * Error is reported by emitting signal error().
     * If the application does not have keychain-access credential,
     * Error::type() is Error::PermissionDenied.
     *
     * @see AuthService::cleared()
     * @see AuthService::error()
     * @credential keychain-access key-chain application can clear database.
     */
    void clear();

Q_SIGNALS:

    /*!
     * Emitted when an error occurs while using the AuthService.
     * Typical error types are generic errors, where
     * Error::type() < Error::AuthServiceErr and
     * AuthService specific, where
     * Error::AuthServiceErr < Error::type() < Error::IdentityErr
     * @see SignOn::Error
     * @see SignOn::Error::ErrorType
     * @param err The error object
     */
    void error(const SignOn::Error &err);

    /*!
     * Emitted when the list of available authentication methods have been obtained
     * from the service.
     *
     * @param methods List of available authentication method names
     */
    void methodsAvailable(const QStringList &methods);

    /*!
     * Emitted when the list of available mechanisms have been obtained
     * from the service.
     *
     * @param method Name of authentication method that was queried
     * @param mechanisms List of available mechanisms
     */
    void mechanismsAvailable(const QString &method, const QStringList &mechanisms);

    /*!
     * Lists identities available on the server matching query parameters.
     * This signal is emitted in response to queryIdentities().
     *
     * @param identityList list of identities information
     */
    void identities(const QList<SignOn::IdentityInfo> &identityList);

    /*!
     * Database is cleared and reset to initial state.
     * This signal is emitted in response to clear().
     */
    void cleared();

private:
    class AuthServiceImpl *impl;
};

} // namespace SignOn

#endif // AUTHSERVICE_H
