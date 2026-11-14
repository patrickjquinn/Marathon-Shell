// SPDX-FileCopyrightText: 2015-2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
// -*- c++ -*-

/*!
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


#ifndef MPRIS_PLUGIN_H
#define MPRIS_PLUGIN_H

#include <QQmlExtensionPlugin>
#include <QtGlobal>

namespace Amber {
class MprisPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "Amber.Mpris")

public:
    MprisPlugin(QObject *parent = 0);
    ~MprisPlugin();

    virtual void registerTypes(const char *uri);
};
}


#endif /* MPRIS_PLUGIN_H */
