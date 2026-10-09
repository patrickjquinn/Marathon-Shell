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

#ifndef SIGNON_ASYNC_DBUS_PROXY_H
#define SIGNON_ASYNC_DBUS_PROXY_H

#include <QDBusError>
#include <QObject>
#include <QQueue>
#include <QVariant>

class QDBusAbstractInterface;
class QDBusConnection;
class QDBusObjectPath;
class QDBusPendingCallWatcher;

/*
 * @cond IMPL
 */
namespace SignOn {

class AsyncDBusProxy;
class Connection;
class DBusInterface;

class PendingCall: public QObject
{
    Q_OBJECT

public:
    ~PendingCall();

    bool cancel();

Q_SIGNALS:
    void finished(QDBusPendingCallWatcher *watcher);
    void success(QDBusPendingCallWatcher *watcher);
    void error(const QDBusError &error);
    void requeueRequested();

private Q_SLOTS:
    void onFinished(QDBusPendingCallWatcher *watcher);
    void onInterfaceDestroyed();
    void fail(const QDBusError &error);

private:
    friend class AsyncDBusProxy;
    PendingCall(const QString &method,
                const QList<QVariant> &args,
                QObject *parent = 0);
    void doCall(QDBusAbstractInterface *interface);

private:
    QString m_method;
    QList<QVariant> m_args;
    QDBusPendingCallWatcher *m_watcher;
    bool m_interfaceWasDestroyed;
};

class AsyncDBusProxy: public QObject
{
    Q_OBJECT

public:
    AsyncDBusProxy(const QString &service,
                   const char *interface,
                   QObject *clientObject);
    ~AsyncDBusProxy();

    void setObjectPath(const QDBusObjectPath &objectPath);
    void setError(const QDBusError &error);

    PendingCall *queueCall(const QString &method,
                           const QList<QVariant> &args,
                           const char *replySlot = 0,
                           const char *errorSlot = 0);
    PendingCall *queueCall(const QString &method,
                           const QList<QVariant> &args,
                           QObject *receiver,
                           const char *replySlot,
                           const char *errorSlot);
    bool connect(const char *name, QObject *receiver, const char *slot);

public Q_SLOTS:
    void setConnection(const QDBusConnection &connection);
    void setDisconnected();

Q_SIGNALS:
    void connectionNeeded();
    void objectPathNeeded();

private:
    enum Status {
        Incomplete,
        Ready,
        Invalid
    };
    void setStatus(Status status);
    void update();
    void enqueue(PendingCall *call);

private Q_SLOTS:
    void onCallFinished(QDBusPendingCallWatcher *watcher);
    void onRequeueRequested();

private:
    QString m_serviceName;
    const char *m_interfaceName;
    QString m_path;
    QDBusConnection *m_connection;
    QObject *m_clientObject;
    QQueue<PendingCall *> m_operationsQueue;
    QQueue<Connection *> m_connectionsQueue;
    DBusInterface *m_interface;
    Status m_status;
    QDBusError m_lastError;
};

class SignondAsyncDBusProxy: public AsyncDBusProxy
{
    Q_OBJECT
public:
    SignondAsyncDBusProxy(const char *interface,
                          QObject *clientObject);
    ~SignondAsyncDBusProxy();

private:
    void setupConnection();
};

} //SignOn

/*
 * @endcond IMPL
 */

#endif // SIGNON_ASYNC_DBUS_PROXY_H
