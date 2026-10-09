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
#ifndef IDENTITYIMPL_H
#define IDENTITYIMPL_H

#include <QObject>
#include <QByteArray>
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QMetaMethod>
#include <QQueue>
#include <QDBusObjectPath>

#include "async-dbus-proxy.h"
#include "libsignoncommon.h"
#include "identity.h"
#include "dbusinterface.h"

namespace SignOn {

class IdentityInfo;

/*!
 * @class IdentityImpl
 * Identity class implementation.
 * @sa Identity
 */
class IdentityImpl: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(IdentityImpl)

    friend class Identity;

public:
    enum State {
        PendingRegistration = 0, /* Ongoing registration */
        NeedsRegistration,       /* Remote object not created or destroyed */
        NeedsUpdate,             /* Remote data changed */
        PendingUpdate,           /* Update in progress */
        Removed,                 /* Removed from database */
        Ready,                   /* Ready for querying locally cached data, or
                                    any remote operation */
        LastState
    };

    IdentityImpl(Identity *parent,
                 const quint32 id = 0);
    ~IdentityImpl();

    quint32 id() const;
    AuthSession *createSession(const QString &methodName, QObject *parent = 0);
    void destroySession(AuthSession *session);

public Q_SLOTS:
    void errorReply(const QDBusError &err);
    void storeCredentialsReply(QDBusPendingCallWatcher *call);
    void removeReply();
    void addReferenceReply();
    void removeReferenceReply();
    void getInfoReply(QDBusPendingCallWatcher *call);
    void verifyUserReply(QDBusPendingCallWatcher *call);
    void verifySecretReply(QDBusPendingCallWatcher *call);
    void signOutReply();
    void infoUpdated(int);
    void remoteObjectDestroyed();

private Q_SLOTS:
    bool sendRegisterRequest();
    void queryAvailableMethods();
    void requestCredentialsUpdate(const QString &message = QString());
    void storeCredentials(const IdentityInfo &info);
    void remove();
    void addReference(const QString &reference = QString());
    void removeReference(const QString &reference = QString());
    void queryInfo();
    void verifyUser(const QString &message = QString());
    void verifyUser(const QVariantMap &params);
    void verifySecret(const QString &secret);
    void signOut();
    void authSessionCancelReply(const SignOn::Error &err);
    void registerReply(QDBusPendingCallWatcher *call);
    void deleteServiceProxy();

private:
    void copyInfo(const IdentityInfo &info);
    void updateState(State state);
    bool checkRemoved();

    void updateContents();
    void updateCachedData(const QVariantMap &infoData);
    void clearAuthSessionsCache();

private:
    Identity *m_parent;
    IdentityInfo *m_identityInfo;
    SignondAsyncDBusProxy m_dbusProxy;

    /* Cache info in the storing case, so that if the storing succeeds, server
     * side does not have to send succesfully stored data over IPC channel.
     */
    IdentityInfo *m_tmpIdentityInfo;
    State m_state;
    QList<AuthSession *> m_authSessions;

    /* This flag tells the queryInfo() reply slot to emit the info() signal */
    bool m_infoQueried;

    /* This flag tells the queryInfo() reply slot to emit the
     * methodsAvailable() signal */
    bool m_methodsQueried;

    /* Marks this Identity as the one which requested the sign out */
    bool m_signOutRequestedByThisIdentity;
};

}  // namespace SignOn

#endif /* IDENTITYIMPL_H */
