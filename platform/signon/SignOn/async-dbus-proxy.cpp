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

#include "async-dbus-proxy.h"

#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QMetaMethod>
#include <QMetaType>
#include <QPointer>

#include "connection-manager.h"
#include "dbusinterface.h"
#include "debug.h"
#include "libsignoncommon.h"
#include "signond/signoncommon.h"

using namespace SignOn;

namespace SignOn {

class Connection
{
public:
    Connection(const char *name, QObject *receiver, const char *slot):
        m_name(name),
        m_receiver(receiver),
        m_slot(slot)
    {
    }
    ~Connection() {}

    const char *m_name;
    QObject *m_receiver;
    const char *m_slot;
};

} // namespace

PendingCall::PendingCall(const QString &method,
                         const QList<QVariant> &args,
                         QObject *parent):
    QObject(parent),
    m_method(method),
    m_args(args),
    m_watcher(0),
    m_interfaceWasDestroyed(false)
{
}

PendingCall::~PendingCall()
{
}

bool PendingCall::cancel()
{
    if (m_watcher) {
        // Too late, can't cancel
        return false;
    }
    Q_EMIT finished(0);
    return true;
}

void PendingCall::doCall(QDBusAbstractInterface *interface)
{
    QDBusPendingCall call =
        interface->asyncCallWithArgumentList(m_method, m_args);
    m_watcher = new QDBusPendingCallWatcher(call, this);
    QObject::connect(m_watcher, SIGNAL(finished(QDBusPendingCallWatcher*)),
                     this, SLOT(onFinished(QDBusPendingCallWatcher*)));
    /* Check if the interface gets destroyed while our call executes */
    m_interfaceWasDestroyed = false;
    QObject::connect(interface, SIGNAL(destroyed()),
                     this, SLOT(onInterfaceDestroyed()));
}

void PendingCall::fail(const QDBusError &err)
{
    Q_EMIT error(err);
    Q_EMIT finished(0);
}

void PendingCall::onFinished(QDBusPendingCallWatcher *watcher)
{
    /* Check if the call failed because the interface became invalid; if
     * so, emit a signal to instruct the AsyncDBusProxy to re-queue this
     * operation. */
    if (m_interfaceWasDestroyed && watcher->isError()) {
        QDBusError::ErrorType type = watcher->error().type();
        if (type == QDBusError::Disconnected ||
            type == QDBusError::UnknownObject) {
            TRACE() << "emitting retry signal";
            Q_EMIT requeueRequested();
            return;
        }
    }

    QPointer<PendingCall> thisguard(this);
    QPointer<QDBusPendingCallWatcher> watcherguard(watcher);
    if (watcher->isError()) {
        Q_EMIT error(watcher->error());
    } else {
        Q_EMIT success(watcher);
    }
    if (thisguard) {
        Q_EMIT finished(watcherguard ? watcher : 0);
    }
}

void PendingCall::onInterfaceDestroyed()
{
    /* If the interface is destroyed during the lifetime of the call, this can
     * be because the remote object got destroyed or the D-Bus connection
     * dropped. In either case, we might have to re-queue our method call.
     *
     * This is done in the onFinished() slot; here we just record the event.
     */
    m_interfaceWasDestroyed = true;
}

AsyncDBusProxy::AsyncDBusProxy(const QString &service,
                               const char *interface,
                               QObject *clientObject):
    m_serviceName(service),
    m_interfaceName(interface),
    m_connection(NULL),
    m_clientObject(clientObject),
    m_interface(NULL),
    m_status(Incomplete)
{
}

AsyncDBusProxy::~AsyncDBusProxy()
{
    qDeleteAll(m_connectionsQueue);
    m_connectionsQueue.clear();

    delete m_connection;
}

void AsyncDBusProxy::setStatus(Status status)
{
    m_status = status;

    if (status == Ready) {
        /* connect the signals and execute all pending methods */
        Q_FOREACH(Connection *connection, m_connectionsQueue) {
            m_interface->connect(connection->m_name,
                                 connection->m_receiver,
                                 connection->m_slot);
        }

        Q_FOREACH(PendingCall *call, m_operationsQueue) {
            call->doCall(m_interface);
        }
        m_operationsQueue.clear();
    } else if (status == Invalid) {
        /* signal error on all operations */
        Q_FOREACH(PendingCall *call, m_operationsQueue) {
            call->fail(m_lastError);
        }
        m_operationsQueue.clear();
    }
}

void AsyncDBusProxy::update()
{
    if (m_interface != NULL) {
        delete m_interface;
        m_interface = 0;
    }

    if (m_connection == NULL || m_path.isEmpty()) {
        setStatus(Incomplete);
        return;
    }

    if (!m_connection->isConnected()) {
        setError(m_connection->lastError());
        return;
    }

    m_interface = new DBusInterface(m_serviceName,
                                    m_path,
                                    m_interfaceName,
                                    *m_connection,
                                    this);
    setStatus(Ready);
}

void AsyncDBusProxy::setConnection(const QDBusConnection &connection)
{
    delete m_connection;
    m_connection = new QDBusConnection(connection);
    update();
}

void AsyncDBusProxy::setDisconnected()
{
    TRACE();
    delete m_connection;
    m_connection = 0;
    /* The daemon is dead, so certainly the object paths are also invalid */
    m_path = QString();
    update();
}

void AsyncDBusProxy::setObjectPath(const QDBusObjectPath &objectPath)
{
    Q_ASSERT(m_path.isEmpty() || objectPath.path().isEmpty());
    m_path = objectPath.path();
    update();
}

void AsyncDBusProxy::setError(const QDBusError &error)
{
    TRACE() << error;
    m_lastError = error;
    setStatus(Invalid);
}

PendingCall *AsyncDBusProxy::queueCall(const QString &method,
                                       const QList<QVariant> &args,
                                       const char *replySlot,
                                       const char *errorSlot)
{
    return queueCall(method, args, m_clientObject, replySlot, errorSlot);
}

PendingCall *AsyncDBusProxy::queueCall(const QString &method,
                                       const QList<QVariant> &args,
                                       QObject *receiver,
                                       const char *replySlot,
                                       const char *errorSlot)
{
    PendingCall *call = new PendingCall(method, args, this);
    QObject::connect(call, SIGNAL(finished(QDBusPendingCallWatcher*)),
                     this, SLOT(onCallFinished(QDBusPendingCallWatcher*)));
    QObject::connect(call, SIGNAL(requeueRequested()),
                     this, SLOT(onRequeueRequested()));

    if (errorSlot) {
        QObject::connect(call, SIGNAL(error(const QDBusError&)),
                         receiver, errorSlot);
        if (replySlot) {
            QObject::connect(call, SIGNAL(success(QDBusPendingCallWatcher*)),
                             receiver, replySlot);
        }
    } else if (replySlot) {
        QObject::connect(call, SIGNAL(finished(QDBusPendingCallWatcher*)),
                         receiver, replySlot);
    }

    if (m_status == Ready) {
        call->doCall(m_interface);
    } else if (m_status == Incomplete) {
        enqueue(call);
    } else {
        QMetaObject::invokeMethod(call, "fail",
                                  Qt::QueuedConnection,
                                  Q_ARG(QDBusError, m_lastError));
    }
    return call;
}

bool AsyncDBusProxy::connect(const char *name,
                             QObject *receiver,
                             const char *slot)
{
    /* Remember all the connections anyway, because we'll re-play them if we
     * disconnect and reconnect again */
    Connection *connection = new Connection(name, receiver, slot);
    m_connectionsQueue.enqueue(connection);

    if (m_status == Ready) {
        return m_interface->connect(name, receiver, slot);
    }
    return true;
}

void AsyncDBusProxy::enqueue(PendingCall *call)
{
    m_operationsQueue.enqueue(call);
    if (!m_connection) {
        Q_EMIT connectionNeeded();
    }
    if (m_path.isEmpty()) {
        Q_EMIT objectPathNeeded();
    }
}

void AsyncDBusProxy::onCallFinished(QDBusPendingCallWatcher *watcher)
{
    Q_UNUSED(watcher);
    PendingCall *call = qobject_cast<PendingCall*>(sender());
    m_operationsQueue.removeOne(call);
    call->deleteLater();
}

void AsyncDBusProxy::onRequeueRequested()
{
    PendingCall *call = qobject_cast<PendingCall*>(sender());
    enqueue(call);
}

SignondAsyncDBusProxy::SignondAsyncDBusProxy(const char *interface,
                                             QObject *clientObject):
    AsyncDBusProxy(SIGNOND_SERVICE, interface, clientObject)
{
    setupConnection();
}

SignondAsyncDBusProxy::~SignondAsyncDBusProxy()
{
}

void SignondAsyncDBusProxy::setupConnection()
{
    ConnectionManager *connManager = ConnectionManager::instance();
    QObject::connect(connManager, SIGNAL(connected(const QDBusConnection&)),
                     this, SLOT(setConnection(const QDBusConnection&)));
    QObject::connect(connManager, SIGNAL(disconnected()),
                     this, SLOT(setDisconnected()));
    QObject::connect(this, SIGNAL(connectionNeeded()),
                     connManager, SLOT(connect()));
    if (connManager->hasConnection()) {
        setConnection(connManager->connection());
    }
}
