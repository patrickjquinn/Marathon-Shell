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
#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QTimer>

#include "signond/signoncommon.h"

#include "debug.h"
#include "libsignoncommon.h"
#include "identityinfo.h"
#include "identityinfoimpl.h"
#include "authserviceimpl.h"
#include "signonerror.h"

using namespace SignOn;

/* ----------------------- IdentityRegExp ----------------------- */

AuthService::IdentityRegExp::IdentityRegExp(const QString &pattern):
    m_pattern(pattern)
{
}

AuthService::IdentityRegExp::IdentityRegExp(const IdentityRegExp &src):
    m_pattern(src.pattern())
{
}

bool AuthService::IdentityRegExp::isValid() const
{
    return false;
}

QString AuthService::IdentityRegExp::pattern() const
{
    return m_pattern;
}

/* ----------------------- AuthServiceImpl ----------------------- */

AuthServiceImpl::AuthServiceImpl(AuthService *parent):
    QObject(parent),
    m_parent(parent),
    m_dbusProxy(SIGNOND_DAEMON_INTERFACE_C,
                this)
{
    TRACE();
    m_dbusProxy.setObjectPath(QDBusObjectPath(SIGNOND_DAEMON_OBJECTPATH));

    qDBusRegisterMetaType<MapList>();
}

AuthServiceImpl::~AuthServiceImpl()
{
}

void AuthServiceImpl::queryMethods()
{
    sendRequest(QLatin1String("queryMethods"),
                SLOT(queryMethodsReply(QDBusPendingCallWatcher*)),
                QVariantList());
}

void AuthServiceImpl::queryMechanisms(const QString &method)
{
    m_dbusProxy.queueCall(QLatin1String("queryMechanisms"),
                          QVariantList() << method,
                          SLOT(queryMechanismsReply(QDBusPendingCallWatcher*)),
                          SLOT(queryMechanismsError(const QDBusError&)));
    m_methodsForWhichMechsWereQueried.enqueue(method);
}

void AuthServiceImpl::queryIdentities(const AuthService::IdentityFilter &filter)
{
    if (!filter.isEmpty())
        TRACE() << "Querying identities with filter not implemented.";

    QVariantList args;
    QMap<QString, QVariant> filterMap;
    if (!filter.empty()) {
        QMapIterator<AuthService::IdentityFilterCriteria,
                     AuthService::IdentityRegExp> it(filter);

        while (it.hasNext()) {
            it.next();

            if (!it.value().isValid())
                continue;

            const char *criteriaStr = 0;
            switch ((AuthService::IdentityFilterCriteria)it.key()) {
            case AuthService::AuthMethod: criteriaStr = "AuthMethod"; break;
            case AuthService::Username: criteriaStr = "Username"; break;
            case AuthService::Realm: criteriaStr = "Realm"; break;
            case AuthService::Caption: criteriaStr = "Caption"; break;
            default: break;
            }
            filterMap.insert(QLatin1String(criteriaStr),
                             QVariant(it.value().pattern()));
        }

    }

    args << filterMap;
    /* TODO: implement the application security context */
    args << QLatin1String("*");

    sendRequest(QLatin1String("queryIdentities"),
                SLOT(queryIdentitiesReply(QDBusPendingCallWatcher*)),
                args);
}

void AuthServiceImpl::clear()
{
    sendRequest(QLatin1String("clear"),
                SLOT(clearReply()),
                QList<QVariant>());
}



void AuthServiceImpl::sendRequest(const QString &operation,
                                  const char *replySlot,
                                  const QList<QVariant> &args)
{
    m_dbusProxy.queueCall(operation, args,
                          replySlot,
                          SLOT(errorReply(const QDBusError&)));
}

void AuthServiceImpl::queryMethodsReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QStringList> reply = *call;
    QStringList methods = reply.argumentAt<0>();
    emit m_parent->methodsAvailable(methods);
}

void AuthServiceImpl::queryMechanismsReply(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QStringList> reply = *call;
    QStringList mechs = reply.argumentAt<0>();
    TRACE() << mechs;
    QString method;
    if (!m_methodsForWhichMechsWereQueried.empty())
        method = m_methodsForWhichMechsWereQueried.dequeue();

    emit m_parent->mechanismsAvailable(method, mechs);
}

void AuthServiceImpl::queryMechanismsError(const QDBusError &err)
{
    if (!m_methodsForWhichMechsWereQueried.empty()) {
        m_methodsForWhichMechsWereQueried.dequeue();
    }

    errorReply(err);
}

void AuthServiceImpl::queryIdentitiesReply(QDBusPendingCallWatcher *call)
{
    QDBusMessage msg = call->reply();
    QList<QVariant> args = msg.arguments();
    if (args.isEmpty()) {
        BLAME() << "Invalid reply: no arguments";
        return;
    }

    QDBusArgument arg = args[0].value<QDBusArgument>();
    MapList identitiesData = qdbus_cast<MapList>(arg);

    QList<IdentityInfo> infoList;
    foreach (const QVariantMap &map, identitiesData) {
        IdentityInfo info;
        info.impl->updateFromMap(map);
        infoList.append(info);
    }

    emit m_parent->identities(infoList);
}

void AuthServiceImpl::clearReply()
{
    emit m_parent->cleared();
}

void AuthServiceImpl::errorReply(const QDBusError &err)
{
    TRACE();

    /* Signon specific errors */
    if (err.name() == SIGNOND_UNKNOWN_ERR_NAME) {
        emit m_parent->error(Error(Error::Unknown, err.message()));
        return;
    } else if (err.name() == SIGNOND_INTERNAL_SERVER_ERR_NAME) {
        emit m_parent->error(Error(Error::InternalServer, err.message()));
        return;
    } else if (err.name() == SIGNOND_METHOD_NOT_KNOWN_ERR_NAME) {
        emit m_parent->error(Error(Error::MethodNotKnown, err.message()));
        return;
    } else if (err.name() == SIGNOND_INVALID_QUERY_ERR_NAME) {
        emit m_parent->error(Error(Error::InvalidQuery, err.message()));
        return;
    } else if (err.name() == SIGNOND_PERMISSION_DENIED_ERR_NAME) {
        emit m_parent->error(Error(Error::PermissionDenied, err.message()));
        return;
    }

    /* Qt DBUS specific errors */
    if (err.type() != QDBusError::NoError) {
        emit m_parent->error(Error(Error::InternalCommunication, err.message()));
        return;
    }

    emit m_parent->error(Error(Error::Unknown, err.message()));
}
