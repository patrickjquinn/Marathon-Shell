// SPDX-FileCopyrightText: 2013 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
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

// Modified for Keel (Qt6), 2026 Shipwright: Properties.Get reply type.
// See keel/nemo-compat/PROVENANCE.md.

#include "declarativedbusadaptor.h"
#include "declarativedbusinterface.h"
#include "dbus.h"

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusConnection>
#include <QMetaMethod>

#include <qqmlinfo.h>
#include <QtDebug>


/*!
    \qmltype DBusAdaptor
    \inqmlmodule Nemo.DBus
    \brief Provides a service on D-Bus

    The DBusAdaptor object can be used to provide a D-Bus service on the system or session bus. A
    service can be called from other applications on the system as long as the service is active.

    DBusAdaptor is intended to provide a means of exposing simple objects over D-Bus. Property
    values and method arguments are automatically converted between QML/JS and D-Bus. There is
    limited control over this process. For more complex use cases it is recommended to use C++ and
    the Qt DBus module.

    \section2 Exposing an object on D-Bus

    The following code demonstrates how to expose an object on the session bus. The
    \c {com.example.service} service name will be registered and an object at
    \c {/com/example/service} will be registered supporting the \c {com.example.service} interface
    in addition to the common interfaces \c {org.freedesktop.DBus.Properties},
    \c {org.freedesktop.DBus.Introspectable} and \c {org.freedesktop.DBus.Peer}.

    All properties and methods of the DBusAdaptor will be accessible via D-Bus. Only those
    properties and methods declared in the \l xml will be discoverable via D-Bus introspection.

    \code
    import QtQuick 2.0
    import Nemo.DBus 2.0

    Item {
        DBusAdaptor {
            id: dbus

            property bool needUpdate: true

            service: 'com.example.service'
            iface: 'com.example.service'
            path: '/com/example/service'

            xml: '  <interface name="com.example.service">\n' +
                 '    <method name="update" />\n' +
                 '    <property name="needUpdate" type="b" access="readwrite" />\n' +
                 '  </interface>\n'

            function update() {
                console.log("Update called")
            }
        }
    }
    \endcode
*/

DeclarativeDBusAdaptor::DeclarativeDBusAdaptor(QObject *parent)
    : QDBusVirtualObject(parent), m_bus(DeclarativeDBus::SessionBus)
{
}

DeclarativeDBusAdaptor::~DeclarativeDBusAdaptor()
{
    QDBusConnection conn = DeclarativeDBus::connection(m_bus);
    conn.unregisterObject(m_path);

    // In theory an application could have multiple adaptor items for different paths or
    // interfaces and destroying one would unregister the whole service.
    // If problems arise we could introduce refcounting for services so that
    // the last service would be responsible for unregisting the service upon
    // destruction. Unregisration should also take into account unregistration happening
    // from C++ side.
    if (!m_service.isEmpty()) {
        if (!conn.unregisterService(m_service)) {
            qmlInfo(this) << "Failed to unregister service " << m_service;
            qmlInfo(this) << conn.lastError().message();
        }
    }
}

/*!
    \qmlproperty string DBusAdaptor::service

    This property holds the registered service name. Typically this is in reversed domain-name.
*/
QString DeclarativeDBusAdaptor::service() const
{
    return m_service;
}

void DeclarativeDBusAdaptor::setService(const QString &service)
{
    if (m_service != service) {
        m_service = service;
        emit serviceChanged();
    }
}

/*!
    \qmlproperty string DBusAdaptor::path

    This property holds the object path that this object will be published at.
*/
QString DeclarativeDBusAdaptor::path() const
{
    return m_path;
}

void DeclarativeDBusAdaptor::setPath(const QString &path)
{
    if (m_path != path) {
        m_path = path;
        emit pathChanged();
    }
}

/*!
    \qmlproperty string DBusAdaptor::iface

    This property holds the interface that this object supports.
*/
QString DeclarativeDBusAdaptor::interface() const
{
    return m_interface;
}

void DeclarativeDBusAdaptor::setInterface(const QString &interface)
{
    if (m_interface != interface) {
        m_interface = interface;
        emit interfaceChanged();
    }
}

/*
    The XML service description. This could be derived from the meta-object but since it's unlikely
    to be needed most of the time this and type conversion is non-trivial it's not, and there is
    this property instead if it is needed.
*/

/*!
    \qmlproperty string DBusAdaptor::xml

    This property holds the D-Bus introspection metadata snippet for this object/interface.
*/
QString DeclarativeDBusAdaptor::xml() const
{
    return m_xml;
}

void DeclarativeDBusAdaptor::setXml(const QString &xml)
{
    if (m_xml != xml) {
        m_xml = xml;
        emit xmlChanged();
    }
}

/*!
    \qmlproperty enum DBusAdaptor::bus

    This property holds whether to use the session or system D-Bus.

    \list
        \li DBus.SessionBus - The D-Bus session bus
        \li DBus.SystemBus - The D-Bus system bus
    \endlist
*/
DeclarativeDBus::BusType DeclarativeDBusAdaptor::bus() const
{
    return m_bus;
}

void DeclarativeDBusAdaptor::setBus(DeclarativeDBus::BusType bus)
{
    if (m_bus != bus) {
        m_bus = bus;
        emit busChanged();
    }
}

void DeclarativeDBusAdaptor::classBegin()
{
}

void DeclarativeDBusAdaptor::componentComplete()
{
    QDBusConnection conn = DeclarativeDBus::connection(m_bus);

    // It is still valid to publish an object on the bus without first registering a service name,
    // a remote process would have to connect directly to the DBus address.
    if (!conn.registerVirtualObject(m_path, this)) {
        qmlInfo(this) << "Failed to register object " << m_path;
        qmlInfo(this) << conn.lastError().message();
    }

    // Register service name only if it has been set.
    if (!m_service.isEmpty()) {
        if (!conn.registerService(m_service)) {
            qmlInfo(this) << "Failed to register service " << m_service;
            qmlInfo(this) << conn.lastError().message();
        }
    }
}

QString DeclarativeDBusAdaptor::introspect(const QString &) const
{
    return m_xml;
}

QDBusArgument &operator << (QDBusArgument &argument, const QVariant &value)
{
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    switch (value.typeId()) {
#else
    switch (value.type()) {
#endif
    case QVariant::String:
        return argument << value.toString();
    case QVariant::StringList:
        return argument << value.toStringList();
    case QVariant::Int:
        return argument << value.toInt();
    case QVariant::Bool:
        return argument << value.toBool();
    case QVariant::Double:
        return argument << value.toDouble();
    default:
        if (value.userType() == qMetaTypeId<float>()) {
            return argument << value.value<float>();
        }
        return argument;
    }
}

bool DeclarativeDBusAdaptor::handleMessage(const QDBusMessage &message,
                                           const QDBusConnection &connection)
{
    QVariant variants[10];
    QGenericArgument arguments[10];

    const QMetaObject *const meta = metaObject();
    const QVariantList dbusArguments = message.arguments();

    QString member = message.member();
    QString interface = message.interface();

    // Don't try to handle introspect call. It will be handled
    // internally for QDBusVirtualObject derived classes.
    if (interface == QLatin1String("org.freedesktop.DBus.Introspectable")) {
        return false;
    } else if (interface == QLatin1String("org.freedesktop.DBus.Properties")) {
        if (member == QLatin1String("Get")) {
            interface = dbusArguments.value(0).toString();
            member = dbusArguments.value(1).toString();

            const QMetaObject *const meta = metaObject();
            if (!member.isEmpty() && member.at(0).isUpper())
                member = "rc" + member;

            for (int propertyIndex = meta->propertyOffset();
                 propertyIndex < meta->propertyCount();
                 ++propertyIndex) {
                QMetaProperty property = meta->property(propertyIndex);

                if (QLatin1String(property.name()) != member)
                    continue;

                QVariant value = property.read(this);
                if (value.userType() == qMetaTypeId<QJSValue>())
                    value = value.value<QJSValue>().toVariant();

                if (value.userType() == QVariant::List) {
                    QVariantList variantList = value.toList();
                    if (variantList.count() > 0) {

                        QDBusArgument list;
                        list.beginArray(variantList.first().userType());
                        foreach (const QVariant &listValue, variantList) {
                            list << listValue;
                        }
                        list.endArray();
                        value = QVariant::fromValue(list);
                    }
                }

                // Keel: Properties.Get returns a variant ("v"); upstream sent the
                // bare value, which QtDBus and GDBus clients reject.
                QDBusMessage reply = message.createReply(QVariantList() << QVariant::fromValue(QDBusVariant(value)));
                connection.call(reply, QDBus::NoBlock);

                return true;
            }
        } else if (member == QLatin1String("GetAll")) {
            interface = dbusArguments.value(0).toString();

            QDBusArgument map;
            map.beginMap(qMetaTypeId<QString>(), qMetaTypeId<QDBusVariant>());

            for (int propertyIndex = meta->propertyOffset();
                 propertyIndex < meta->propertyCount();
                 ++propertyIndex) {
                QMetaProperty property = meta->property(propertyIndex);

                QString propertyName = QLatin1String(property.name());
                if (propertyName.startsWith(QLatin1String("rc")))
                    propertyName = propertyName.mid(2);

                QVariant value = property.read(this);
                if (value.userType() == qMetaTypeId<QJSValue>())
                    value = value.value<QJSValue>().toVariant();

                if (value.userType() == QVariant::List) {
                    QVariantList variantList = value.toList();
                    if (variantList.count() > 0) {

                        QDBusArgument list;
                        list.beginArray(variantList.first().userType());
                        foreach (const QVariant &listValue, variantList) {
                            list << listValue;
                        }
                        list.endArray();
                        value = QVariant::fromValue(list);
                    }
                }

                if (value.isValid()) {
                    map.beginMapEntry();
                    map << propertyName;
                    map << QDBusVariant(value);
                    map.endMapEntry();
                }
            }
            map.endMap();

            QDBusMessage reply = message.createReply(QVariantList() << QVariant::fromValue(map));
            connection.call(reply, QDBus::NoBlock);

            return true;
        } else if (member == QLatin1String("Set")) {
            interface = dbusArguments.value(0).toString();
            member = dbusArguments.value(1).toString();

            const QMetaObject *const meta = metaObject();
            if (!member.isEmpty() && member.at(0).isUpper())
                member = "rc" + member;

            for (int propertyIndex = meta->propertyOffset();
                 propertyIndex < meta->propertyCount();
                 ++propertyIndex) {
                QMetaProperty property = meta->property(propertyIndex);

                if (QLatin1String(property.name()) != member)
                    continue;

                QVariant value = NemoDBus::demarshallDBusArgument(dbusArguments.value(2));

                return property.write(this, value);
            }
        }
        return false;
    }

    // Support interfaces with method names starting with an uppercase letter.
    // com.example.interface.Foo -> com.example.interface.rcFoo (remote-call Foo).
    if (!member.isEmpty() && member.at(0).isUpper())
        member = "rc" + member;

    for (int methodIndex = meta->methodOffset(); methodIndex < meta->methodCount(); ++methodIndex) {
        const QMetaMethod method = meta->method(methodIndex);
        const QList<QByteArray> parameterTypes = method.parameterTypes();

        if (parameterTypes.count() != dbusArguments.count())
            continue;

        QByteArray sig(method.methodSignature());

        if (!sig.startsWith(member.toLatin1() + "("))
            continue;

        int argumentCount = 0;
        for (; argumentCount < 10 && argumentCount < dbusArguments.count(); ++argumentCount) {
            variants[argumentCount] = NemoDBus::demarshallDBusArgument(dbusArguments.at(argumentCount));
            QVariant &argument = variants[argumentCount];

            const QByteArray parameterType = parameterTypes.at(argumentCount);
            if (parameterType == "QVariant") {
                arguments[argumentCount] = QGenericArgument("QVariant", &argument);
            } else if (parameterType == argument.typeName()) {
                arguments[argumentCount] = QGenericArgument(argument.typeName(), argument.data());
            } else {
                // Type mismatch, there may be another overload.
                break;
            }
        }

        if (argumentCount == dbusArguments.length()) {
            if (method.methodType() == QMetaMethod::Signal) {
                return method.invoke(
                            this,
                            arguments[0],
                            arguments[1],
                            arguments[2],
                            arguments[3],
                            arguments[4],
                            arguments[5],
                            arguments[6],
                            arguments[7],
                            arguments[8],
                            arguments[9]);
            } else {
                QVariant retVal;
                // Modified by Shipwright: since Qt 6.5 Q_RETURN_ARG selects the
                // variadic invoke() overload, which would pass the
                // QGenericArguments below as values; name the legacy type.
                bool success = method.invoke(
                            this,
                            QGenericReturnArgument("QVariant", &retVal),
                            arguments[0],
                            arguments[1],
                            arguments[2],
                            arguments[3],
                            arguments[4],
                            arguments[5],
                            arguments[6],
                            arguments[7],
                            arguments[8],
                            arguments[9]);
                if (success) {
                    QDBusMessage reply = retVal.isValid() ? message.createReply(retVal) : message.createReply();
                    QDBusConnection conn = DeclarativeDBus::connection(m_bus);
                    conn.send(reply);
                }
                return success;
            }
        }
    }
    QByteArray signature = message.member().toLatin1() + "(";
    for (int i = 0; i < dbusArguments.count(); ++i) {
        if (i > 0)
            signature += ",";
        signature += dbusArguments.at(i).typeName();
    }
    signature += ")";

    qmlInfo(this) << "No method with the signature " << signature;
    return false;
}

/*!
    \qmlmethod void DBusAdaptor::emitSignal(string name, var arguments)

    Emit a signal with the given \a name and \a arguments. If \a arguments is undefined (the
    default if not specified), then the signal will be emitted without arguments.
*/
void DeclarativeDBusAdaptor::emitSignal(const QString &name, const QJSValue &arguments)
{
    QDBusMessage signal = QDBusMessage::createSignal(m_path, m_interface, name);
    QDBusConnection conn = DeclarativeDBus::connection(m_bus);

    if (!arguments.isUndefined()) {
        signal.setArguments(DeclarativeDBusInterface::argumentsFromScriptValue(arguments));
    }

    if (!conn.send(signal))
        qmlInfo(this) << conn.lastError();
}
