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

#ifndef SIGNON_CONNECTION_MANAGER_H
#define SIGNON_CONNECTION_MANAGER_H

#include <QDBusConnection>
#include <QObject>

class QDBusPendingCallWatcher;

namespace SignOn {

class ConnectionManager: public QObject
{
    Q_OBJECT

    enum SocketConnectionStatus {
        SocketConnectionOk = 0,
        SocketConnectionUnavailable,
        SocketConnectionNoService
    };

    enum ServiceStatus {
        ServiceStatusUnknown = 0,
        ServiceActivating,
        ServiceActivated
    };

public:
    ConnectionManager(QObject *parent = 0);
    ~ConnectionManager();

    static ConnectionManager *instance();

    bool hasConnection() const;
    const QDBusConnection &connection() const { return m_connection; }
    static const QDBusConnection &get() { return instance()->connection(); }

public Q_SLOTS:
    void connect();

Q_SIGNALS:
    void connected(const QDBusConnection &connection);
    void disconnected();

private:
    SocketConnectionStatus setupSocketConnection();
    void init();

private Q_SLOTS:
    void onActivationDone(QDBusPendingCallWatcher *watcher);
    void onDisconnected();

private:
    QDBusConnection m_connection;
    ServiceStatus m_serviceStatus;
    int m_retryCount;
};

}

#endif // SIGNON_CONNECTION_MANAGER_H
