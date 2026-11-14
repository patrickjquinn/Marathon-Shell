// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2021 deloptes@gmail.com
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 *               2021 Updated to use bluez5 by deloptes@gmail.com
 *
 * Contact: Sateesh Kavuri <sateesh.kavuri@nokia.com>
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
 *
 */

#include <QDebug>
#include <LogMacros.h>

#include "BtCommon.h"
#include "BtHelper.h"

using namespace Buteo;

// big help was found here
// https://github.com/zeenix/bluetooth-demo/blob/master/blueconnect.cpp

BtHelper::BtHelper(const QString &deviceAddress, QObject* parent)
    : QObject(parent),
      m_SystemBus(QDBusConnection::systemBus())
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

#ifdef HAVE_BLUEZ_5
    qDBusRegisterMetaType <InterfacesMap> ();
    qDBusRegisterMetaType <ObjectsMap> ();

    QDBusInterface managerInterface( BT::BLUEZ_DEST, QString("/"),
            BT::BLUEZ_MANAGER_INTERFACE,
            m_SystemBus );

    QDBusReply<ObjectsMap> reply = managerInterface.call(BT::GETMANAGEDOBJECTS);
    if (!reply.isValid()) {
        qCWarning(lcButeoCore) << "Failed to connect to ObjectManager: " << reply.error().message();
    } else {

        ObjectsMap objects = reply.value();
        for (ObjectsMap::iterator i = objects.begin(); i != objects.end(); ++i) {

            InterfacesMap ifaces = i.value();
            for (InterfacesMap::iterator j = ifaces.begin(); j != ifaces.end(); ++j) {
                if (j.key() == BT::BLUEZ_DEVICE_INTERFACE) {
                    QString path = i.key().path();
                    QDBusInterface dev(BT::BLUEZ_DEST,
                            path,
                            BT::BLUEZ_DEVICE_INTERFACE,
                            m_SystemBus);

                    if (dev.property("Connected").toBool()
                            &&
                            dev.property("Address").toString() == deviceAddress) {

                        qCDebug(lcButeoCore) << "[BtHelper]Device connected("
                                << dev.property("Address").toString()
                                << ") at" << path;
                        m_devicePath = path;
                    }
                }
            }
        }
    }
#else
    Q_UNUSED(deviceAddress)
#endif
}

BtHelper::~BtHelper()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
}

QVariantMap BtHelper::getDeviceProperties()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

#ifdef HAVE_BLUEZ_5
    if (m_devicePath.isEmpty())
        return QVariantMap();

    QDBusInterface deviceInterface(BT::BLUEZ_DEST,
            m_devicePath,
            BT::BLUEZ_PROPERTIES_INTERFACE,
            m_SystemBus );
    if (!deviceInterface.isValid()) {
        qCDebug(lcButeoCore) << "Device interface is not valid";
        return QVariantMap();
    }

    QDBusReply<QVariantMap> reply =
            deviceInterface.call(BT::GETPROPERTIES, BT::BLUEZ_DEVICE_INTERFACE);
    if (!reply.isValid()) {
        qCWarning(lcButeoCore) << "Failed to get device properties: " << reply.error().message();
        return QVariantMap();
    }

    return reply.value();
#else
    qCDebug(lcButeoCore) << "Bluetooth is not supported";
    return QVariantMap();
#endif
}
