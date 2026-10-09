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

#ifndef NEMODBUS_DBUS_H
#define NEMODBUS_DBUS_H

#include <nemo-dbus/global.h>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QVector>

namespace NemoDBus {

class Connection;

template <typename Argument> inline QVariant marshallArgument(const Argument &argument)
{
    return QVariant::fromValue(argument);
}

inline QVariant marshallArgument(const QVariant &argument)
{
    return QVariant::fromValue(QDBusVariant(argument));
}

template <typename Argument> inline Argument demarshallArgument(const QVariant &argument)
{
    if (argument.userType() == qMetaTypeId<QDBusArgument>()) {
        Argument demarshalled;
        argument.value<QDBusArgument>() >> demarshalled;
        return demarshalled;
    } else {
        return argument.value<Argument>();
    }
}

template <> inline QDBusArgument demarshallArgument<QDBusArgument>(const QVariant &argument)
{
    return argument.value<QDBusArgument>();
}

template <> inline QVariant demarshallArgument<QVariant>(const QVariant &argument)
{
    return argument.value<QDBusVariant>().variant();
}

inline void appendArguments(QVariantList &) {}

template<typename Argument, typename... Arguments>
inline void appendArguments(QVariantList &list, Argument &&value, Arguments &&...arguments)
{
    list.append(marshallArgument(std::forward<Argument>(value)));
    appendArguments(list, std::forward<Arguments>(arguments)...);
}

template <typename... Arguments> inline QVariantList marshallArguments(Arguments &&...arguments)
{
    QVariantList list;
    appendArguments(list, std::forward<Arguments>(arguments)...);
    return list;
}

template <typename... Arguments> inline bool send(
        const QDBusConnection &connection,
        const QString &path,
        const QString &interface,
        const QString &method,
        Arguments &&...arguments)
{
    QDBusMessage message = QDBusMessage::createMethodCall(QString(), path, interface, method);
    message.setArguments(marshallArguments(std::forward<Arguments>(arguments)...));
    return connection.send(message);
}

template <typename... Arguments> inline bool send(
        const QString &connectionName,
        const QString &path,
        const QString &interface,
        const QString &method,
        Arguments &&...arguments)
{
    return send(QDBusConnection(connectionName), path, interface, method,
            std::forward<Arguments>(arguments)...);
}

NEMODBUS_EXPORT QVariant demarshallDBusArgument(const QVariant &val, int depth = 0);
NEMODBUS_EXPORT void registerDBusTypes();

NEMODBUS_EXPORT Connection systemBus();
NEMODBUS_EXPORT Connection sessionBus();

}

#endif
