// SPDX-FileCopyrightText: 2013-2016 Canonical Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
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

#include "connection-manager.h"
#include "debug.h"
#include "libsignoncommon.h"
#include "signond/signoncommon.h"

#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusPendingCallWatcher>
#include <QPointer>
#include <QProcessEnvironment>
#include <QStandardPaths>

using namespace SignOn;

static QPointer<ConnectionManager> connectionInstance = 0;

ConnectionManager::ConnectionManager(QObject *parent):
    QObject(parent),
    m_connection(QLatin1String("libsignon-qt-invalid")),
    m_serviceStatus(ServiceStatusUnknown),
    m_retryCount(0)
{
    if (connectionInstance == 0) {
        init();
        connectionInstance = this;
    } else {
        BLAME() << "SignOn::ConnectionManager instantiated more than once!";
    }
}

ConnectionManager::~ConnectionManager()
{
}

ConnectionManager *ConnectionManager::instance()
{
    if (connectionInstance == 0) {
        connectionInstance = new ConnectionManager;
    }
    return connectionInstance;
}

void ConnectionManager::connect()
{
    if (m_connection.isConnected()) {
        Q_EMIT connected(m_connection);
    } else {
        init();
    }
}

bool ConnectionManager::hasConnection() const
{
    return m_connection.isConnected();
}

ConnectionManager::SocketConnectionStatus
ConnectionManager::setupSocketConnection()
{
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    QLatin1String one("1");
    if (environment.value(QLatin1String("SSO_USE_PEER_BUS"), one) != one) {
        return SocketConnectionUnavailable;
    }

    QString runtimeDir =
        QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) return SocketConnectionUnavailable;

    QString socketFileName =
        QString::fromLatin1("unix:path=%1/" SIGNOND_SOCKET_FILENAME).arg(runtimeDir);
    static int count = 0;

    QDBusConnection connection =
        QDBusConnection::connectToPeer(socketFileName,
                                       QString(QLatin1String("libsignon-qt%1")).arg(count++));
    if (!connection.isConnected()) {
        QDBusError error = connection.lastError();
        QString name = error.name();
        TRACE() << "p2p error:" << error << error.type();
        if (name == QLatin1String("org.freedesktop.DBus.Error.FileNotFound") &&
            m_serviceStatus != ServiceActivated) {
            return SocketConnectionNoService;
        } else {
            return SocketConnectionUnavailable;
        }
    }

    m_connection = connection;
    m_connection.connect(QString(),
                         QLatin1String("/org/freedesktop/DBus/Local"),
                         QLatin1String("org.freedesktop.DBus.Local"),
                         QLatin1String("Disconnected"),
                         this, SLOT(onDisconnected()));

    return SocketConnectionOk;
}

void ConnectionManager::init()
{
    if (m_serviceStatus == ServiceActivating) return;

    SocketConnectionStatus status = setupSocketConnection();

    if (status == SocketConnectionUnavailable) {
#ifdef ENABLE_P2P
        if (m_retryCount >= 15) {
            BLAME() << "Unable to activate p2p signond service!";
            return;
        }
        TRACE() << "Unable to activate p2p signond service, trying again";
        status = SocketConnectionNoService;
        m_retryCount += 1;
#else
        TRACE() << "Unable to activate p2p signond service, falling back to session bus";
        m_connection = SIGNOND_BUS;
#endif
    }

    if (status == SocketConnectionNoService) {
        TRACE() << "Peer connection unavailable, activating service";
        QDBusConnectionInterface *interface =
            QDBusConnection::sessionBus().interface();
        QDBusPendingCall call =
            interface->asyncCall(QLatin1String("StartServiceByName"),
                                 SIGNOND_SERVICE, uint(0));
        m_serviceStatus = ServiceActivating;
        QDBusPendingCallWatcher *watcher =
            new QDBusPendingCallWatcher(call, this);
        QObject::connect(watcher,
                         SIGNAL(finished(QDBusPendingCallWatcher*)),
                         this,
                         SLOT(onActivationDone(QDBusPendingCallWatcher*)));
    }

    if (m_connection.isConnected()) {
        m_retryCount = 0;
        TRACE() << "Connected to" << m_connection.name();
        Q_EMIT connected(m_connection);
    }
}

void ConnectionManager::onActivationDone(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<> reply(*watcher);
    watcher->deleteLater();

    if (!reply.isError()) {
        m_serviceStatus = ServiceActivated;
        /* Attempt to connect again */
        init();
    } else {
        BLAME() << reply.error();
    }
}

void ConnectionManager::onDisconnected()
{
    TRACE() << "Disconnected from daemon";
    m_serviceStatus = ServiceStatusUnknown;
    Q_EMIT disconnected();
}
