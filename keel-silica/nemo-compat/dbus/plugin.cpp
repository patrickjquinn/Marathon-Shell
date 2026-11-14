// SPDX-FileCopyrightText: 2013-2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2013-2018 Jolla Ltd.
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

#include <QtGlobal>

#include <QtQml>
#include <QQmlExtensionPlugin>
#include <QDebug>

#include "declarativedbus.h"
#include "declarativedbusadaptor.h"
#include "declarativedbusinterface.h"

#include "dbus.h"

class Q_DECL_EXPORT NemoDBusPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "Nemo.DBus")
public:
    void registerTypes(const char *uri)
    {
        Q_ASSERT(uri == QLatin1String("Nemo.DBus") || uri == QLatin1String("org.nemomobile.dbus"));

        if (uri == QLatin1String("org.nemomobile.dbus")) {
            qWarning() << "org.nemomobile.dbus import is deprecated. Suggest migrating to Nemo.DBus";
        }

        NemoDBus::registerDBusTypes();

        qmlRegisterUncreatableType<DeclarativeDBus>(uri, 2, 0, "DBus", "Cannot create DBus objects");
        qmlRegisterType<DeclarativeDBusAdaptor>(uri, 2, 0, "DBusAdaptor");
        qmlRegisterType<DeclarativeDBusInterface>(uri, 2, 0, "DBusInterface");
    }
};

#include "plugin.moc"
