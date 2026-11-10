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

#ifndef SIGNONERROR_H
#define SIGNONERROR_H


#ifdef SIGNON_INTERNAL
    #include <QObject>
#endif

#include <QMetaType>
#include <QString>

#include <SignOn/libsignoncommon.h>

namespace SignOn {

/*!
 * @class Error Base object definition for Signon error handling.
 * Extend this class' error range in order to provide custom error handling.
 *
 * @attention All this class' definitions must be inline.
 */
class SIGNON_EXPORT Error
#ifdef SIGNON_INTERNAL
: public QObject { Q_OBJECT
#else
{
#endif
public:
    /*!
     * @enum ErrorType Error codes for all the Signon by default supported
     * errors.
     * Plugin developers should use the predefined error types in the
     * AuthSessionErr and UserErr interval, and in the case of extended error
     * handling values greater than UserErr.
     * @attention Error types lesser than Error::UserErr are reserved.
     */
    enum ErrorType {
        Unknown = 1,               /**< Catch-all for errors not distinguished
                                        by another code. */
        InternalServer = 2,        /**< Signon Daemon internal error. */
        InternalCommunication = 3, /**< Communication with Signon Daemon
                                     error. */
        PermissionDenied = 4,      /**< The operation cannot be performed due to
                                        insufficient client permissions. */
        EncryptionFailure,         /**< Failure during data
                                     encryption/decryption. */
        AuthServiceErr = 100,           /* Placeholder to rearrange enumeration
                                         - AuthService specific */
        MethodNotKnown,            /**< The method with this name is not
                                     found. */
        ServiceNotAvailable,       /**< The service is temporarily
                                     unavailable. */
        InvalidQuery,              /**< Parameters for the query are invalid. */
        IdentityErr = 200,              /* Placeholder to rearrange enumeration
                                         - Identity specific */
        MethodNotAvailable,        /**< The requested method is not available. */
        IdentityNotFound,          /**< The identity matching this Identity
                                     object was not found on the service. */
        StoreFailed,               /**< Storing credentials failed. */
        RemoveFailed,              /**< Removing credentials failed. */
        SignOutFailed,             /**< SignOut failed. */
        IdentityOperationCanceled, /**< Identity operation was canceled by
                                     user. */
        CredentialsNotAvailable,   /**< Query failed. */
        ReferenceNotFound,         /**< Trying to remove nonexistent
                                     reference. */
        AuthSessionErr = 300,      /* Placeholder to rearrange enumeration
                                     - AuthSession/AuthPluginInterface
                                     specific */
        MechanismNotAvailable,     /**< The requested mechanism is not
                                     available. */
        MissingData,               /**< The SessionData object does not contain
                                        necessary information. */
        InvalidCredentials,        /**< The supplied credentials are invalid for
                                        the mechanism implementation. */
        NotAuthorized,             /**< Authorization failed. */
        WrongState,                /**< An operation method has been called in
                                        a wrong state. */
        OperationNotSupported,     /**< The operation is not supported by the
                                        mechanism implementation. */
        NoConnection,              /**< No Network connetion. */
        Network,                   /**< Network connetion failed. */
        Ssl,                       /**< Ssl connection failed. */
        Runtime,                   /**< Casting SessionData into subclass
                                     failed */
        SessionCanceled,           /**< Challenge was cancelled. */
        TimedOut,                  /**< Challenge was timed out. */
        UserInteraction,           /**< User interaction dialog failed */
        OperationFailed,           /**< Temporary failure in authentication. */
        EncryptionFailed,          /**< @deprecated Failure during data
                                     encryption/decryption. */
        TOSNotAccepted,            /**< User declined Terms of Service. */
        ForgotPassword,            /**< User requested reset password
                                     sequence. */
        MethodOrMechanismNotAllowed, /**< Method or mechanism not allowed for
                                       this identity. */
        IncorrectDate,             /**< Date time incorrect on device. */
        UserErr = 400                   /* Placeholder to rearrange enumeration
                                         - User space specific */
    };

    /*!
     * Constructor
     */
    Error() : m_type((int)Unknown), m_message(QString()) { registerType(); }

    /*!
     * Copy constructor
     * @param src Error object to be copied
     */

    Error(const Error &src) :
#ifdef SIGNON_INTERNAL
        QObject(),
#endif
        m_type(src.type()), m_message(src.message()) {}

    /*!
     * For convenience constructor
     * @param type Type of the error
     * @param message Error message
     */
    Error(int type, const QString &message = QString()):
        m_type(type), m_message(message) { registerType(); }

    /*!
     * Assignment operator
     * @param src Error object to be assigned to this instance
     */
    Error &operator=(const Error &src)
        { m_type = src.type(); m_message = src.message(); return *this; }

    /*!
     * Destructor
     */
    virtual ~Error() {}

    /*!
     * Sets the type of the error.
     * The 'type' parameter is an integer and values beyond Error::ErrorType
     * can be used for customized error reporting.
     * @see Error::ErrorType.
     * @param type The type to be set
     */
    void setType(int type) { m_type = type; }

    /*!
     * Sets the error message.
     * @param message The message to be set
     */
    void setMessage(const QString &message) { m_message = message; }

    /*!
     * @return Type of the error
     */
    int type() const { return m_type; }

    /*!
     * @return Error message
     */
    QString message() const { return m_message; }

private:
    inline void registerType();

private:
    int m_type;
    QString m_message;
};

} //namespace SignOn

Q_DECLARE_METATYPE(SignOn::Error)

void SignOn::Error::registerType() {
    qRegisterMetaType<SignOn::Error>("SignOn::Error");
}

#endif // SIGNONERROR_H
