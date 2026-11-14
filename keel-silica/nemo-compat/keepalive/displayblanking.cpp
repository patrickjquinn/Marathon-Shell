// SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2023 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
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

#include "displayblanking_p.h"
#include "common.h"

/* ========================================================================= *
 * class DisplayBlanking
 * ========================================================================= */

/*!
    \qmltype DisplayBlanking
    \inqmlmodule Nemo.KeepAlive
    \brief Provides means for preventing display blanking

    Tracks MCE state over D-Bus and exposes the current display state
    as a QML property.

    Provides simple abstraction for D-Bus mechanisms that are required
    for preventing display blanking (when allowed by lower level policies).
*/

/*!
    \qmlproperty enumeration DisplayBlanking::status
    \brief Returns the current display state

    The status can be one of:
    \list
    \li DisplayBlanking.Unknown - initial placeholder value
    \li DisplayBlanking.Off
    \li DisplayBlanking.Dimmed
    \li DisplayBlanking.On
    \endlist
*/

/*!
    \qmlproperty bool DisplayBlanking::preventBlanking
    \brief Sets the desired blank prevention mode

    When set to true, prevents display from blanking - provided
    that the system is in a state that allows it.

    preventBlanking defaults to false.

*/

DisplayBlanking::DisplayBlanking(QObject *parent)
    : QObject(parent)
    , priv(nullptr)
{
    priv = new DisplayBlankingPrivate(this);
}

DisplayBlanking::~DisplayBlanking()
{
    delete priv; priv = nullptr;
}

DisplayBlanking::Status DisplayBlanking::status() const
{
    return priv->displayStatus();
}

bool DisplayBlanking::preventBlanking() const
{
    return priv->preventBlanking();
}

void DisplayBlanking::setPreventBlanking(bool prevent)
{
    TRACE
    priv->setPreventBlanking(prevent);
}
