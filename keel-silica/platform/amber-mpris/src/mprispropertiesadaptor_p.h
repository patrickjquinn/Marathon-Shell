// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*!
 * Copyright (C) 2015-2023 Jolla Ltd.
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

#ifndef MPRISPROPERTIESADAPTOR_P_H
#define MPRISPROPERTIESADAPTOR_P_H

#include <QtCore/QObject>
#include <QtDBus/QtDBus>

namespace Amber {

class MprisPlayerPrivate;

/*
 * Adaptor class for interface org.freedesktop.DBus.Properties
 *
 * This is needed because the standard QDBusAbstractAdaptor
 * Properties implementation doesn't allow errors to be
 * returned for the org.freedesktop.DBus.Properties.Set method,
 * but these are needed to fulfil the MPRIS spec.
 *
 */
class MprisPropertiesAdaptor: public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.DBus.Properties")
    Q_CLASSINFO("D-Bus Introspection",
"  <interface name=\"org.freedesktop.DBus.Properties\">\n"
"    <method name=\"Get\">\n"
"      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>\n"
"      <arg name=\"property_name\" type=\"s\" direction=\"in\"/>\n"
"      <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
"    </method>\n"
"    <method name=\"Set\">\n"
"      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>\n"
"      <arg name=\"property_name\" type=\"s\" direction=\"in\"/>\n"
"      <arg name=\"value\" type=\"v\" direction=\"in\"/>\n"
"    </method>\n"
"    <method name=\"GetAll\">\n"
"      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>\n"
"      <arg name=\"values\" type=\"a{sv}\" direction=\"out\"/>\n"
"      <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"QVariantMap\"/>\n"
"    </method>\n"
"    <signal name=\"PropertiesChanged\">\n"
"      <arg name=\"interface_name\" type=\"s\" direction=\"out\"/>\n"
"      <arg name=\"changed_properties\" type=\"a{sv}\" direction=\"out\"/>\n"
"      <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out1\" value=\"QVariantMap\"/>\n"
"      <arg name=\"invalidated_properties\" type=\"as\" direction=\"out\"/>\n"
"    </signal>\n"
"  </interface>\n")

public:
    MprisPropertiesAdaptor(MprisPlayerPrivate *parent);
    virtual ~MprisPropertiesAdaptor();

    bool propertiesLocked() const;
    void lockProperties();
    void hideProperty(const QString &property, bool hidden);
    void reset();
    bool hasMaskedProperties() const;
    bool propertyMasked(const QString &property) const;

public Q_SLOTS: // METHODS
    QDBusVariant Get(const QString &interface_name, const QString &property_name);
    void Set(const QString &interface_name, const QString &property_name, const QDBusVariant &value);
    QVariantMap GetAll(const QString &interface_name);

private:
    void replyPropertyNotFoundError(const QString &interface_name, const QString &property_name);
    void replyPropertyReadOnlyError(const QString &interface_name, const QString &property_name);
    void replyInternalError();

    QVariant get(const QString &getter);
    void set(const QString &setter, const QDBusVariant &value);

    MprisPlayerPrivate *m_playerPrivate;
    bool m_propertiesLocked;
    QSet<QString> m_maskedProperties;
};
}

#endif
