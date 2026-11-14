// SPDX-FileCopyrightText: 2014 - 2020 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (c) 2014 - 2020 Jolla Ltd.
 * Copyright (c) 2020 Open Mobile Platform LLC.
**
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Pekka Vuorela <pekka.vuorela@jollamobile.com>
**
** All rights reserved.
**
** This file is part of nemo-keepalive package.
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

// Modified for Keel (Qt6), 2026 Shipwright: legacy org.nemomobile.keepalive
// registration. See keel/nemo-compat/PROVENANCE.md.

#include "declarativebackgroundactivity.h"
#include "displayblanking.h"

#include <QtGlobal>
#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <QDebug>

#define KEEPALIVE_URI "Nemo.KeepAlive"

QML_DECLARE_TYPE(DisplayBlanking)
QML_DECLARE_TYPE(BackgroundActivity)

static QObject *display_blanking_api_factory(QQmlEngine *, QJSEngine *)
{
    qWarning() << "Deprecated use of singleton DisplayBlanking type detected."
               << "This application will cease to work sometime in the near future."
               << "Upgrade code to utilize" << KEEPALIVE_URI << "1.2";

    return new DisplayBlanking;
}

static QObject *keel_legacy_keepalive_factory(QQmlEngine *, QJSEngine *)
{
    return new DeclarativeKeepAlive;
}

class KeepalivePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID KEEPALIVE_URI)

public:
    void registerTypes(const char *uri)
    {
        // Keel: the same plugin also serves the legacy org.nemomobile.keepalive
        // import (keel/nemo-compat/PROVENANCE.md). There 1.0 has KeepAlive
        // and DisplayBlanking as singletons and 1.1 matches Nemo.KeepAlive 1.1.
        if (QLatin1String(uri) == QLatin1String("org.nemomobile.keepalive")) {
            qWarning() << "org.nemomobile.keepalive import is deprecated. Suggest migrating to" << KEEPALIVE_URI;
            qmlRegisterSingletonType<DeclarativeKeepAlive>(uri, 1, 0, "KeepAlive", keel_legacy_keepalive_factory);
            qmlRegisterSingletonType<DisplayBlanking>(uri, 1, 0, "DisplayBlanking", display_blanking_api_factory);
            qmlRegisterType<DeclarativeBackgroundJob>(uri, 1, 0, "BackgroundJob");
            qmlRegisterSingletonType<DisplayBlanking>(uri, 1, 1, "DisplayBlanking", display_blanking_api_factory);
            qmlRegisterType<DeclarativeKeepAlive>(uri, 1, 1, "KeepAlive");
            qmlRegisterType<DeclarativeBackgroundJob>(uri, 1, 1, "BackgroundJob");
            return;
        }
        Q_ASSERT(QLatin1String(uri) == QLatin1String(KEEPALIVE_URI));

        // 1.1 KeepAlive is an instantiable class
        qmlRegisterSingletonType<DisplayBlanking>(uri, 1, 1, "DisplayBlanking", display_blanking_api_factory);
        qmlRegisterType<DeclarativeKeepAlive>(uri,     1, 1, "KeepAlive");
        qmlRegisterType<DeclarativeBackgroundJob>(uri, 1, 1, "BackgroundJob");

        // 1.2 DisplayBlanking is instantiable class
        qmlRegisterType<DisplayBlanking>(uri,          1, 2, "DisplayBlanking");
        qmlRegisterType<DeclarativeKeepAlive>(uri,     1, 2, "KeepAlive");
        qmlRegisterType<DeclarativeBackgroundJob>(uri, 1, 2, "BackgroundJob");
    }
};

#include "plugin.moc"
