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

#ifndef IDENTITY_H
#define IDENTITY_H

#include <QObject>
#include <QByteArray>
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QPointer>

#include "libsignoncommon.h"
#include "authsession.h"
#include "identityinfo.h"
#include "signonerror.h"

#define SSO_NEW_IDENTITY 0

namespace SignOn {

typedef QPointer<AuthSession> AuthSessionP;

/*!
 * @class Identity
 * @headerfile identity.h SignOn/Identity
 *
 * Represents a database entry for a single identity.
 * Identity is a client side presentation of a credential.
 */
class SIGNON_EXPORT Identity: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(Identity)

    friend class IdentityImpl;

public:
    /*!
     * @enum IdentityError
     * Codes for errors that may be reported by Identity objects
     * @deprecated This enum is deprecated. Replaced by Error::ErrorType.
     */
    enum IdentityError {
        UnknownError = 1,               /**< Catch-all for errors not
                                          distinguished by another code. */
        InternalServerError = 2,        /**< Signon Daemon internal error. */
        InternalCommunicationError = 3, /**< Communication with Signon Daemon
                                          error . */
        PermissionDeniedError = 4,      /**< The operation cannot be performed
                                          due to insufficient client
                                          permissions. */
        IdentityErr = 200,              /* placeholder to rearrange
                                          enumeration. */
        MethodNotAvailableError,        /**< The requested mechanism is not
                                          available. */
        NotFoundError,                  /**< The identity matching this
                                          Identity object was not found on the
                                          service. */
        StoreFailedError,               /**< Storing credentials failed. */
        RemoveFailedError,              /**< Removing credentials failed. */
        SignOutFailedError,             /**< SignOut failed. */
        CanceledError,                  /**< Operation was canceled by user. */
        CredentialsNotAvailableError    /**< Query fails*/
    };

protected:
    /*!
     * @internal
     */
    Identity(const quint32 id = SSO_NEW_IDENTITY,
             QObject *parent = 0);

public:
    /*!
     * Constructs a new identity object.
     *
     * Can return NULL if client is untrusted.
     *
     * @param info Identity information
     * @param parent Parent object of the identity
     * @return Pointer to new identity object or NULL if it fails to create.
     */
    static Identity *newIdentity(const IdentityInfo &info = IdentityInfo(),
                                 QObject *parent = 0);

    /*!
     * Constructs an identity object associated with an existing identity record.
     *
     * Can return NULL if client is untrusted.
     *
     * @param id Identity ID on the service
     * @param parent Parent object of the identity
     * @return Pointer to identity object or NULL if it fails to create.
     */
    static Identity *existingIdentity(const quint32 id, QObject *parent = 0);

    /*!
     * Destructor
     */
    virtual ~Identity();

    /*!
     * Unique id of given identity
     *
     * @return  Identity ID of the identity. For new identity which is not
     * stored, NEW_IDENTITY is returned.
     */
    quint32 id() const;

    /*!
     * Query list of available authentication methods for given identity.
     * List is returned by emitting signal methodsAvailable().
     * If the operation fails, a signal error() is emitted.
     * @see Identity::error()
     * If identity is not stored, Error::type() is
     * Error::CredentialsNotAvailable, or
     * Error::IdentityNotFound.
     * @see methodsAvailable().
     */
    void queryAvailableMethods();

    /*!
     * Creates a new session for authentication. This creates a connection
     * to authentication plugin.
     * The Identity object is parent and owner of all created authentication sessions.
     *
     * @param methodName Name of authentication method to use
     * @return New authentication session or NULL if not able to create
     */
    AuthSessionP createSession(const QString &methodName);

    /*!
     * Destroys an authentication session.
     *
     * @param session Session to be destroyed
     */
    void destroySession(const AuthSessionP &session);

    /*!
     * Requests the user to give a new secret into database.
     * Client can use requestCredentialsUpdate() to launch external
     * dialog for asking new secret, that will be stored into database.
     * On success, a signal credentialsStored() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If storing changes fails, Error::type() is
     * Error::StoreFailed,
     * If user cancels dialog, Error::type() is
     * Error::IdentityOperationCanceled.
     *
     * @see credentialsStored()
     * @see Identity::error()
     * @param message Message to be shown for the user
     */
    void requestCredentialsUpdate(const QString &message = QString());

    /*!
     * Stores credential parameters for this authentication identity.
     * IdentityInfo contains restrictions on methods and mechanisms
     * for given Identity. @see IdentityInfo
     * On success, a signal credentialsStored() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If storing changes fails, Error::type() is
     * Error::StoreFailed,
     *
     * Untrusted clients may be blocked from performing this operation,
     * subject to the security framework restrictions.
     *
     * If default value is used for the parameter the Identity object
     * stores the internally stored information, e.g. the IdentityInfo object
     * used to create a new identity using Identity::newIdentity()
     *
     * @see credentialsStored()
     * @see Identity::error()
     * @param info Credentials to store
     */
    void storeCredentials(const IdentityInfo &info = IdentityInfo());

    /*!
     * Removes this identity from database.
     * On success, a signal removed() is emitted
     * If the operation fails, a signal error() is emitted.
     * If removing fails, Error::type() is
     * Error::RemoveFailed,
     *
     * Untrusted clients may be blocked from performing this operation,
     * subject to the security framework restrictions.
     * @see removed()
     * @see Identity::error()
     */
    void remove();

    /*!
     * Adds the named reference to identity into the database.
     * On success, a signal referenceAdded() is emitted
     * If the operation fails, a signal error() is emitted.
     * If referencing fails, Error::type() is
     * Error::StoreFailed,
     *
     * Untrusted clients may be blocked from performing this operation,
     * subject to the security framework restrictions.
     * @see referenceAdded()
     * @see Identity::error()
     */
    void addReference(const QString &reference = QString());

    /*!
     * Removes a named reference to identity from the database.
     * On success, a signal referenceRemoved() is emitted
     * If the operation fails, a signal error() is emitted.
     * If dereferencing fails, Error::type() is
     * Error::ReferenceNotFound,
     *
     * Untrusted clients may be blocked from performing this operation,
     * subject to the security framework restrictions.
     * @see referenceRemoved()
     * @see Identity::error()
     */
    void removeReference(const QString &reference = QString());

    /*!
     * Query stored credential parameters for this authentication identity.
     * On success, a signal info() is emitted with parameters
     * in the service.
     * If the operation fails, a signal error() is emitted.
     * If query fails, Error::type() is
     * Error::CredentialsNotAvailable,
     *
     * Untrusted clients may be blocked from performing this operation,
     * subject to the security framework restrictions.
     * @see info()
     * @see Identity::error()
     */
    void queryInfo();

    /*!
     * Gets a secret verification from the user and compares it to the stored
     * secret.
     * This launchs an external dialog for asking secret.
     * When verification is completed, signal userVerified() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If user selects "Forgot Password"-sequence, Error::type() is
     * Error::ForgotPassword.
     *
     * @see userVerified()
     * @see Identity::error()
     * @param message Message to be shown for the user
     */
    void verifyUser(const QString &message = QString());

    /*!
     * Gets a secret verification from the user and compares it to the stored
     * secret.
     * This launchs an external dialog for asking secret.
     * When verification is completed, signal userVerified() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If user selects "Forgot Password"-sequence, Error::type() is
     * Error::ForgotPassword.
     *
     * @see userVerified()
     * @see Identity::error()
     * @param params Dialog customization parameters
     */
    void verifyUser(const QVariantMap &params);

    /*!
     * Verifies if the given secret match the stored secret.
     * When verification is completed, a signal secretVerified() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If the credentials are not stored, Error::type() is
     * Error::CredentialsNotAvailable.
     *
     * @see secretVerified()
     * @see Identity::error()
     * @param secret String to be verified
     */
    void verifySecret(const QString &secret);

     /*!
     * Signs out Identity from all services. All authentication sessions using
     * this Identity will be invalidated and all tokens cleared from cache.
     * When sign out is completed, signal signedOut() is emitted.
     * If the operation fails, a signal error() is emitted.
     * If signout fails, Error::type() is
     * Error::SignOutFailed.
     *
     * All clients using same identity will receive signedOut signal.
     * @see signedOut()
     * @see Identity::error()
     */
    void signOut();

Q_SIGNALS:

    /*!
     * Emitted when an error occurs while performing an operation.
     * Typical error types are generic errors, where
     * Error::type() < Error::AuthServiceErr and
     * Identity specific, where
     * Error::IdentityErr < Error::type() < Error::AuthServiceErr
     * @see SignOn::Error.
     * @see SignOn::Error::ErrorType
     * @param err The error object.
     */
    void error(const SignOn::Error &err);

    /*!
     * Emitted when the list of available mechanisms has been obtained
     * for identity.
     *
     * @param methods List of available methods
     */
    void methodsAvailable(const QStringList &methods);

    /*!
     * Emitted when credentials passed by storeCredentials() method
     * have been successfully stored on the service.
     * @param id Identifier of the credentials that has been stored
     */
    void credentialsStored(const quint32 id);

    /*!
     * Emitted when references are added by addReference()
     * method and change
     * has been successfully stored on the service.
     */
    void referenceAdded();

    /*!
     * Emitted when references are removed by removeReference()
     * method and change
     * has been successfully stored on the service.
     */
    void referenceRemoved();

    /*!
     * Emitted when credentials passed by queryInfo() method
     * @param info Credentials as have been stored on the service
     */
    void info(const SignOn::IdentityInfo &info);

    /*!
     * Emitted when the user verification is completed.
     * @param valid Is the given secret same as stored
     */
    void userVerified(const bool valid);

    /*!
     * Emitted when secret verification is completed.
     * @param valid Is the given secret same as stored
     */
    void secretVerified(const bool valid);

    /*!
     * Emitted when the identity is signed out.
     */
    void signedOut();

    /*!
     * Emitted when the identity is removed.
     */
    void removed();

private:
    class IdentityImpl *impl;
};

}  // namespace SignOn

#endif /* IDENTITY_H */
