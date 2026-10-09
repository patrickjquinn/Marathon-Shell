// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* Copyright (C) 2021 Jolla Ltd.
 *
 * Contact: Juho Hämäläinen <juho.hamalainen@jolla.com>
 *
 * This work is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1 as published by the Free Software Foundation.
 *
 * This work is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this work; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 */

#include "declarativengfeventproperty.h"

/*!
   \qmlclass NgfProperty DeclarativeNgfEventProperty
   \brief Additional properties for non-graphical feedback events

   Event may have extra properties to control some behaviour explicitly.
   For example, to always disable vibra effect for an event, define
   property for the event:

   \qml
   NonGraphicalFeedback {
       id: ringtone
       event: "voip_ringtone"
       properties: [
           NgfProperty { name: "media.vibra"; value: false }
       ]
   }
   \endqml
 */

/*!
   \qmlproperty string name

   Name of the property. For example "media.audio", "audio", "media.vibra"
 */

/*!
   \qmlproperty variant value

   Value for the property. Type can be string, integer or boolean.
 */

DeclarativeNgfEventProperty::DeclarativeNgfEventProperty(QObject *parent)
    : QObject(parent)
{
}

QString DeclarativeNgfEventProperty::name() const
{
    return m_name;
}

void DeclarativeNgfEventProperty::setName(const QString &n)
{
    m_name = n;
    emit nameChanged();
}

QVariant DeclarativeNgfEventProperty::value() const
{
    return m_value;
}

void DeclarativeNgfEventProperty::setValue(const QVariant &v)
{
    // We accept everything here but filter non-applicable types
    // in DeclarativeNgfEvent.
    m_value = v;
    emit valueChanged();
}
