// SPDX-FileCopyrightText: 2015-2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
// -*- c++ -*-

/*
 *
 * Copyright (C) 2015-2021 Jolla Ltd.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */


#include "mprisplugin.h"

#include <Mpris>
#include <MprisPlayer>
#include <MprisController>
#include <MprisMetaData>
#include "declarativemprisplayer_p.h"

#include <qqml.h>

using namespace Amber;

template<class T> QObject *api_factory(QQmlEngine *, QJSEngine *)
{
    return new T;
}

MprisPlugin::MprisPlugin(QObject *parent) :
    QQmlExtensionPlugin(parent)
{
}

MprisPlugin::~MprisPlugin()
{
}

void MprisPlugin::registerTypes(const char *uri)
{
    qRegisterMetaType<QDBusObjectPath>();
    // Modified by Shipwright for Qt 6: Mpris is a Q_GADGET, which Qt 6 takes
    // for a value type (lower-case names only); registered as an enum holder
    // instead, so Mpris.Playing etc. resolve as on Qt 5.
    qmlRegisterUncreatableMetaObject(Mpris::staticMetaObject, uri, 1, 0, "Mpris", QStringLiteral("Mpris is a namespace object"));
    qmlRegisterType<DeclarativeMprisPlayer>(uri, 1, 0, "MprisPlayer");
    qmlRegisterType<MprisController>(uri, 1, 0, "MprisController");
    qmlRegisterUncreatableType<MprisMetaData>(uri, 1, 0, "MprisMetaData",
                                              QStringLiteral("MprisMetaData can't be instantiated, use MprisPlayer or MprisController"));
}
