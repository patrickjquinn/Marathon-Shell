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
#include <stdarg.h>

#include <QByteArray>
#include <QDBusArgument>
#include <QDBusPendingReply>
#include <QTimer>

#include "signond/signoncommon.h"

#include "debug.h"
#include "libsignoncommon.h"
#include "identityimpl.h"
#include "identityinfo.h"
#include "identityinfoimpl.h"
#include "authsessionimpl.h"
#include "signonerror.h"

#define SIGNOND_AUTH_SESSION_CANCEL_TIMEOUT 5000 //ms

using namespace SignOn;

/* Keep these aligned with the State enum */
static const char *stateNames[] = {
    "PendingRegistration",
    "NeedsRegistration",
    "NeedsUpdate",
    "PendingUpdate",
    "Removed",
    "Ready",
};

static QString stateName(IdentityImpl::State state)
{
    return QLatin1String((state < IdentityImpl::LastState) ?
                         stateNames[state] : "Unknown");
}

IdentityImpl::IdentityImpl(Identity *parent, const quint32 id):
    QObject(parent),
    m_parent(parent),
    m_identityInfo(new IdentityInfo),
    m_dbusProxy(SIGNOND_IDENTITY_INTERFACE_C,
                this),
    m_tmpIdentityInfo(NULL),
    m_state(NeedsRegistration),
    m_infoQueried(true),
    m_methodsQueried(false),
    m_signOutRequestedByThisIdentity(false)
{
    m_dbusProxy.connect("infoUpdated", this, SLOT(infoUpdated(int)));
    m_dbusProxy.connect("unregistered", this, SLOT(remoteObjectDestroyed()));
    QObject::connect(&m_dbusProxy, SIGNAL(objectPathNeeded()),
                     this, SLOT(sendRegisterRequest()));

    m_identityInfo->setId(id);
    sendRegisterRequest();
}

IdentityImpl::~IdentityImpl()
{
    if (m_identityInfo)
        delete m_identityInfo;

    if (m_tmpIdentityInfo)
        delete m_tmpIdentityInfo;

    if (!m_authSessions.empty()) {
        foreach (AuthSession *session, m_authSessions)
            destroySession(session);
    }
}

void IdentityImpl::updateState(State state)
{
    TRACE() << "Updating state: " << stateName(state) << this;

    m_state = state;
    switch (state)
    {
    case NeedsUpdate:
        updateContents();
        break;
    default:
        break;
    }
}

void IdentityImpl::copyInfo(const IdentityInfo &info)
{
    *m_identityInfo->impl = *info.impl;
}

quint32 IdentityImpl::id() const
{
   return m_identityInfo->id();
}

AuthSession *IdentityImpl::createSession(const QString &methodName,
                                         QObject *parent)
{
    foreach (AuthSession *authSession, m_authSessions) {
        if (authSession->name() == methodName) {
            qWarning() << QString::fromLatin1(
                    "Authentication session for method "
                    "`%1` already requested.").arg(methodName);
            return 0;
        }
    }

    AuthSession *session = new AuthSession(id(), methodName, parent);
    m_authSessions.append(session);
    return session;
}

void IdentityImpl::destroySession(AuthSession *session)
{
    session->blockSignals(true);
    m_authSessions.removeOne(session);
    session->deleteLater();
}

void IdentityImpl::queryAvailableMethods()
{
    TRACE() << "Querying available identity authentication methods.";
    if (!checkRemoved()) return;

    if (m_state == Ready) {
        emit m_parent->methodsAvailable(m_identityInfo->methods());
        return;
    }

    m_methodsQueried = true;
    updateContents();
}

void IdentityImpl::requestCredentialsUpdate(const QString &message)
{
    TRACE() << "Requesting credentials update.";
    if (!checkRemoved()) return;

    QVariantList args;
    args << message;
    m_dbusProxy.queueCall(QLatin1String("requestCredentialsUpdate"),
                          args,
                          SLOT(storeCredentialsReply(QDBusPendingCallWatcher*)),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::storeCredentials(const IdentityInfo &info)
{
    TRACE() << "Storing credentials";

    if (m_state == Removed) {
        updateState(NeedsRegistration);
    }

    const IdentityInfo *localInfo = info.impl->isEmpty() ? m_identityInfo : &info;

    if (localInfo->impl->isEmpty()) {
        emit m_parent->error(
            Error(Error::StoreFailed,
                  QLatin1String("Invalid Identity data.")));
        return;
    }

    QVariantList args;
    QVariantMap map = localInfo->impl->toMap();
    map.insert(SIGNOND_IDENTITY_INFO_ID, m_identityInfo->id());
    args << map;

    m_dbusProxy.queueCall(QLatin1String("store"), args,
                          SLOT(storeCredentialsReply(QDBusPendingCallWatcher*)),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::remove()
{
    TRACE() << "Removing credentials.";

    /* If the Identity is not stored, it makes no sense to request a removal
     * -- this condition could be removed; there is the case when there is an
     * ongoing store operation.
     */

    if (id() != SIGNOND_NEW_IDENTITY) {
        m_dbusProxy.queueCall(QLatin1String("remove"),
                              QVariantList(),
                              SLOT(removeReply()),
                              SLOT(errorReply(const QDBusError&)));
    } else {
        emit m_parent->error(Error(Error::IdentityNotFound,
                                   QLatin1String("Remove request failed. The "
                                                 "identity is not stored")));
    }
}

void IdentityImpl::addReference(const QString &reference)
{
    TRACE() << "Adding reference to identity";
    if (!checkRemoved()) return;

    m_dbusProxy.queueCall(QLatin1String("addReference"),
                          QVariantList() << QVariant(reference),
                          SLOT(addReferenceReply()),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::removeReference(const QString &reference)
{
    TRACE() << "Removing reference from identity";
    if (!checkRemoved()) return;

    m_dbusProxy.queueCall(QLatin1String("removeReference"),
                          QVariantList() << QVariant(reference),
                          SLOT(removeReferenceReply()),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::queryInfo()
{
    TRACE() << "Querying info.";
    if (!checkRemoved()) return;

    if (m_state == Ready) {
        emit m_parent->info(IdentityInfo(*m_identityInfo));
        return;
    }

    m_infoQueried = true;
    updateContents();
}

void IdentityImpl::verifyUser(const QString &message)
{
    QVariantMap params;
    params.insert(QLatin1String("QueryMessage"), message);
    verifyUser(params);
}

void IdentityImpl::verifyUser(const QVariantMap &params)
{
    TRACE() << "Verifying user.";
    if (!checkRemoved()) return;

    m_dbusProxy.queueCall(QLatin1String("verifyUser"),
                          QVariantList() << params,
                          SLOT(verifyUserReply(QDBusPendingCallWatcher*)),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::verifySecret(const QString &secret)
{
    TRACE();
    if (!checkRemoved()) return;

    m_dbusProxy.queueCall(QLatin1String("verifySecret"),
                          QVariantList() << QVariant(secret),
                          SLOT(verifySecretReply(QDBusPendingCallWatcher*)),
                          SLOT(errorReply(const QDBusError&)));
}

void IdentityImpl::signOut()
{
    TRACE() << "Signing out.";
    if (!checkRemoved()) return;

    /* if this is a stored identity, inform server about signing out
       so that other client identity objects having the same id will
       be able to perform the operation.
    */
    if (id() != SIGNOND_NEW_IDENTITY) {
        m_dbusProxy.queueCall(QLatin1String("signOut"),
                              QVariantList(),
                              SLOT(signOutReply()),
                              SLOT(errorReply(const QDBusError&)));
        m_signOutRequestedByThisIdentity = true;
    }

    clearAuthSessionsCache();
}

void IdentityImpl::clearAuthSessionsCache()
{
    while (!m_authSessions.empty()) {
        AuthSession *session = m_authSessions.takeFirst();
        connect(session,
                SIGNAL(error(const SignOn::Error &)),
                this,
                SLOT(authSessionCancelReply(const SignOn::Error &)));

        session->cancel();
        QTimer::singleShot(SIGNOND_AUTH_SESSION_CANCEL_TIMEOUT,
                           session, SLOT(deleteLater()));
    }
}

void IdentityImpl::authSessionCancelReply(const SignOn::Error &err)
{
    TRACE() << "CANCEL SESSION REPLY";

    bool deleteTheSender = false;
    switch (err.type()) {
    /* fall trough */
    case Error::SessionCanceled:
    case Error::WrongState:
        deleteTheSender = true;
        break;
    default: break;
    }

    if (deleteTheSender) {
        QObject *sender = QObject::sender();
        if (sender) {
            TRACE() << "DELETING SESSION";
            sender->deleteLater();
        }
    }
}

void IdentityImpl::storeCredentialsReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<quint32> reply = *call;
    quint32 id = reply.argumentAt<0>();
    TRACE() << "stored id:" << id << "old id:" << this->id();
    if (m_tmpIdentityInfo) {
        *m_identityInfo = *m_tmpIdentityInfo;
        delete m_tmpIdentityInfo;
        m_tmpIdentityInfo = NULL;
    }

    if (id != this->id()) {
        m_identityInfo->setId(id);
        foreach (AuthSession *session, m_authSessions)
            session->impl->setId(id);
    }
    emit m_parent->credentialsStored(id);
}

void IdentityImpl::removeReply()
{
    m_identityInfo->impl->clear();
    updateState(Removed);
    emit m_parent->removed();
}

void IdentityImpl::addReferenceReply()
{
    emit m_parent->referenceAdded();
}

void IdentityImpl::removeReferenceReply()
{
    emit m_parent->referenceRemoved();
}

void IdentityImpl::getInfoReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QVariantMap> reply = *call;
    QVariantMap infoData = reply.argumentAt<0>();
    TRACE() << infoData;
    updateCachedData(infoData);
    updateState(Ready);

    if (m_infoQueried) {
        Q_EMIT m_parent->info(IdentityInfo(*m_identityInfo));
        m_infoQueried = false;
    }

    if (m_methodsQueried) {
        Q_EMIT m_parent->methodsAvailable(m_identityInfo->methods());
        m_methodsQueried = false;
    }
}

void IdentityImpl::verifyUserReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<bool> reply = *call;
    bool valid = reply.argumentAt<0>();
    emit m_parent->userVerified(valid);
}

void IdentityImpl::verifySecretReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<bool> reply = *call;
    bool valid = reply.argumentAt<0>();
    emit m_parent->secretVerified(valid);
}

void IdentityImpl::signOutReply()
{
    emit m_parent->signedOut();
}

void IdentityImpl::infoUpdated(int state)
{
    const char *stateStr;
    switch ((IdentityState)state) {
    /* Data updated on the server side. */
    case IdentityDataUpdated:
        updateState(NeedsUpdate);
        stateStr = "NeedsUpdate";
        break;
    /* Data removed on the server side. */
    case IdentityRemoved:
        updateState(Removed);
        stateStr = "Removed";
        break;
    /* A remote client identity signed out,
       thus server informed this object to do the same */
    case IdentitySignedOut:
        //if this is not the identity that requested the signing out
        if (!m_signOutRequestedByThisIdentity) {
            clearAuthSessionsCache();
            emit m_parent->signedOut();
        }
        stateStr = "SignedOut";
        break;
    default: stateStr = "Unknown";
        break;
    }
    TRACE() << "SERVER INFO UPDATED." << stateStr <<
        QString(QLatin1String(" %1 ")).arg(id());
}

void IdentityImpl::errorReply(const QDBusError& err)
{
    TRACE() << err;

    /* Signon specific errors */
    if (err.name() == SIGNOND_UNKNOWN_ERR_NAME) {
        emit m_parent->error(Error(Error::Unknown, err.message()));
        return;
    } else if (err.name() == SIGNOND_INTERNAL_SERVER_ERR_NAME) {
        emit m_parent->error(Error(Error::InternalServer, err.message()));
        return;
    } else if (err.name() == SIGNOND_PERMISSION_DENIED_ERR_NAME) {
        emit m_parent->error(Error(Error::PermissionDenied, err.message()));
        return;
    } else if (err.name() == SIGNOND_ENCRYPTION_FAILED_ERR_NAME) {
        emit m_parent->error(Error(Error::EncryptionFailure, err.message()));
        return;
    } else if (err.name() == SIGNOND_METHOD_NOT_AVAILABLE_ERR_NAME) {
        emit m_parent->error(Error(Error::MethodNotAvailable, err.message()));
        return;
    } else if (err.name() == SIGNOND_IDENTITY_NOT_FOUND_ERR_NAME) {
        emit m_parent->error(Error(Error::IdentityNotFound, err.message()));
        return;
    } else if (err.name() == SIGNOND_STORE_FAILED_ERR_NAME) {
        emit m_parent->error(Error(Error::StoreFailed, err.message()));
        if (m_tmpIdentityInfo) {
            delete m_tmpIdentityInfo;
            m_tmpIdentityInfo = NULL;
        }
        return;
    } else if (err.name() == SIGNOND_REMOVE_FAILED_ERR_NAME) {
        emit m_parent->error(Error(Error::RemoveFailed, err.message()));
        return;
    } else if (err.name() == SIGNOND_SIGNOUT_FAILED_ERR_NAME) {
        emit m_parent->error(Error(Error::SignOutFailed, err.message()));
        return;
    } else if (err.name() == SIGNOND_IDENTITY_OPERATION_CANCELED_ERR_NAME) {
        emit m_parent->error(Error(Error::IdentityOperationCanceled,
                                   err.message()));
        return;
    } else if (err.name() == SIGNOND_CREDENTIALS_NOT_AVAILABLE_ERR_NAME) {
        emit m_parent->error(Error(Error::CredentialsNotAvailable,
                                   err.message()));
        return;
    } else if (err.name() == SIGNOND_REFERENCE_NOT_FOUND_ERR_NAME) {
       emit m_parent->error(Error(Error::ReferenceNotFound, err.message()));
       return;
    } else if (err.name() == SIGNOND_FORGOT_PASSWORD_ERR_NAME) {
       emit m_parent->error(Error(Error::ForgotPassword, err.message()));
       return;
    } else {
        if (m_state == this->PendingRegistration)
            updateState(NeedsRegistration);

        TRACE() << "Non internal SSO error reply.";
    }

    /* Qt DBUS specific errors */
    if (err.type() != QDBusError::NoError) {
        emit m_parent->error(Error(Error::InternalCommunication,
                                   err.message()));
        return;
    }

    emit m_parent->error(Error(Error::Unknown, err.message()));
}

void IdentityImpl::updateContents()
{
    m_dbusProxy.queueCall(QLatin1String("getInfo"),
                          QVariantList(),
                          SLOT(getInfoReply(QDBusPendingCallWatcher*)),
                          SLOT(errorReply(const QDBusError&)));
    updateState(PendingUpdate);
}

bool IdentityImpl::sendRegisterRequest()
{
    if (m_state == PendingRegistration) return true;

    QVariantList args;
    QString registerMethodName = QLatin1String("registerNewIdentity");

    if (id() != SIGNOND_NEW_IDENTITY) {
        registerMethodName = QLatin1String("getIdentity");
        args << m_identityInfo->id();
    }

    /* TODO: implement the application security context */
    args << QLatin1String("*");
    SignondAsyncDBusProxy *authService =
        new SignondAsyncDBusProxy(SIGNOND_DAEMON_INTERFACE_C, this);
    authService->setObjectPath(QDBusObjectPath(SIGNOND_DAEMON_OBJECTPATH));

    PendingCall *call =
        authService->queueCall(registerMethodName,
                               args,
                               SLOT(registerReply(QDBusPendingCallWatcher*)),
                               SLOT(errorReply(const QDBusError&)));
    QObject::connect(call, SIGNAL(finished(QDBusPendingCallWatcher*)),
                     this, SLOT(deleteServiceProxy()));
    updateState(PendingRegistration);
    return true;
}

void IdentityImpl::updateCachedData(const QVariantMap &infoData)
{
    m_identityInfo->impl->updateFromMap(infoData);
}

void IdentityImpl::registerReply(QDBusPendingCallWatcher *call)
{
    QVariantList arguments = call->reply().arguments();
    if (arguments.count() > 1) {
        QDBusArgument info = arguments.at(1).value<QDBusArgument>();
        updateCachedData(qdbus_cast<QVariantMap>(info));
    }

    m_dbusProxy.setObjectPath(arguments.at(0).value<QDBusObjectPath>());
    updateState(Ready);
}

void IdentityImpl::deleteServiceProxy()
{
    PendingCall *call = qobject_cast<PendingCall*>(sender());
    /* This destroys the AsyncDBusProxy which we created just for registering
     * the identity. */
    call->parent()->deleteLater();
}

void IdentityImpl::remoteObjectDestroyed()
{
    TRACE();
    m_dbusProxy.setObjectPath(QDBusObjectPath());
    updateState(NeedsRegistration);
}

bool IdentityImpl::checkRemoved()
{
    if (m_state == Removed) {
        Q_EMIT m_parent->error(Error(Error::IdentityNotFound,
                                     QLatin1String("Removed from database.")));
        return false;
    }
    return true;
}
