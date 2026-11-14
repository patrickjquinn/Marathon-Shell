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

#include "declarativedbusinterface.h"
#include "dbus.h"

#include <QMetaMethod>
#include <QDBusMessage>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusObjectPath>
#include <QDBusSignature>
#include <QDBusUnixFileDescriptor>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <qqmlinfo.h>
#include <QJSEngine>
#include <QJSValue>
#include <QJSValueIterator>
#include <QFile>
#include <QUrl>
#include <QXmlStreamReader>

/*!
    \qmltype DBusInterface
    \inqmlmodule Nemo.DBus
    \brief Provides access to a service on D-Bus

    The DBusInterface object can be used to call methods of objects on the system and session bus,
    as well as receive signals (see \l signalsEnabled) and read properties of those objects.

    DBusInterface is intended to provide access to simple objects exposed over D-Bus. Property
    values and method arguments are automatically converted between QML/JS and D-Bus. There is
    limited control over this process. For more complex use cases it is recommended to use C++ and
    the Qt DBus module.

    \section2 Handling D-Bus Signals

    If \l signalsEnabled is set to \c true, signals of the destination object will be connected to
    functions on the object that have the same name.

    Imagine a D-Bus object in service \c {org.example.service} at path \c {/org/example/service} and
    interface \c {org.example.intf} with two signals, \c {UpdateAll} and \c {UpdateOne}. You can
    handle these signals this way:

    \code
    DBusInterface {
        service: 'org.example.service'
        path: '/org/example/service'
        iface: 'org.example.intf'

        signalsEnabled: true

        function updateAll() {
            // Will be called when the "UpdateAll" signal is received
        }

        function updateOne(a, b) {
            // Will be called when the "UpdateOne" signal is received
        }
    }
    \endcode

    \note In D-Bus, signal names usually start with an uppercase letter, but in QML, function names
          on objects must start with lowercase letters. The plugin connects uppercase signal names
          to functions where the first letter is lowercase (the D-Bus signal \c {UpdateOne} is
          handled by the QML/JavaScript function \c {updateOne}).

    \section2 Handling D-Bus Properties

    If \l propertiesEnabled is set to \c true, properties of the destination object will
    be available on the local object with matching names.

    \code
    DBusInterface {
        service: 'org.example.service'
        path: '/org/example/service'
        iface: 'org.example.intf'

        propertiesEnabled: true

        property string activeState
        onActiveStateChanged: {
            // handle state change
        }
    }
    \endcode

    \section2 Calling D-Bus Methods

    Remote D-Bus methods can be called using either \l call() or \l typedCall(). \l call() provides
    a simpler calling API, only supporting basic data types, \l typedCall()
    supports more data types. Both methods provide callbacks for response and error handling.

    Imagine a D-Bus object in service \c {org.example.service} at path \c {/org/example/service} and
    interface \c {org.example.intf} with two methods:

    \list
        \li \c RegisterObject with a single \e {object path} parameter and returning a \c bool
        \li \c Update with no parameters
    \endlist

    You can call these two methods this way:

    \code
    DBusInterface {
        service: 'org.example.service'
        path: '/org/example/service'
        iface: 'org.example.intf'

        // Local function to call remote method RegisterObject
        function registerObject(object) {
            typedCall('RegisterObject',
                      { 'type': 'o', 'value': '/example/object/path' },
                      function(result) { console.log('call completed with:', result) },
                      function(error, message) { console.log('call failed', error, 'message:', message) })
        }

        // Location function to call remote method Update
        function update() {
            call('Update', undefined)
        }
    }
    \endcode
*/

/*!
    \qmlsignal DBusInterface::propertiesChanged()

    This signal is emitted when properties of the D-Bus object have changed (only if the D-Bus
    object does emit signals when properties change). Right now, this does not tell which properties
    have changed and to which values.

    \since version 2.0.8
*/

namespace {
const QLatin1String PropertyInterface("org.freedesktop.DBus.Properties");
}

DeclarativeDBusInterface::DeclarativeDBusInterface(QObject *parent)
    : QObject(parent)
    , m_watchServiceStatus(false)
    , m_status(Unknown)
    , m_bus(DeclarativeDBus::SessionBus)
    , m_componentCompleted(false)
    , m_signalsEnabled(false)
    , m_signalsConnected(false)
    , m_propertiesEnabled(false)
    , m_propertiesConnected(false)
    , m_introspected(false)
    , m_providesPropertyInterface(false)
    , m_serviceWatcher(nullptr)
{
}

DeclarativeDBusInterface::~DeclarativeDBusInterface()
{
    qDeleteAll(m_pendingCalls.keys());
}

/*!
    \qmlproperty bool DBusInterface::watchServiceStatus

    When enabled, the \l status property will match the current availability of the
    D-Bus service.
*/
bool DeclarativeDBusInterface::watchServiceStatus() const
{
    return m_watchServiceStatus;
}

void DeclarativeDBusInterface::setWatchServiceStatus(bool watchServiceStatus)
{
    if (m_watchServiceStatus != watchServiceStatus) {
        m_watchServiceStatus = watchServiceStatus;
        updateServiceWatcher();

        emit watchServiceStatusChanged();

        connectSignalHandler();
        connectPropertyHandler();
    }
}

/*!
    \qmlproperty enumeration DBusInterface::status

    Returns the availability of the service if tracking is enabled via \l watchServiceStatus.
    Value can be:
    \list
    \li DeclarativeDBusInterface.Unknown
    \li DeclarativeDBusInterface.Unavailable
    \li DeclarativeDBusInterface.Available
    \endlist
*/

DeclarativeDBusInterface::Status DeclarativeDBusInterface::status() const
{
    return m_status;
}

/*!
    \qmlproperty string DBusInterface::service

    This property holds the service name of the service to connect to.
*/
QString DeclarativeDBusInterface::service() const
{
    return m_service;
}

void DeclarativeDBusInterface::setService(const QString &service)
{
    if (m_service != service) {
        invalidateIntrospection();

        m_service = service;
        updateServiceWatcher();

        emit serviceChanged();

        connectSignalHandler();
        connectPropertyHandler();
    }
}

/*!
    \qmlproperty string DBusInterface::path

    This property holds the object path of the object to access.
*/
QString DeclarativeDBusInterface::path() const
{
    return m_path;
}

void DeclarativeDBusInterface::setPath(const QString &path)
{
    if (m_path != path) {
        invalidateIntrospection();

        m_path = path;
        emit pathChanged();

        connectSignalHandler();
        connectPropertyHandler();
    }
}

/*!
    \qmlproperty string DBusInterface::iface

    This property holds the interface.
*/
QString DeclarativeDBusInterface::interface() const
{
    return m_interface;
}

void DeclarativeDBusInterface::setInterface(const QString &interface)
{
    if (m_interface != interface) {
        invalidateIntrospection();

        m_interface = interface;
        emit interfaceChanged();

        connectSignalHandler();
        connectPropertyHandler();
    }
}

/*!
    \qmlproperty enum DBusInterface::bus

    This property holds whether to use the session or system D-Bus.

    \list
        \li DBus.SessionBus - The D-Bus session bus
        \li DBus.SystemBus - The D-Bus system bus
    \endlist
*/
DeclarativeDBus::BusType DeclarativeDBusInterface::bus() const
{
    return m_bus;
}

void DeclarativeDBusInterface::setBus(DeclarativeDBus::BusType bus)
{
    if (m_bus != bus) {
        invalidateIntrospection();

        m_bus = bus;
        updateServiceWatcher();
        emit busChanged();

        connectSignalHandler();
        connectPropertyHandler();
    }
}

/*!
    \qmlproperty bool DBusInterface::signalsEnabled

    This property holds whether this object listens signal emissions on the remote D-Bus object. See
    \l {Handling D-Bus Signals}.
*/
bool DeclarativeDBusInterface::signalsEnabled() const
{
    return m_signalsEnabled;
}

void DeclarativeDBusInterface::setSignalsEnabled(bool enabled)
{
    if (m_signalsEnabled != enabled) {
        if (!enabled)
            disconnectSignalHandler();

        m_signalsEnabled = enabled;
        emit signalsEnabledChanged();

        connectSignalHandler();
    }
}

/*!
    \qmlproperty bool DBusInterface::propertiesEnabled

    This property holds whether this object tracks properties on the remote D-Bus object.
    See \l {Handling D-Bus Properties}.
*/

bool DeclarativeDBusInterface::propertiesEnabled() const
{
    return m_propertiesEnabled;
}

void DeclarativeDBusInterface::setPropertiesEnabled(bool enabled)
{
    if (m_propertiesEnabled != enabled) {
        if (!m_signalsEnabled)
            disconnectPropertyHandler();

        m_propertiesEnabled = enabled;
        emit propertiesEnabledChanged();

        // connectPropertyHandler will call this as well.  This just cover the case where
        // connectPropertyHandler was previously called and m_propertiesEnabled was false.
        queryPropertyValues();
        connectPropertyHandler();
    }
}

QVariantList DeclarativeDBusInterface::argumentsFromScriptValue(const QJSValue &arguments)
{
    QVariantList dbusArguments;

    if (arguments.isArray()) {
        QJSValueIterator it(arguments);
        while (it.hasNext()) {
            it.next();
            // Arrays carry the size as last value
            if (!it.hasNext())
                continue;
            dbusArguments.append(it.value().toVariant());
        }
    } else if (!arguments.isUndefined()) {
        dbusArguments.append(arguments.toVariant());
    }

    return dbusArguments;
}

/*!
    \qmlmethod void DBusInterface::call(string method, var arguments, var callback, var errorCallback)

    Call a D-Bus method with the name \a method on the object with \a arguments as either a single
    value or an array. For a function with no arguments, pass in \c undefined.

    The callback arguments are handled as described under \l typedCall().

    \note This function supports passing basic data types and will fail if the signature of the
          remote method does not match the signature determined from the type of \a arguments. The
          \l typedCall() function can be used to explicity specify the type of each element of
          \a arguments.
*/
void DeclarativeDBusInterface::call(
        const QString &method,
        const QJSValue &arguments,
        const QJSValue &callback,
        const QJSValue &errorCallback)
{
    QVariantList dbusArguments = argumentsFromScriptValue(arguments);

    QDBusMessage message = QDBusMessage::createMethodCall(
                m_service,
                m_path,
                m_interface,
                method);
    message.setArguments(dbusArguments);

    dispatch(message, callback, errorCallback);
}

template<typename T> static QList<T> toQList(const QVariantList &lst)
{
    QList<T> arr;
    foreach (const QVariant &var, lst) {
        arr << qvariant_cast<T>(var);
    }
    return arr;
}

static QStringList toQStringList(const QVariantList &lst)
{
    QStringList arr;
    foreach (const QVariant &var, lst) {
        arr << qvariant_cast<QString>(var);
    }
    return arr;
}

static QByteArray toQByteArray(const QVariantList &lst)
{
    QByteArray arr;
    foreach (const QVariant &var, lst) {
        uchar tmp = static_cast<uchar>(var.toUInt());
        arr.append(static_cast<char>(tmp));
    }
    return arr;
}

static bool flattenVariantList(QVariant &var, const QVariantList &lst,
                               int typeChar)
{
    bool res = true;

    switch (typeChar) {
    case 'b': // BOOLEAN
        var = QVariant::fromValue(toQList<bool>(lst));
        break;
    case 'y': // BYTE
        var = QVariant::fromValue(toQByteArray(lst));
        break;
    case 'q': // UINT16
        var = QVariant::fromValue(toQList<quint16>(lst));
        break;
    case 'u': // UINT32
        var = QVariant::fromValue(toQList<quint32>(lst));
        break;
    case 't': // UINT64
        var = QVariant::fromValue(toQList<quint64>(lst));
        break;
    case 'n': // INT16
        var = QVariant::fromValue(toQList<qint16>(lst));
        break;
    case 'i': // INT32
        var = QVariant::fromValue(toQList<qint32>(lst));
        break;
    case 'x': // INT64
        var = QVariant::fromValue(toQList<qint64>(lst));
        break;
    case 'd': // DOUBLE
        var = QVariant::fromValue(toQList<double>(lst));
        break;
    case 's': // STRING
        var = QVariant::fromValue(toQStringList(lst));
        break;
    default:
        res = false;
        break;
    }

    return res;
}

static bool flattenVariantArrayForceType(QVariant &var, int typeChar)
{
    return flattenVariantList(var, var.toList(), typeChar);
}

static void flattenVariantArrayGuessType(QVariant &var)
{
    /* If the value can't be converted to a variant list
     * or if the resulting list would be empty: use the
     * value without modification */
    QVariantList arr = var.toList();
    if (arr.empty())
        return;

    /* If all items in the list do not share the same type:
     * use as is -> each value will be wrapped in variant
     * container */
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    int t = arr[0].typeId();
#else
    int t = arr[0].type();
#endif
    int n = arr.size();
    for (int i = 1; i < n; ++i) {
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
        if (arr[i].typeId() != t)
#else
        if (arr[i].type() != t)
#endif
            return;
    }

    switch (t) {
    case QVariant::String:
        flattenVariantList(var, arr, 's');
        break;
    case QVariant::Bool:
        flattenVariantList(var, arr, 'b');
        break;
    case QVariant::Int:
        flattenVariantList(var, arr, 'i');
        break;
    case QVariant::Double:
        flattenVariantList(var, arr, 'd');
        break;
    default:
        /* Unhandled types are encoded as variant:array:variant:val
         * instead of variant:array:val what we actually want.
         */
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
        qWarning("unhandled array type: %d (%s)", t, QMetaType(t).name());
#else
        qWarning("unhandled array type: %d (%s)", t, QVariant::typeToName(t));
#endif
        break;
    }
}

bool
DeclarativeDBusInterface::marshallDBusArgument(QDBusMessage &msg, const QJSValue &arg)
{
    QJSValue type = arg.property(QLatin1String("type"));

    if (!type.isString()) {
        qWarning() << "DeclarativeDBusInterface::typedCall - Invalid type";
        qmlInfo(this) << "DeclarativeDBusInterface::typedCall - Invalid type";
        return false;
    }

    QJSValue value = arg.property(QLatin1String("value"));

    if (value.isNull() || value.isUndefined()) {
        qWarning() << "DeclarativeDBusInterface::typedCall - Invalid argument";
        qmlInfo(this) << "DeclarativeDBusInterface::typedCall - Invalid argument";
        return false;
    }

    QString t = type.toString();
    if (t.length() == 1) {
        switch (t.at(0).toLatin1()) {
        case 'y': // BYTE
            msg << QVariant::fromValue(static_cast<quint8>(value.toUInt()));
            return true;

        case 'q': // UINT16
            msg << QVariant::fromValue(static_cast<quint16>(value.toUInt()));
            return true;

        case 'u': // UINT32
            msg << QVariant::fromValue(static_cast<quint32>(value.toUInt()));
            return true;

        case 't': // UINT64
            msg << QVariant::fromValue(static_cast<quint64>(value.toVariant().toULongLong()));
            return true;

        case 'n': // INT16
            msg << QVariant::fromValue(static_cast<qint16>(value.toInt()));
            return true;

        case 'i': // INT32
            msg << QVariant::fromValue(static_cast<qint32>(value.toInt()));
            return true;

        case 'x': // INT64
            msg << QVariant::fromValue(static_cast<qint64>(value.toVariant().toLongLong()));
            return true;

        case 'b': // BOOLEAN
            msg << value.toBool();
            return true;

        case 'd': // DOUBLE
            msg << value.toNumber();
            return true;

        case 's': // STRING
            msg << value.toString();
            return true;

        case 'o': // OBJECT_PATH
            msg << QVariant::fromValue(QDBusObjectPath(value.toString()));
            return true;

        case 'g': // SIGNATURE
            msg << QVariant::fromValue(QDBusSignature(value.toString()));
            return true;

        case 'h': // UNIX_FD
            msg << QVariant::fromValue(QDBusUnixFileDescriptor(value.toInt()));
            return true;

        case 'v': { // VARIANT
            QVariant var = value.toVariant();
            flattenVariantArrayGuessType(var);
            msg << QVariant::fromValue(QDBusVariant(var));
        }
            return true;

        default:
            break;
        }
    } else if (t.length() == 2 && (t.at(0).toLatin1() == 'a')) {
        // The result must be an array of typed data
        if (!value.isArray()) {
            qWarning() << "Invalid value for type specifier:" << t << "v:" << value.toVariant();
            qmlInfo(this) << "Invalid value for type specifier: " << t << " v: " << value.toVariant();
            return false;
        }

        QVariant vec = value.toVariant();
        int type = t.at(1).toLatin1();

        if (flattenVariantArrayForceType(vec, type)) {
            msg << vec;
            return true;
        }
    } else if (t == "a{sv}") {
        if (!value.isObject()) {
            qWarning() << "Invalid value for type specifier:" << t << "v:" << value.toVariant();
            qmlInfo(this) << "Invalid value for type specifier: " << t << " v: " << value.toVariant();
            return false;
        }
        QVariantMap variantMap;
        QJSValueIterator it(value);
        while (it.hasNext()) {
            it.next();
            QVariant var = it.value().toVariant();
            flattenVariantArrayGuessType(var);
            variantMap.insert(it.name(), var);
        }

        msg << variantMap;
        return true;
    }

    qWarning() << "DeclarativeDBusInterface::typedCall - Invalid type specifier:" << t;
    qmlInfo(this) << "DeclarativeDBusInterface::typedCall - Invalid type specifier: " << t;
    return false;
}

QDBusMessage
DeclarativeDBusInterface::constructMessage(const QString &service,
                                           const QString &path,
                                           const QString &interface,
                                           const QString &method,
                                           const QJSValue &arguments)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);

    if (arguments.isArray()) {
        quint32 len = arguments.property(QLatin1String("length")).toUInt();
        for (quint32 i = 0; i < len; ++i) {
            if (!marshallDBusArgument(message, arguments.property(i)))
                return QDBusMessage();
        }
    } else if (!arguments.isUndefined()) {
        // arguments is a singular typed value
        if (!marshallDBusArgument(message, arguments))
            return QDBusMessage();
    }
    return message;
}

void DeclarativeDBusInterface::updateServiceWatcher()
{
    delete m_serviceWatcher;
    m_serviceWatcher = nullptr;

    if (!m_service.isEmpty() && m_watchServiceStatus) {
        QDBusConnection conn = DeclarativeDBus::connection(m_bus);
        m_serviceWatcher = new QDBusServiceWatcher(m_service, conn,
                                                   QDBusServiceWatcher::WatchForRegistration |
                                                   QDBusServiceWatcher::WatchForUnregistration, this);
        connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered,
                this, &DeclarativeDBusInterface::serviceRegistered);
        connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered,
                this, &DeclarativeDBusInterface::serviceUnregistered);

        if (conn.interface()->isServiceRegistered(m_service)) {
            QMetaObject::invokeMethod(this, "serviceRegistered", Qt::QueuedConnection);
        }
    }
}

bool DeclarativeDBusInterface::serviceAvailable() const
{
    // If we're not interrested about watching service status, treat service as available.
    return !m_watchServiceStatus || m_status == Available;
}

/*!
    \qmlmethod bool DBusInterface::typedCall(string method, var arguments, var callback, var errorCallback)

    Call a D-Bus method with the name \a method on the object with \a arguments. Each parameter is
    described by an object:

    \code
    {
        'type': 'o'
        'value': '/org/example'
    }
    \endcode

    Where \c type is the D-Bus type that \c value should be marshalled as. \a arguments can be
    either a single object describing the parameter or an array of objects.

    A method with the D-Bus signature \c{ssa{sv}}, so two string parameters and an array of dict
    can be called like this:

    \code
    typedCall("setInventory", [
        { "type" : 's', "value": "apple" },
        { "type" : 's', "value": "banana" },
        { "type" : 'a{sv}',
          "value": [ { "name": "rose", "color": "red", "hasThorns": true, "count": 3 } ],
        },
    ])
    \endcode

    When the function returns, \a callback is called with the method reply message as a single argument.
    If the function fails, \a errorCallback is called with two parameters, the
    error name (e.g. \c org.freedesktop.DBus.Error.InvalidArgs) and the error
    message ("Failed to create method call (Invalid argument)").

    Both callback arguments are optional, if set to \c undefined (the default),
    the return value and/or error messages will be discarded.

*/
bool DeclarativeDBusInterface::typedCall(const QString &method, const QJSValue &arguments,
                                         const QJSValue &callback,
                                         const QJSValue &errorCallback)
{
    QDBusMessage message = constructMessage(m_service, m_path, m_interface, method, arguments);
    if (message.type() == QDBusMessage::InvalidMessage) {
        qmlInfo(this) << "Invalid message, cannot call method: " << method;
        return false;
    }

    return dispatch(message, callback, errorCallback);
}

bool DeclarativeDBusInterface::dispatch(
        const QDBusMessage &message, const QJSValue &callback, const QJSValue &errorCallback)
{
    QDBusConnection conn = DeclarativeDBus::connection(m_bus);

    if (callback.isUndefined()) {
        // Call without waiting for return value (callback is undefined)
        if (!conn.send(message)) {
            qmlInfo(this) << conn.lastError();
        }
        return true;
    }

    // If we have a non-undefined callback, it must be callable
    if (!callback.isCallable()) {
        qmlInfo(this) << "Callback argument is not a function";
        return false;
    }

    if (!errorCallback.isUndefined() && !errorCallback.isCallable()) {
        qmlInfo(this) << "Error callback argument is not a function or undefined";
        return false;
    }

    if (!conn.isConnected()) {
        // Keel: without a bus, asyncCall gives a pending call that never
        // finishes, so neither callback would ever run. Fail the call the way
        // a refused one fails: the error callback, after this call returns.
        const QString name = QStringLiteral("org.freedesktop.DBus.Error.Disconnected");
        const QString text = conn.lastError().isValid()
                ? conn.lastError().message()
                : QStringLiteral("Not connected to D-Bus server");
        QMetaObject::invokeMethod(this, [this, errorCallback, name, text]() {
            failCall(errorCallback, name, text);
        }, Qt::QueuedConnection);
        return true;
    }

    QDBusPendingCall pendingCall = conn.asyncCall(message);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pendingCall);
    connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher*)),
            this, SLOT(pendingCallFinished(QDBusPendingCallWatcher*)));
    m_pendingCalls.insert(watcher, qMakePair(callback, errorCallback));
    return true;
}

/*!
    \qmlmethod var DBusInterface::getProperty(string name)

    Returns the the D-Bus property named \a name from the object.
*/
QVariant DeclarativeDBusInterface::getProperty(const QString &name)
{
    QDBusMessage message =
            QDBusMessage::createMethodCall(m_service, m_path,
                                           PropertyInterface,
                                           QLatin1String("Get"));

    QVariantList args;
    args.append(m_interface);
    args.append(name);

    message.setArguments(args);

    QDBusConnection conn = DeclarativeDBus::connection(m_bus);

    QDBusMessage reply = conn.call(message);
    if (reply.type() == QDBusMessage::ErrorMessage)
        return QVariant();
    if (reply.arguments().isEmpty())
        return QVariant();

    return NemoDBus::demarshallDBusArgument(reply.arguments().first());
}

/*!
    \qmlmethod void DBusInterface::setProperty(string name, var value)

    Sets the D-Bus property named \a name on the object to \a value.

    \since version 2.0.0
*/
void DeclarativeDBusInterface::setProperty(const QString &name, const QVariant &newValue)
{
    QDBusMessage message = QDBusMessage::createMethodCall(m_service, m_path,
                                                          PropertyInterface,
                                                          QLatin1String("Set"));

    QVariant value = newValue;
    if (value.userType() == qMetaTypeId<QJSValue>())
        value = value.value<QJSValue>().toVariant();


    QVariantList args;
    args.append(m_interface);
    args.append(name);
    args.append(QVariant::fromValue(QDBusVariant(value)));
    message.setArguments(args);

    QDBusConnection conn = DeclarativeDBus::connection(m_bus);
    if (!conn.send(message))
        qmlInfo(this) << conn.lastError();
}

void DeclarativeDBusInterface::classBegin()
{
}

void DeclarativeDBusInterface::componentComplete()
{
    m_componentCompleted = true;
    connectSignalHandler();
    connectPropertyHandler();
}

void DeclarativeDBusInterface::failCall(const QJSValue &errorCallback, const QString &name,
                                        const QString &message)
{
    if (errorCallback.isCallable()) {
        QJSValueList args = { QJSValue(name), QJSValue(message) };
        QJSValue result = errorCallback.call(args);
        if (result.isError()) {
            qmlInfo(this) << "Error executing error handling callback";
        }
    } else {
        qmlInfo(this) << name << ": " << message;
    }
}

void DeclarativeDBusInterface::pendingCallFinished(QDBusPendingCallWatcher *watcher)
{
    QPair<QJSValue, QJSValue> callbacks = m_pendingCalls.take(watcher);

    watcher->deleteLater();

    QDBusPendingReply<> reply = *watcher;

    if (reply.isError()) {
        failCall(callbacks.second, reply.error().name(), reply.error().message());
        return;
    }

    QJSValue callback = callbacks.first;
    if (!callback.isCallable())
        return;

    QJSEngine *engine = qjsEngine(this);
    if (!engine) {
        qmlInfo(this) << "Error getting QJSEngine";
        return;
    }

    QDBusMessage message = reply.reply();

    QJSValueList callbackArguments;

    QVariantList arguments = message.arguments();
    foreach (QVariant argument, arguments) {
        callbackArguments << engine->toScriptValue<QVariant>(NemoDBus::demarshallDBusArgument(argument));
    }

    QJSValue result = callback.call(callbackArguments);
    if (result.isError()) {
        qmlInfo(this) << "Error executing callback";
    }
}

void DeclarativeDBusInterface::signalHandler(const QDBusMessage &message)
{
    QVariantList arguments = message.arguments();
    QVariantList normalized;

    QGenericArgument args[10];

    for (int i = 0; i < qMin(arguments.length(), 10); ++i) {
        const QVariant &tmp = arguments.at(i);
        normalized.append(NemoDBus::demarshallDBusArgument(tmp));
    }

    QMetaMethod method = m_signals.value(message.member());
    if (!method.isValid())
        return;

    // Modified by Shipwright: pass each argument as the type the handler
    // declares. QML functions take QVariant, and Qt 6.5+ refuses to convert
    // a concrete type to QVariant inside QMetaMethod::invoke().
    const QList<QByteArray> parameterTypes = method.parameterTypes();
    for (int i = 0; i < normalized.count(); ++i) {
        const QVariant &arg = normalized.at(i);
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
        if (i >= parameterTypes.count() || parameterTypes.at(i) == "QVariant")
            args[i] = QGenericArgument("QVariant", &arg);
        else
            args[i] = QGenericArgument(QMetaType(arg.metaType()).name(), arg.data());
#else
        args[i] = Q_ARG(QVariant, arg);
#endif
    }

    method.invoke(this, args[0], args[1], args[2], args[3], args[4],
                  args[5], args[6], args[7], args[8], args[9]);
}

static int indexOfMangledName(const QString &name, const QStringList &candidates)
{
    int index = candidates.indexOf(name);
    if (index >= 0) {
        return index;
    } else if (name.length() > 2
               && name.startsWith(QStringLiteral("rc"))
               && name.at(2).isUpper()) {
        // API version 1.0 name mangling:
        // Connect QML signals with the prefix 'rc' followed by an upper-case
        // letter to DBus signals of the same name minus the prefix.
        return candidates.indexOf(name.mid(2));
    } else if (name.length() >= 2) {
        // API version 2.0 name mangling:
        //  "methodName" -> "MethodName" (if a corresponding signal exists)
        return candidates.indexOf(name.at(0).toUpper() + name.mid(1));
    } else {
        return -1;
    }
}

void DeclarativeDBusInterface::introspectionDataReceived(const QString &introspectionData)
{
    invalidateIntrospection();
    m_introspected = true;

    QStringList dbusSignals;
    QStringList dbusProperties;

    QXmlStreamReader xml(introspectionData);
    while (!xml.atEnd()) {
        if (!xml.readNextStartElement())
            continue;

        if (xml.name() == QLatin1String("node"))
            continue;

        bool skip = false;
        if (xml.name() != QLatin1String("interface")) {
            skip = true;
        } else {
            if (xml.attributes().value(QLatin1String("name")) == PropertyInterface) {
                m_providesPropertyInterface = true;
            }
            skip = xml.attributes().value(QLatin1String("name")) != m_interface;
        }

        if (skip) {
            xml.skipCurrentElement();
            continue;
        }

        while (!xml.atEnd()) {
            if (!xml.readNextStartElement())
                break;

            if (xml.name() == QLatin1String("signal"))
                dbusSignals.append(xml.attributes().value(QLatin1String("name")).toString());
            if (xml.name() == QLatin1String("property"))
                dbusProperties.append(xml.attributes().value(QStringLiteral("name")).toString());

            xml.skipCurrentElement();
        }
    }

    if (dbusSignals.isEmpty() && dbusProperties.isEmpty() && !m_propertiesEnabled)
        return;

    // Skip over signals defined in DeclarativeDBusInterface and its parent classes
    // so only signals defined in qml are connected to.
    const QMetaObject *const meta = metaObject();
    for (int i = staticMetaObject.methodCount(); i < meta->methodCount(); ++i) {
        QMetaMethod method = meta->method(i);

        const int index = indexOfMangledName(method.name(), dbusSignals);
        if (index < 0)
            continue;

        m_signals.insert(dbusSignals.at(index), method);

        dbusSignals.removeAt(index);

        if (dbusSignals.isEmpty())
            break;
    }

    for (int i = staticMetaObject.propertyCount(); i < meta->propertyCount(); ++i) {
        QMetaProperty property = meta->property(i);

        const int index = indexOfMangledName(property.name(), dbusProperties);
        if (index < 0)
            continue;

        m_properties.insert(dbusProperties.at(index), property);

        dbusProperties.removeAt(index);

        if (dbusProperties.isEmpty())
            break;
    }

    connectSignalHandler();
    connectPropertyHandler();
}

void DeclarativeDBusInterface::notifyPropertyChange(const QDBusMessage &message)
{
    const QVariantList arguments = message.arguments();

    if (arguments.value(0) == m_interface) {
        updatePropertyValues(arguments.value(1).value<QDBusArgument>());

        foreach (const QString &name, arguments.value(2).value<QStringList>()) {
            if (m_properties.contains(name)) {
                queryPropertyValues();
                break;
            }
        }

        emit propertiesChanged();
    }
}

void DeclarativeDBusInterface::disconnectSignalHandler()
{
    if (m_signalsConnected) {
        m_signalsConnected = false;

        QDBusConnection conn = DeclarativeDBus::connection(m_bus);

        foreach (const QString &signal, m_signals.keys()) {
            conn.disconnect(m_service, m_path, m_interface, signal,
                            this, SLOT(signalHandler(QDBusMessage)));
        }

        if (!m_propertiesEnabled) {
            disconnectPropertyHandler();
        }
    }
}

void DeclarativeDBusInterface::connectSignalHandler()
{
    if (!m_componentCompleted
            || m_signalsConnected
            || !m_signalsEnabled
            || m_service.isEmpty()
            || m_path.isEmpty()
            || m_interface.isEmpty()
            || !serviceAvailable()) {
        return;
    }

    if (!m_introspected) {
        introspect();
    } else if (!m_signals.isEmpty() || m_providesPropertyInterface) {
        m_signalsConnected = true;

        QDBusConnection conn = DeclarativeDBus::connection(m_bus);

        foreach (const QString &signal, m_signals.keys()) {
            conn.connect(m_service, m_path, m_interface, signal,
                         this, SLOT(signalHandler(QDBusMessage)));
        }

        connectPropertyHandler();
    }
}

void DeclarativeDBusInterface::connectPropertyHandler()
{
    if (!m_componentCompleted
            || m_propertiesConnected
            || (!m_propertiesEnabled && !m_signalsEnabled)
            || m_service.isEmpty()
            || m_path.isEmpty()
            || m_interface.isEmpty()
            || !serviceAvailable()) {
        return;
    }

    if (!m_introspected) {
        introspect();
    } else if (m_providesPropertyInterface || !m_properties.isEmpty()) {
        m_propertiesConnected = DeclarativeDBus::connection(m_bus).connect(
                    m_service,
                    m_path,
                    PropertyInterface,
                    QStringLiteral("PropertiesChanged"),
                    this,
                    SLOT(notifyPropertyChange(QDBusMessage)));
        if (!m_propertiesConnected) {
            qmlInfo(this) << "Failed to connect to DBus property interface signaling, service: "
                          << m_service << " path: " << m_path;
        }

        queryPropertyValues();
    }
}

void DeclarativeDBusInterface::disconnectPropertyHandler()
{
    if (m_propertiesConnected) {
        m_propertiesConnected = false;

        DeclarativeDBus::connection(m_bus).disconnect(
                    m_service,
                    m_path,
                    PropertyInterface,
                    QStringLiteral("PropertiesChanged"),
                    this,
                    SLOT(notifyPropertyChange(QDBusMessage)));
    }
}

void DeclarativeDBusInterface::queryPropertyValues()
{
    if (m_propertiesConnected && m_propertiesEnabled) {
        QDBusMessage message = QDBusMessage::createMethodCall(
                    m_service, m_path, PropertyInterface, QStringLiteral("GetAll"));
        message.setArguments(QVariantList() << m_interface);

        DeclarativeDBus::connection(m_bus).callWithCallback(
                    message, this, SLOT(propertyValuesReceived(QDBusMessage)));
    }
}

void DeclarativeDBusInterface::propertyValuesReceived(const QDBusMessage &message)
{
    updatePropertyValues(message.arguments().value(0).value<QDBusArgument>());
}

void DeclarativeDBusInterface::serviceRegistered()
{
    m_status = Available;
    emit statusChanged();

    connectSignalHandler();
    connectPropertyHandler();
}

void DeclarativeDBusInterface::serviceUnregistered()
{
    m_status = Unavailable;
    emit statusChanged();
}

void DeclarativeDBusInterface::updatePropertyValues(const QDBusArgument &argument)
{
    if (m_propertiesEnabled) {
        argument.beginMap();
        while (!argument.atEnd()) {
            argument.beginMapEntry();

            const QString name = argument.asVariant().toString();
            QMetaProperty property = m_properties.value(name);
            if (property.isValid()) {
                property.write(this, NemoDBus::demarshallDBusArgument(argument.asVariant()));
            }

            argument.endMapEntry();
        }
        argument.endMap();
    }
}

void DeclarativeDBusInterface::invalidateIntrospection()
{
    disconnectSignalHandler();
    disconnectPropertyHandler();

    m_introspected = false;
    m_providesPropertyInterface = false;
    m_signals.clear();
    m_properties.clear();
}

void DeclarativeDBusInterface::introspect()
{
    m_introspected = true;

    QDBusMessage message
            = QDBusMessage::createMethodCall(m_service, m_path,
                                             QLatin1String("org.freedesktop.DBus.Introspectable"),
                                             QLatin1String("Introspect"));

    if (message.type() == QDBusMessage::InvalidMessage)
        return;

    QDBusConnection conn = DeclarativeDBus::connection(m_bus);

    if (!conn.callWithCallback(message, this, SLOT(introspectionDataReceived(QString)))) {
        qmlInfo(this) << "Failed to introspect interface " << conn.lastError();
    }
}
