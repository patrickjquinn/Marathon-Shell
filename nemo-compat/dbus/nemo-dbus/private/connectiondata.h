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

#ifndef NEMODBUS_CONNECTIONDATA_H
#define NEMODBUS_CONNECTIONDATA_H

#include <nemo-dbus/dbus.h>
#include <nemo-dbus/response.h>

#include <nemo-dbus/private/propertychanges.h>

#include <QSharedData>

namespace NemoDBus {

class PropertyChanges;
class Response;

class NEMODBUS_EXPORT ConnectionData : public QObject, public QSharedData
{
    Q_OBJECT
public:
    ConnectionData(const QDBusConnection &connection, const QLoggingCategory &logs);
    ~ConnectionData();

    template <typename... Arguments>
    Response *call(
            QObject *context,
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &method,
            Arguments &&...arguments)
    {
        return callMethod(context, service, path, interface, method,
                marshallArguments(std::forward<Arguments>(arguments)...));
    }

    template <typename... Arguments>
    QDBusMessage blockingCall(
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &method,
            Arguments &&...arguments)
    {
        return blockingCallMethod(service, path, interface, method,
                marshallArguments(std::forward<Arguments>(arguments)...));
    }

    template <typename T, typename Handler>
    void subscribeToProperty(
            QObject *context,
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &property,
            const Handler &onChanged)
    {
        const auto subscription = subscribeToObject(context, service, path);

        QObject::connect(
                    subscription, &PropertyChanges::propertyChanged,
                    context,
                    [interface, property, onChanged](
                    const QString changedInterface, const QString &changedProperty, const QVariant &value) {
            if (interface == changedInterface && property == changedProperty) {
                onChanged(demarshallArgument<T>(value));
            }
        });

        QVariant value;
        if (getProperty(&value, connection, service, path, interface, property)) {
            onChanged(demarshallArgument<T>(value));
        }
    }

    bool getProperty(
            QVariant *value,
            const QDBusConnection &connection,
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &property);

    void connectToDisconnected();

    const QLoggingCategory &logs()
    {
        return m_logs;
    }

    QDBusConnection connection;
    QHash<QString, QHash<QString, PropertyChanges *>> propertyChanges;

signals:
    void connected();
    void disconnected();

private slots:
    void handleDisconnect();

private:
    Response *callMethod(
            QObject *context,
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &method,
            const QVariantList &arguments);
    QDBusMessage blockingCallMethod(
            const QString &service,
            const QString &path,
            const QString &interface,
            const QString &method,
            const QVariantList &arguments);
    PropertyChanges *subscribeToObject(QObject *context, const QString &service, const QString &path);

    void deletePropertyListeners();

    const QLoggingCategory &m_logs;
};

}

#endif
