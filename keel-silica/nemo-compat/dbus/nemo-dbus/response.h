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

#ifndef NEMODBUS_RESPONSE_H
#define NEMODBUS_RESPONSE_H

#include <nemo-dbus/dbus.h>

#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

namespace NemoDBus {

class NEMODBUS_EXPORT Response : public QObject
{
    Q_OBJECT
public:
    ~Response();

    template <typename... Arguments, typename Handler>
    void onFinished(const Handler &handler)
    {
        connect(this, &Response::success, [handler](const QVariantList &arguments) {
            invoke<Handler, Arguments...>(handler, arguments);
        });
    }

    template <typename T> void onError(const T &handler)
    {
        connect(this, &Response::failure, [handler](const QDBusError &error) {
            handler(error);
        });
    }

signals:
    void success(const QVariantList &arguments);
    void failure(const QDBusError &error);

private slots:
    void callReturn(const QDBusMessage &message);
    void callError(const QDBusError &error, const QDBusMessage &message);

private:
    friend class ConnectionData;

    template <typename Handler> static void invoke(const Handler &handler, const QVariantList &)
    {
        handler();
    }
    template <typename Handler, typename Argument0> static void invoke(
            const Handler &handler, const QVariantList &arguments)
    {
        handler(demarshallArgument<Argument0>(arguments.value(0)));
    }
    template <typename Handler, typename Argument0, typename Argument1> static void invoke(
            const Handler &handler, const QVariantList &arguments)
    {
        handler(demarshallArgument<Argument0>(arguments.value(0)),
                demarshallArgument<Argument1>(arguments.value(1)));
    }

    explicit Response(const QLoggingCategory &logs, QObject *parent);

    const QLoggingCategory &logs()
    {
        return m_logs;
    }

    const QLoggingCategory &m_logs;
};

}
#endif
