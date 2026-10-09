// SPDX-FileCopyrightText: 2016 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2016 Jolla Ltd
 * Contact: Andrew den Exter <andrew.den.exter@jolla.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of the copyright holder nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "connection.h"
#include "connectiondata.h"

#include "logging.h"

typedef QExplicitlySharedDataPointer<NemoDBus::ConnectionData> ConnectionDataPointer;
Q_DECLARE_METATYPE(ConnectionDataPointer)

namespace NemoDBus {

ConnectionData::ConnectionData(const QDBusConnection &connection, const QLoggingCategory &logs)
    : connection(connection)
    , m_logs(logs)
{
    if (connection.isConnected()) {
        qCDebug(logs, "Connected to %s", qPrintable(connection.name()));

        connectToDisconnected();
    } else {
        qCWarning(logs, "Connection to %s failed.  %s",
                  qPrintable(connection.name()), qPrintable(connection.lastError().message()));
    }
}

ConnectionData::~ConnectionData()
{
    deletePropertyListeners();
}

bool ConnectionData::getProperty(
        QVariant *value,
        const QDBusConnection &connection,
        const QString &service,
        const QString &path,
        const QString &interface,
        const QString &property)
{
    auto message = QDBusMessage::createMethodCall(
                service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    message.setArguments(marshallArguments(interface, property));

    const auto reply = connection.call(message);

    if (reply.type() == QDBusMessage::ReplyMessage) {
        *value = reply.arguments().value(0).value<QDBusVariant>().variant();

        return true;
    } else {
        qCWarning(logs(), "DBus error (%s %s org.freedesktop.DBus.Properties.Get): %s",
                  qPrintable(service),
                  qPrintable(path),
                  qPrintable(reply.errorMessage()));
        return false;
    }
}

void ConnectionData::connectToDisconnected()
{
    if (!connection.connect(
                QString(),
                QStringLiteral("/org/freedesktop/DBus/Local"),
                QStringLiteral("org.freedesktop.DBus.Local"),
                QStringLiteral("Disconnected"),
                this,
                SIGNAL(handleDisconnect()))) {
        qCWarning(logs(), "Failed to connection to connection disconnected signal");
    }
}

void ConnectionData::handleDisconnect()
{
    qCDebug(logs(), "Disconnected from %s", qPrintable(connection.name()));

    deletePropertyListeners();

    emit disconnected();
}

void ConnectionData::deletePropertyListeners()
{
    const auto services = propertyChanges;
    propertyChanges.clear();

    for (auto changes : services) {
        qDeleteAll(changes);
    }
}

Response *ConnectionData::callMethod(
        QObject *context,
        const QString &service,
        const QString &path,
        const QString &interface,
        const QString &method,
        const QVariantList &arguments)
{
    qCDebug(logs(), "DBus invocation (%s %s %s.%s)",
            qPrintable(service), qPrintable(path), qPrintable(interface), qPrintable(method));

    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(arguments);

    const auto response = new Response(m_logs, context);
    // Setting the connection as a dynamic property of the response will keep a reference to it
    // alive until after the the response's QObject destructor has executed.  This is important
    // because the object may have a queued QDBusCallDeliveryEvent containing a reference to the
    // connection which could be stale if all other references to the connection are freed before
    // the response is destroyed.
    response->setProperty("connection", QVariant::fromValue(ConnectionDataPointer(this)));
    connection.callWithCallback(
                message,
                response,
                SLOT(callReturn(QDBusMessage)),
                SLOT(callError(QDBusError,QDBusMessage)));

    return response;
}

QDBusMessage ConnectionData::blockingCallMethod(
        const QString &service,
        const QString &path,
        const QString &interface,
        const QString &method,
        const QVariantList &arguments)
{
    qCDebug(logs(), "DBus invocation (%s %s %s.%s)",
            qPrintable(service), qPrintable(path), qPrintable(interface), qPrintable(method));

    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(arguments);

    return connection.call(message);
}

PropertyChanges *ConnectionData::subscribeToObject(
        QObject *context, const QString &service, const QString &path)
{
    auto &changes = propertyChanges[service][path];
    if (!changes) {
        changes = new PropertyChanges(this, service, path);
        connection.connect(
                    service,
                    path,
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("PropertiesChanged"),
                    changes,
                    SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
    }

    changes->addSubscriber(context);

    return changes;
}

Connection::Connection(const QDBusConnection &connection)
    : Connection(connection, dbus())
{
}

Connection::Connection(const QDBusConnection &connection, const QLoggingCategory &logs)
    : d(new ConnectionData(connection, logs))
{
}

Connection::Connection(const Connection &connection)
    : d(connection.d)
{
}

Connection::~Connection()
{
}

QDBusConnection Connection::connection() const
{
    return d->connection;
}

bool Connection::isConnected() const
{
    return d->connection.isConnected();
}

bool Connection::reconnect(const QDBusConnection &connection)
{
    d->connection = connection;

    if (d->connection.isConnected()) {
        qCDebug(d->logs(), "Connected to %s", qPrintable(d->connection.name()));

        d->connectToDisconnected();
        emit d->connected();

        return true;
    } else {
        qCWarning(d->logs(), "Connection to %s failed.  %s",
                  qPrintable(d->connection.name()), qPrintable(d->connection.lastError().message()));
        return false;
    }
}

bool Connection::connectToSignal(
        const QString &service,
        const QString &path,
        const QString &interface,
        const QString &signal,
        QObject *object,
        const char *slot)
{
    if (!d->connection.connect(service, path, interface,  signal, object, slot)) {
        qCWarning(d->logs(), "Failed to connect to (%s %s %s.%s)",
                  qPrintable(service), qPrintable(path), qPrintable(interface), qPrintable(signal));
        return false;
    } else {
        return true;
    }
}

bool Connection::registerObject(
        const QString &path, QObject *object, QDBusConnection::RegisterOptions options)
{
    if (!d->connection.registerObject(path, object, options)) {
        qCWarning(d->logs()) << "Failed to register object on path" << path << object;

        return false;
    } else {
        return true;
    }
}


}

