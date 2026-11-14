// SPDX-FileCopyrightText: 2016 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2016 - 2021 Jolla Ltd.
 * Copyright (C) 2021 Open Mobile Platform LLC.
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

// Modified for Keel (Qt6), 2026 Shipwright: built-in type check in
// demarshallDBusArgument(). See keel/nemo-compat/PROVENANCE.md.

#include "dbus.h"
#include "connection.h"

#include <QThreadStorage>
#include <QDBusMetaType>
#include <QDBusUnixFileDescriptor>
#include <QDebug>

namespace NemoDBus {

class SystemBus : public Connection
{
public:
    SystemBus()
        : Connection(QDBusConnection::systemBus())
    {
    }
};

class SessionBus : public Connection
{
public:
    SessionBus()
        : Connection(QDBusConnection::sessionBus())
    {
    }
};

Connection systemBus()
{
    static QThreadStorage<SystemBus> bus;

    return bus.localData();
}

Connection sessionBus()
{
    static QThreadStorage<SessionBus> bus;

    return bus.localData();
}

QVariant demarshallDBusArgument(const QVariant &val, int depth)
{
    // Make sure that dbus types are registered.
    registerDBusTypes();

    /* Limit recursion depth to protect against type conversions
     * that fail to converge to basic qt types within qt variant.
     *
     * Using limit >= DBUS_MAXIMUM_TYPE_RECURSION_DEPTH (=32) should
     * mean we do not bail out too soon on deeply nested but othewise
     * valid dbus messages. */
    static const int maximum_dept = 32;

    /* Default to QVariant with isInvalid() == true */
    QVariant res;

    const int type = val.userType();

    if (++depth > maximum_dept) {
        /* Leave result to invalid variant */
        qWarning() << "Too deep recursion detected at userType:" << type;
    } else if (type == QVariant::ByteArray) {
        /* Is built-in type, but does not get correctly converted
         * to qml domain -> convert to variant list */
        QByteArray arr = val.toByteArray();
        QVariantList lst;
        for (int i = 0; i < arr.size(); ++i)
            lst << QVariant::fromValue(static_cast<quint8>(arr[i]));
        res = QVariant::fromValue(lst);
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    } else if (type < QMetaType::User) {
        // Keel: in Qt 6 typeId() always equals userType(), so the upstream
        // comparison treated QDBusVariant and QDBusArgument as built-in types
        // and returned them unconverted.
#else
    } else if (type == val.type()) {
#endif
        /* Already is built-in qt type, use as is */
        res = val;
    } else if (type == qMetaTypeId<QDBusVariant>()) {
        /* Convert QDBusVariant to QVariant */
        res = demarshallDBusArgument(val.value<QDBusVariant>().variant(), depth);
    } else if (type == qMetaTypeId<QDBusObjectPath>()) {
        /* Convert QDBusObjectPath to QString */
        res = val.value<QDBusObjectPath>().path();
    } else if (type == qMetaTypeId<QDBusSignature>()) {
        /* Convert QDBusSignature to QString */
        res = val.value<QDBusSignature>().signature();
    } else if (type == qMetaTypeId<QDBusUnixFileDescriptor>()) {
        /* Ignore, leave it to the receiver to extract the file descriptor */
        res = val;
    } else if (type == qMetaTypeId<QDBusArgument>()) {
        /* Try to deal with everything QDBusArgument could be ... */
        const QDBusArgument &arg = val.value<QDBusArgument>();
        const QDBusArgument::ElementType elem = arg.currentType();
        switch (elem) {
        case QDBusArgument::BasicType:
            /* Most of the basic types should be convertible to QVariant.
             * Recurse anyway to deal with object paths and the like. */
            res = demarshallDBusArgument(arg.asVariant(), depth);
            break;

        case QDBusArgument::VariantType:
            /* Try to convert to QVariant. Recurse to check content */
            res = demarshallDBusArgument(arg.asVariant().value<QDBusVariant>().variant(),
                                         depth);
            break;

        case QDBusArgument::ArrayType:
            /* Convert dbus array to QVariantList */
            {
                QVariantList list;
                arg.beginArray();
                while (!arg.atEnd()) {
                    QVariant tmp = arg.asVariant();
                    list.append(demarshallDBusArgument(tmp, depth));
                }
                arg.endArray();
                res = list;
            }
            break;

        case QDBusArgument::StructureType:
            /* Convert dbus struct to QVariantList */
            {
                QVariantList list;
                arg.beginStructure();
                while (!arg.atEnd()) {
                    QVariant tmp = arg.asVariant();
                    list.append(demarshallDBusArgument(tmp, depth));
                }
                arg.endStructure();
                res = QVariant::fromValue(list);
            }
            break;

        case QDBusArgument::MapType:
            /* Convert dbus dict to QVariantMap */
            {
                QVariantMap map;
                arg.beginMap();
                while (!arg.atEnd()) {
                    arg.beginMapEntry();
                    QVariant key = arg.asVariant();
                    QVariant val = arg.asVariant();
                    map.insert(demarshallDBusArgument(key, depth).toString(),
                               demarshallDBusArgument(val, depth));
                    arg.endMapEntry();
                }
                arg.endMap();
                res = map;
            }
            break;

        default:
            /* Unhandled types produce invalid QVariant */
            qWarning() << "Unhandled QDBusArgument element type:" << elem;
            break;
        }
    } else {
        /* Default to using as is. This should leave for example QDBusError
         * types in a form that does not look like a string to qml code. */
        res = val;
        qWarning() << "Unhandled QVariant userType:" << type;
    }

    return res;
}

void registerDBusTypes()
{
    static bool done = false;

    if (!done) {
        done = true;

        qDBusRegisterMetaType< QList<bool> >();
        qDBusRegisterMetaType< QList<int> >();
        qDBusRegisterMetaType< QList<double> >();

        qDBusRegisterMetaType< QList<quint8> >();
        qDBusRegisterMetaType< QList<quint16> >();
        qDBusRegisterMetaType< QList<quint32> >();
        qDBusRegisterMetaType< QList<quint64> >();

        qDBusRegisterMetaType< QList<qint16> >();
        qDBusRegisterMetaType< QList<qint32> >();
        qDBusRegisterMetaType< QList<qint64> >();
    }
}

}
