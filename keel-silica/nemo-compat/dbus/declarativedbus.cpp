// SPDX-FileCopyrightText: 2013 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Andrew den Exter <andrew.den.exter@jollamobile.com>
** All rights reserved.
**
** You may use this file under the terms of the GNU Lesser General
** Public License version 2.1 as published by the Free Software Foundation
** and appearing in the file license.lgpl included in the packaging
** of this file.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file license.lgpl included in the packaging
** of this file.
**
** This library is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
** Lesser General Public License for more details.
**
****************************************************************************************/

#include "declarativedbus.h"

DeclarativeDBus::DeclarativeDBus(QObject *parent)
    : QObject(parent)
{
}

DeclarativeDBus::~DeclarativeDBus()
{
}

QDBusConnection DeclarativeDBus::connection(DeclarativeDBus::BusType bus)
{
    if (bus == SessionBus) {
        return QDBusConnection::sessionBus();
    } else {
        return QDBusConnection::systemBus();
    }
}
