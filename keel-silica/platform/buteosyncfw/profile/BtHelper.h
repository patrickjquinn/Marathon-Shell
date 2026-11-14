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

#ifndef BTHELPER_H
#define BTHELPER_H

#include <QObject>
#include <QtDBus>
#include <QMap>

namespace Buteo {

/*! \brief Implementation for bluetooth helper utils.
  */
class BtHelper : public QObject
{
    Q_OBJECT

public:
    /*! \brief Constructor.
      * \param deviceAddress Bluetooth address of remote device
      * \param parent Parent object
      */
    BtHelper(const QString &deviceAddress, QObject *parent = 0);

    /*! \brief Destructor
      */
    ~BtHelper();

    /*! \brief To find remote device BT properties.
      */
    QVariantMap getDeviceProperties();

private:
    QDBusConnection m_SystemBus;
    QString m_devicePath;
};

#endif // BTHELPER_H

}
