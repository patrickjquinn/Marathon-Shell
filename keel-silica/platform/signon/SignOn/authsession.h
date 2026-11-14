// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2011-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
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
/*!
 * @copyright Copyright (C) 2009-2011 Nokia Corporation.
 * @license LGPL
 */

#ifndef AUTHSESSION_H
#define AUTHSESSION_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QVariant>

#include "libsignoncommon.h"
#include "sessiondata.h"
#include "signonerror.h"

namespace SignOnTests {
    class AccessControlTest;
}

namespace SignOn {

/*!
 * @class AuthSession
 * @headerfile authsession.h SignOn/AuthSession
 *
 * Represents a session to authentication plugin/server.
 * AuthSession is used to maintain connection to authentication plugin.
 */
class SIGNON_EXPORT AuthSession: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(AuthSession)

    friend class IdentityImpl;
    friend class AuthSessionImpl;
    friend class SignOnTests::AccessControlTest;

public:
    /*!
     * @enum AuthSessionError
     * Codes for errors that may be reported by AuthSession objects
     * @deprecated This enum is deprecated. Replaced by Error::ErrorType.
     */
    enum AuthSessionError {
        UnknownError = 1,               /**< Catch-all for errors not distinguished by another code. */
        InternalServerError = 2,        /**< Signon Daemon internal error. */
        InternalCommunicationError = 3, /**< Communication with Signon Daemon error . */
        PermissionDeniedError = 4,      /**< The operation cannot be performed due to insufficient client permissions. */
        AuthSessionErr = 300,           /* placeholder to rearrange enumeration */
        MechanismNotAvailableError,     /**< The requested mechanism is not available. */
        MissingDataError,               /**< The SessionData object does not contain necessary information. */
        InvalidCredentialsError,        /**< The supplied credentials are invalid for the mechanism implementation. */
        WrongStateError,                /**< An operation method has been called in a wrong state. */
        OperationNotSupportedError,     /**< The operation is not supported by the mechanism implementation. */
        NoConnectionError,              /**< No Network connetion. */
        NetworkError,                   /**< Network connetion failed. */
        SslError,                       /**< Ssl connetion failed. */
        RuntimeError,                   /**< Casting SessionData into subclass failed */
        CanceledError,                  /**< Challenge was canceled. */
        TimedOutError,                  /**< Challenge was timed out. */
        UserInteractionError            /**< User interaction dialog failed */
    };

    /*!
     * @enum AuthSessionState
     * Codes for the states of the AuthSession object.
     * @see stateChanged(AuthSession::AuthSessionState state, const QString &message)
     * @todo The order of the states must be synchronized with AuthPluginState enum
     */
    enum AuthSessionState {
        SessionNotStarted = 0,          /**< No message. */
        HostResolving,                  /**< Resolving remote server host name. */
        ServerConnecting,               /**< Connecting to remote server. */
        DataSending,                    /**< Sending data to remote server. */
        ReplyWaiting,                   /**< Waiting reply from remote server. */
        UserPending,                    /**< Waiting response from user. */
        UiRefreshing,                   /**< Refreshing ui request. */
        ProcessPending,                 /**< Waiting another process to start. */
        SessionStarted,                 /**< Authentication session is started. */
        ProcessCanceling,               /**< Canceling.current process: is this really needed??? */
        ProcessDone,                    /**< Authentication completed. > */
        CustomState,                    /**< Custom message. */
        MaxState,
    };

protected:
    /*!
     * @internal
     */
    AuthSession(quint32 id, const QString &methodName, QObject *parent = 0);
    ~AuthSession();

public:
    /*!
     * Name of method for session
     *
     * @return Name of authentication method.
     */
    const QString name() const;

    /*!
     * Query list of available mechanisms. If wantedMechanisms list is
     * provided, only mechanisms available on that list are reported.
     * List is returned by emitting signal mechanismsAvailable().
     * If the operation fails, the error() signal is emitted.
     *
     * @see AuthSession::mechanismsAvailable()
     * @see AuthSession::error()
     * @param wantedMechanisms List of mechanisms that the client would like to use
     */
     void queryAvailableMechanisms(const QStringList &wantedMechanisms = QStringList());

    /*!
     * Processes sessionData in the authentication service.
     * The service processes the data and generates a response that
     * is emitted with response() signal.
     * If the operation fails, the error() signal is emitted.
     *
     * The format and interpretation of the data is
     * mechanism-specific. The client usually obtains the data
     * from a network protocol, such as the protocols using SASL. In case
     * the mechanism implies generation of the authentication token without
     * a challenge, this method should be called with an empty parameters.
     *
     * Parameters are key value pairs, and they are given for authentication
     * plugin. For example it can contain server name, realm, client key, etc.
     * If the Identity objected that created this AuthSession object was itself created
     * using a IdentityInfo object having the username and secret set, that data
     * is going to be added to the params map before it is passed to a specific
     * authentication plugin implementation. If credentials have been stored
     * with Identity::storeCredentials, then the username is overriden from database.
     * Stored secret is used as a default value.
     *
     * @see AuthSession::response()
     * @see AuthSession::error()
     * @param sessionData Information for authentication session
     * @param mechanism Mechanism to use for authentication
     *
     * @see IdentityInfo
     * @see AuthPluginInterface
     */
    void process(const SessionData &sessionData,
                 const QString &mechanism = QString());

    /*!
     * Sends a challenge to the authentication service.
     * The service processes the challenge and generates a response token that
     * is emitted with response() signal.
     * If the operation fails, the error() signal is emitted.
     *
     * This is actually a call to process. @see process
     *
     * @see AuthSession::response()
     * @see AuthSession::error()
     * @param sessionData Information for authentication session
     * @param mechanism Mechanism to use for authentication
     */
    void challenge(const SessionData& sessionData,
                   const QString &mechanism = QString()) {
        process(sessionData, mechanism);
    }

    /*!
     * Sends a request to the authentication service.
     * The service processes the request and generates a response token that
     * is emitted with response() signal.
     * If the operation fails, the error() signal is emitted.
     *
     * This is actually a call to process. @see process
     *
     * @see AuthSession::response()
     * @see AuthSession::error()
     * @param sessionData Information for authentication session
     * @param mechanism Mechanism to use for authentication
     */
    void request(const SessionData &sessionData,
                 const QString &mechanism = QString()) {
        process(sessionData, mechanism);
    }

    /*!
     * Cancels the ongoing challenge.
     * Signal error() is emitted with Error::type() Error::SessionCanceled when
     * process is canceled.
     * If there is no challenge to cancel, Error::type() is Error::WrongState.
     * If the operation fails, the error() signal is emitted.
     * @see AuthSession::error()
     */
    void cancel();

    /*!
     * Signs message by using secret stored into identity.
     * This convenience interface is to do special challenge to signature service.
     * @param params Extra information for signing
     * @param mechanism Mechanism to use for signing
     *
     * @deprecated
     */
    void signMessage(const SessionData &params,
                     const QString &mechanism = QString()) {
        process(params, mechanism);
    }

Q_SIGNALS:
    /*!
     * Emitted when an error occurs while performing an operation.
     * Typical error types are generic errors, where
     * Error::type() < Error::AuthServiceErr and
     * AuthSession specific, where
     * Error::AuthSessionErr < Error::type() < Error::UserErr
     * @see SignOn::Error
     * @see SignOn::Error::ErrorType
     * @param err The error object
     */
    void error(const SignOn::Error &err);

    /*!
     * Emitted when the list of available mechanisms have been obtained
     * for identity.
     *
     * @param mechanisms List of available mechanisms
     */
    void mechanismsAvailable(const QStringList &mechanisms);

    /*!
     * Authentication response generated by the authentication service.
     * It is sent after a process() call sends a challenge token for
     * authentication is used to request an authentication
     * token, with the response token and accompanying non-opaque information
     * produced by the service.
     *
     * The format and interpretation of the response, as well as
     * names and types of the information parameters, are mechanism-specific.
     *
     * @param sessionData Parameters with the authentication token
     */
    void response(const SignOn::SessionData &sessionData);

    /*!
     * Provides the information about the state of the authentication
     * request.
     * @param state Current state of the authentication request
     * @param message Textual description of the state
     */
    void stateChanged(AuthSession::AuthSessionState state,
                      const QString &message);

private:
    class AuthSessionImpl *impl;
};

}  // namespace SignOn

Q_DECLARE_METATYPE(SignOn::AuthSession::AuthSessionState)

#endif // AUTHSESSION_H
