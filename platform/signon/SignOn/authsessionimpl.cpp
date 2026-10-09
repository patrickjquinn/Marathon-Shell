// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2013-2016 Canonical Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2013-2016 Canonical Ltd.
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
#include "signond/signoncommon.h"

#include "authsessionimpl.h"
#include "debug.h"
#include "libsignoncommon.h"

#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

using namespace SignOn;

static QVariantMap sessionData2VariantMap(const SessionData &data)
{
    QVariantMap result;

    foreach(QString key, data.propertyNames()) {
        if (!data.getProperty(key).isNull() && data.getProperty(key).isValid())
            result[key] = data.getProperty(key);
    }

    return result;
}

AuthSessionImpl::AuthSessionImpl(AuthSession *parent,
                                 quint32 id,
                                 const QString &methodName,
                                 const QString &applicationContext):
    QObject(parent),
    m_parent(parent),
    m_dbusProxy(SIGNOND_AUTH_SESSION_INTERFACE_C,
                this),
    m_id(id),
    m_applicationContext(applicationContext),
    m_methodName(methodName),
    m_isAuthInProcessing(false),
    m_processCall(0)
{
    m_dbusProxy.connect("stateChanged", this,
                        SLOT(stateSlot(int, const QString&)));
    m_dbusProxy.connect("unregistered", this,
                        SLOT(unregisteredSlot()));
    QObject::connect(&m_dbusProxy, SIGNAL(objectPathNeeded()),
                     this, SLOT(initInterface()));

    initInterface();
}

AuthSessionImpl::~AuthSessionImpl()
{
}

PendingCall *AuthSessionImpl::send2interface(const QString &operation,
                                             const char *slot,
                                             const QVariantList &arguments)
{
    return m_dbusProxy.queueCall(operation, arguments,
                                 slot,
                                 SLOT(errorSlot(const QDBusError&)));
}

void AuthSessionImpl::setId(quint32 id)
{
    m_id = id;

    QVariantList arguments;
    arguments += id;

    send2interface(QLatin1String("setId"), 0, arguments);
}

bool AuthSessionImpl::initInterface()
{
    TRACE();
    if (m_isAuthInProcessing) return true;

    m_isAuthInProcessing = true;

    QLatin1String operation("getAuthSessionObjectPath");
    QVariantList arguments;
    arguments += m_id;
    arguments += m_applicationContext;
    arguments += m_methodName;

    SignondAsyncDBusProxy *authService =
        new SignondAsyncDBusProxy(SIGNOND_DAEMON_INTERFACE_C, this);
    authService->setObjectPath(QDBusObjectPath(SIGNOND_DAEMON_OBJECTPATH));

    PendingCall *call =
        authService->queueCall(operation,
                               arguments,
                               SLOT(authenticationSlot(QDBusPendingCallWatcher*)),
                               SLOT(errorSlot(const QDBusError&)));
    QObject::connect(call, SIGNAL(finished(QDBusPendingCallWatcher*)),
                     this, SLOT(deleteServiceProxy()));
    return true;
}

QString AuthSessionImpl::name()
{
    return m_methodName;
}

void
AuthSessionImpl::queryAvailableMechanisms(const QStringList &wantedMechanisms)
{
    QLatin1String remoteFunctionName("queryAvailableMechanisms");

    QVariantList arguments;
    arguments += wantedMechanisms;

    send2interface(remoteFunctionName,
                   SLOT(mechanismsAvailableSlot(QDBusPendingCallWatcher*)),
                   arguments);
}

void AuthSessionImpl::process(const SessionData &sessionData,
                              const QString &mechanism)
{
    if (m_processCall) {
        TRACE() << "AuthSession: client is busy";

        emit m_parent->error(
                Error(Error::WrongState,
                      QString(QLatin1String("AuthSession(%1) is busy"))
                         .arg(m_methodName)));
        return;
    }

    QVariantMap sessionDataVa = sessionData2VariantMap(sessionData);
    QString remoteFunctionName;

    QVariantList arguments;
    arguments += sessionDataVa;
    arguments += mechanism;

    remoteFunctionName = QLatin1String("process");

    m_processCall = send2interface(remoteFunctionName,
                   SLOT(responseSlot(QDBusPendingCallWatcher*)), arguments);
    Q_EMIT m_parent->stateChanged(AuthSession::ProcessPending,
                                  QLatin1String("The request is added "
                                                "to queue."));
}

void AuthSessionImpl::cancel()
{
    if (m_processCall && m_processCall->cancel()) {
        emit m_parent->error(Error(Error::SessionCanceled,
                                   QLatin1String("Process is canceled.")));
    } else {
        send2interface(QLatin1String("cancel"), 0, QVariantList());
    }

    m_processCall = 0;
}

void AuthSessionImpl::ignoreError(const QDBusError &err)
{
    TRACE() << err;
}

void AuthSessionImpl::errorSlot(const QDBusError &err)
{
    TRACE() << err;

    m_processCall = 0;
    int errCode = Error::Unknown;
    QString errMessage;

    if (err.type() != QDBusError::Other) {
        qCritical() << err.type();
        qCritical() << err.name();
        qCritical() << err.message();
    } else if (err.name() == SIGNOND_SESSION_CANCELED_ERR_NAME) {
        errCode = Error::SessionCanceled;
    } else if (err.name() == SIGNOND_TIMED_OUT_ERR_NAME) {
        errCode = Error::TimedOut;
    } else if (err.name() == SIGNOND_INVALID_CREDENTIALS_ERR_NAME) {
        errCode = Error::InvalidCredentials;
    } else if (err.name() == SIGNOND_NOT_AUTHORIZED_ERR_NAME) {
        errCode = Error::NotAuthorized;
    } else if (err.name() == SIGNOND_OPERATION_NOT_SUPPORTED_ERR_NAME) {
        errCode = Error::OperationNotSupported;
    } else if (err.name() == SIGNOND_PERMISSION_DENIED_ERR_NAME) {
        errCode = Error::PermissionDenied;
    } else if (err.name() == SIGNOND_METHOD_OR_MECHANISM_NOT_ALLOWED_ERR_NAME) {
        errCode = Error::MethodOrMechanismNotAllowed;
    } else if (err.name() == SIGNOND_WRONG_STATE_ERR_NAME) {
        errCode = Error::WrongState;
    } else if (err.name() == SIGNOND_MECHANISM_NOT_AVAILABLE_ERR_NAME) {
        errCode = Error::MechanismNotAvailable;
    } else if (err.name() == SIGNOND_METHOD_NOT_KNOWN_ERR_NAME) {
        errCode = Error::MethodNotAvailable;
    } else if (err.name() == SIGNOND_MISSING_DATA_ERR_NAME) {
         errCode = Error::MissingData;
    } else if (err.name() == SIGNOND_RUNTIME_ERR_NAME) {
        errCode = Error::Runtime;
    } else if (err.name() == SIGNOND_NO_CONNECTION_ERR_NAME) {
        errCode = Error::NoConnection;
    } else if (err.name() == SIGNOND_NETWORK_ERR_NAME) {
        errCode = Error::Network;
    } else if (err.name() == SIGNOND_SSL_ERR_NAME) {
        errCode = Error::Ssl;
    } else if (err.name() == SIGNOND_USER_INTERACTION_ERR_NAME) {
        errCode = Error::UserInteraction;
    } else if (err.name() == SIGNOND_OPERATION_FAILED_ERR_NAME) {
        errCode = Error::OperationFailed;
    } else if (err.name() == SIGNOND_ENCRYPTION_FAILED_ERR_NAME) {
        errCode = Error::EncryptionFailure;
    } else if (err.name() == SIGNOND_TOS_NOT_ACCEPTED_ERR_NAME) {
        errCode = Error::TOSNotAccepted;
    } else if (err.name() == SIGNOND_FORGOT_PASSWORD_ERR_NAME) {
        errCode = Error::ForgotPassword;
    } else if (err.name() == SIGNOND_INCORRECT_DATE_ERR_NAME) {
        errCode = Error::IncorrectDate;
    } else if (err.name() == SIGNOND_USER_ERROR_ERR_NAME){
        //the error message comes in as "code:message"
        bool ok = false;
        errCode = err.message().section(QLatin1Char(':'), 0, 0).toInt(&ok);
        errMessage = err.message().section(QLatin1Char(':'), 1, 1);
        if (!ok)
            errCode = Error::Unknown;
    }

    if (m_isAuthInProcessing) {
        TRACE() << "Error while registering";
        m_isAuthInProcessing = false;

        m_dbusProxy.setError(err);
        // Forces a reinitialization of the proxy
        m_dbusProxy.setObjectPath(QDBusObjectPath());
        return;
    }

    if (errMessage.isEmpty())
        errMessage = err.message();

    emit m_parent->error(Error(errCode, errMessage));
}

void AuthSessionImpl::authenticationSlot(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QDBusObjectPath> reply = *call;
    m_dbusProxy.setObjectPath(reply.argumentAt<0>());

    m_isAuthInProcessing = false;
}

void AuthSessionImpl::deleteServiceProxy()
{
    PendingCall *call = qobject_cast<PendingCall*>(sender());
    /* This destroys the AsyncDBusProxy which we created just for registering
     * the authsession. */
    call->parent()->deleteLater();
}

void AuthSessionImpl::mechanismsAvailableSlot(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QStringList> reply = *call;
    QStringList mechanisms = reply.argumentAt<0>();
    emit m_parent->mechanismsAvailable(mechanisms);
}

void AuthSessionImpl::responseSlot(QDBusPendingCallWatcher *call)
{
    m_processCall = 0;

    QDBusPendingReply<QVariantMap> reply = *call;
    QVariantMap sessionDataVa = reply.argumentAt<0>();
    emit m_parent->response(SessionData(sessionDataVa));
}

void AuthSessionImpl::stateSlot(int state, const QString &message)
{
    emit m_parent->stateChanged((AuthSession::AuthSessionState)state, message);
}

void AuthSessionImpl::unregisteredSlot()
{
    m_dbusProxy.setObjectPath(QDBusObjectPath());
}
