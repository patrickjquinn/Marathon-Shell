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

#ifndef AUTHSESSIONIMPL_H
#define AUTHSESSIONIMPL_H

#include <QObject>
#include <QByteArray>
#include <QMap>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QQueue>
#include <QDateTime>

#include "async-dbus-proxy.h"
#include "authsession.h"
#include "dbusinterface.h"

namespace SignOn {

/*!
 * @class AuthSessionImpl
 * AuthSession class implementation.
 * @sa AuthSession
 */
class AuthSessionImpl: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(AuthSessionImpl)

    friend class AuthSession;
    friend class IdentityImpl;

public:
    AuthSessionImpl(AuthSession *parent, quint32 id,
                    const QString &methodName,
                    const QString &applicationContext = QStringLiteral("*"));
    ~AuthSessionImpl();

public Q_SLOTS:
    QString name();
    void queryAvailableMechanisms(const QStringList &wantedMechanisms);
    void process(const SessionData &sessionData, const QString &mechanism);
    void cancel();

private Q_SLOTS:
    bool initInterface();
    void ignoreError(const QDBusError &err);
    void errorSlot(const QDBusError &err);
    void authenticationSlot(QDBusPendingCallWatcher *call);
    void deleteServiceProxy();
    void mechanismsAvailableSlot(QDBusPendingCallWatcher *call);
    void responseSlot(QDBusPendingCallWatcher *call);
    void stateSlot(int state, const QString &message);
    void unregisteredSlot();

private:
    PendingCall *send2interface(const QString &operation,
                                const char *slot,
                                const QVariantList &arguments);
    void setId(quint32 id);

private:
    AuthSession *m_parent;
    SignondAsyncDBusProxy m_dbusProxy;
    quint32 m_id;
    QString m_applicationContext;
    QString m_methodName;

    /*
     * flag to prevent multiple authentication requests
     */
    bool m_isAuthInProcessing;

    /*
     * Handle to process operation
     */
    QPointer<PendingCall> m_processCall;
};

} //namespace SignOn

#endif //AUTHSESSIONIMPL_H
