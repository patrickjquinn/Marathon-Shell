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

#ifndef NEMODBUS_OBJECT_H
#define NEMODBUS_OBJECT_H

#include <nemo-dbus/connection.h>

namespace NemoDBus {

class NEMODBUS_EXPORT Object
{
public:
    Object(QObject *context, const Connection &connection, const QString &service, const QString &path);
    virtual ~Object();

    QObject *context() const;
    QDBusConnection connection() const;
    QString service() const;
    QString path() const;

    template <typename... Arguments>
    Response *call(const QString &interface, const QString &method, Arguments &&...arguments)
    {
        return m_connection.call(m_context, m_service, m_path, interface, method,
                std::forward<Arguments>(arguments)...);
    }

    template <typename... Arguments>
    QDBusMessage blockingCall(const QString &interface, const QString &method, Arguments &&...arguments)
    {
        return m_connection.blockingCall(m_service, m_path, interface, method,
                std::forward<Arguments>(arguments)...);
    }

    template <typename T, typename Handler>
    void subscribeToProperty(const QString &interface, const QString &property,
                             const Handler &onChanged)
    {
        m_connection.subscribeToProperty<T>(m_context, m_service, m_path, interface, property, onChanged);
    }

    bool connectToSignal(const QString &interface, const QString &signal, const char *slot);

private:
    QObject *const m_context;
    Connection m_connection;
    const QString m_service;
    const QString m_path;
};

}

#endif
