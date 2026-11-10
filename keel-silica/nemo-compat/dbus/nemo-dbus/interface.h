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

#ifndef NEMODBUS_INTERFACE_H
#define NEMODBUS_INTERFACE_H

#include <nemo-dbus/object.h>

namespace NemoDBus {

class NEMODBUS_EXPORT Interface : private Object
{
public:
    Interface(
            QObject *context,
            const Connection &connection,
            const QString &service,
            const QString &path,
            const QString &interface);
    ~Interface();

    using Object::context;
    using Object::connection;
    using Object::service;
    using Object::path;

    QString interface() const;

    template <typename... Arguments>
    Response *call(const QString &method, Arguments &&...arguments)
    {
        return Object::call(m_interface, method, std::forward<Arguments>(arguments)...);
    }

    template <typename... Arguments>
    QDBusMessage blockingCall(const QString &method, Arguments &&...arguments)
    {
        return Object::blockingCall(m_interface, method, std::forward<Arguments>(arguments)...);
    }

    template <typename T, typename Handler>
    void subscribeToProperty(const QString &property, const Handler &onChanged)
    {
        Object::subscribeToProperty<T>(m_interface, property, onChanged);
    }

    bool connectToSignal(const QString &signal, const char *slot);

private:
    QString m_interface;
};

}

#endif
