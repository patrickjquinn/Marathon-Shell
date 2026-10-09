// SPDX-FileCopyrightText: 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*!
 * Copyright (C) 2023 Jolla Ltd.
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
 *
 */

#ifndef MPRISINTROSPECTABLEADAPTOR_P_H
#define MPRISINTROSPECTABLEADAPTOR_P_H

#include <QtCore/QObject>
#include <QtDBus/QtDBus>

namespace Amber {

class MprisPlayerPrivate;
class MprisPlayerAdaptor;
class MprisPropertiesAdaptor;

/*
 * Adaptor class for interface org.freedesktop.DBus.Introspectable
 *
 * This is needed because the standard QDBusAbstractAdaptor
 * Introspectable implementation doesn't allow skipping properties
 * for the org.freedesktop.DBus.Introspectable.Introspect method,
 * but these are needed to fulfil the MPRIS spec.
 *
 */
class MprisIntrospectableAdaptor: public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.DBus.Introspectable")
    Q_CLASSINFO("D-Bus Introspection",
"  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
"    <method name=\"Introspect\">\n"
"      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
"    </method>\n"
"  </interface>\n")

public:
    MprisIntrospectableAdaptor(MprisPropertiesAdaptor *propertiesAdaptor, MprisPlayerPrivate *parent);
    virtual ~MprisIntrospectableAdaptor();

public Q_SLOTS: // METHODS
    QString Introspect();

private:
    MprisPropertiesAdaptor *m_propertiesAdaptor;
};

} // namespace Amber

#endif // MPRISINTROSPECTABLEADAPTOR_P_H
