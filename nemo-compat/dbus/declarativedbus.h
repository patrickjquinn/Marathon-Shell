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

#ifndef DECLARATIVEDBUS_H
#define DECLARATIVEDBUS_H

#include <QObject>
#include <QDBusConnection>

class DeclarativeDBus : public QObject
{
    Q_OBJECT
    Q_ENUMS(BusType)

public:
    DeclarativeDBus(QObject *parent = 0);
    ~DeclarativeDBus();

    enum BusType {
        SystemBus,
        SessionBus
    };

    static QDBusConnection connection(BusType bus);
};

#endif
