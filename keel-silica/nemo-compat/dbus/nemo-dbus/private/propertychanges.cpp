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

#include "propertychanges.h"

#include "connectiondata.h"
#include "response.h"

#include "logging.h"

namespace NemoDBus {

PropertyChanges::PropertyChanges(ConnectionData *cache, const QString &service, const QString &path)
    : QObject(cache)
    , m_cache(cache)
    , m_service(service)
    , m_path(path)
{
}

PropertyChanges::~PropertyChanges()
{
}

void PropertyChanges::addSubscriber(QObject *subscriber)
{
    if (!m_subscribers.contains(subscriber)) {
        connect(subscriber, &QObject::destroyed, this, &PropertyChanges::subscriberDestroyed);

        m_subscribers.append(subscriber);
    }
}

void PropertyChanges::subscriberDestroyed(QObject *subscriber)
{
    m_subscribers.removeOne(subscriber);

    if (m_subscribers.isEmpty()) {
        for (auto &services : m_cache->propertyChanges) {
            for (auto it = services.begin(); it != services.end(); ++it) {
                if (*it == this) {
                    services.erase(it);
                    break;
                }
            }
        }
        delete this;
    }
}

void PropertyChanges::getProperty(const QString &interface, const QString &property)
{
    auto response = m_cache->call(
                this,
                m_service,
                m_path,
                QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("Get"),
                interface,
                property);

    response->onFinished<QVariant>([this, interface, property](const QVariant &value) {
        emit propertyChanged(interface, property, value);
    });
}

void PropertyChanges::propertiesChanged(
        const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    for (auto it = changed.begin(); it != changed.end(); ++it) {
        qCDebug(m_cache->logs(), "DBus property changed (%s %s %s.%s)",
                qPrintable(m_service), qPrintable(m_path), qPrintable(interface), qPrintable(it.key()));

        emit propertyChanged(interface, it.key(), it.value());
    }

    for (auto property : invalidated) {
        qCDebug(m_cache->logs(), "DBus property changed (%s %s %s.%s)",
                qPrintable(m_service), qPrintable(m_path), qPrintable(interface), qPrintable(property));

        getProperty(interface, property);
    }
}

}
