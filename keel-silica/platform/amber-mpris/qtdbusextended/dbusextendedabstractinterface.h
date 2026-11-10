// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
// -*- c++ -*-

/*!
 *
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
 */


#ifndef DBUSEXTENDEDABSTRACTINTERFACE_H
#define DBUSEXTENDEDABSTRACTINTERFACE_H

#include <DBusExtended>

#include <QDBusAbstractInterface>
#include <QDBusError>
#include <QDebug>
#include <QMetaProperty>

class QDBusPendingCallWatcher;

namespace Amber {
namespace Private {
class DBusExtendedPendingCallWatcher;

class QT_DBUS_EXTENDED_EXPORT DBusExtendedAbstractInterface: public QDBusAbstractInterface
{
    Q_OBJECT

public:
    virtual ~DBusExtendedAbstractInterface();

    Q_PROPERTY(bool sync READ sync WRITE setSync)
    inline bool sync() const { return m_sync; }
    inline void setSync(bool sync) { m_sync = sync; }

    Q_PROPERTY(bool useCache READ useCache WRITE setUseCache)
    inline bool useCache() const { return m_useCache; }
    inline void setUseCache(bool useCache) { m_useCache = useCache; }

    void getAllProperties();
    inline QDBusError lastExtendedError() const { return m_lastExtendedError; };

protected:
    DBusExtendedAbstractInterface(const QString &service,
                                  const QString &path,
                                  const char *interface,
                                  const QDBusConnection &connection,
                                  QObject *parent);

    void connectNotify(const QMetaMethod &signal);
    void disconnectNotify(const QMetaMethod &signal);
    QVariant internalPropGet(const char *propname, void *propertyPtr);
    void internalPropSet(const char *propname, const QVariant &value);

    // Can be used for accessing properties stored with a different type internally
    template<class External, class Internal>
    External internalPropGetExternal(const char *propname, Internal *propertyPtr, External convert(Internal from));
    template<class Internal, class External>
    Internal internalPropGetInternal(const char *propname, Internal *propertyPtr, Internal convert(External from));

Q_SIGNALS:
    void propertyChanged(const QString &propertyName, const QVariant &value);
    void propertyInvalidated(const QString &propertyName);
    void asyncPropertyFinished(const QString &propertyName);
    void asyncSetPropertyFinished(const QString &propertyName);
    void asyncGetAllPropertiesFinished();

private Q_SLOTS:
    void onPropertiesChanged(const QString& interfaceName,
                             const QVariantMap& changedProperties,
                             const QStringList& invalidatedProperties);
    void onAsyncPropertyFinished(QDBusPendingCallWatcher *watcher, const QString &propertyName);
    void onAsyncSetPropertyFinished(QDBusPendingCallWatcher *watcher, const QString &propertyName, const QVariant value);
    void onAsyncGetAllPropertiesFinished(QDBusPendingCallWatcher *watcher);

private:
    QVariant asyncProperty(const QString &propertyName);
    void asyncSetProperty(const QString &propertyName, const QVariant &value);
    static QVariant demarshall(const QString &interface, const QMetaProperty &metaProperty, const QVariant &value, QDBusError *error);

    bool m_sync;
    bool m_useCache;
    QDBusPendingCallWatcher *m_getAllPendingCallWatcher;
    QDBusError m_lastExtendedError;
    bool m_propertiesChangedConnected;
};

template<class External, class Internal>
External DBusExtendedAbstractInterface::internalPropGetExternal(const char *propname, Internal *propertyPtr, External convert(Internal from))
{
    m_lastExtendedError = QDBusError();

    if (m_useCache) {
        return convert(*propertyPtr);
    }

    if (m_sync) {
        return qvariant_cast<External>(property(propname));
    } else {
        if (!isValid()) {
            QString errorMessage = QStringLiteral("This Extended DBus interface is not valid yet.");
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qDebug() << Q_FUNC_INFO << errorMessage;
            return External();
        }

        int propertyIndex = metaObject()->indexOfProperty(propname);

        if (-1 == propertyIndex) {
            QString errorMessage = QStringLiteral("Got unknown property \"%1\" to read")
                .arg(QString::fromLatin1(propname));
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qWarning() << Q_FUNC_INFO << errorMessage;
            return External();
        }

        QMetaProperty metaProperty = metaObject()->property(propertyIndex);

        if (!metaProperty.isReadable()) {
            QString errorMessage = QStringLiteral("Property \"%1\" is NOT readable")
                .arg(QString::fromLatin1(propname));
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qWarning() << Q_FUNC_INFO << errorMessage;
            return External();
        }

        asyncProperty(propname);
        return convert(*propertyPtr);
    }
}

template<class Internal, class External>
Internal DBusExtendedAbstractInterface::internalPropGetInternal(const char *propname, Internal *propertyPtr, Internal convert(External from))
{
    m_lastExtendedError = QDBusError();

    if (m_useCache) {
        return *propertyPtr;
    }

    if (m_sync) {
        return convert(qvariant_cast<External>(property(propname)));
    } else {
        if (!isValid()) {
            QString errorMessage = QStringLiteral("This Extended DBus interface is not valid yet.");
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qDebug() << Q_FUNC_INFO << errorMessage;
            return Internal();
        }

        int propertyIndex = metaObject()->indexOfProperty(propname);

        if (-1 == propertyIndex) {
            QString errorMessage = QStringLiteral("Got unknown property \"%1\" to read")
                .arg(QString::fromLatin1(propname));
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qWarning() << Q_FUNC_INFO << errorMessage;
            return Internal();
        }

        QMetaProperty metaProperty = metaObject()->property(propertyIndex);

        if (!metaProperty.isReadable()) {
            QString errorMessage = QStringLiteral("Property \"%1\" is NOT readable")
                .arg(QString::fromLatin1(propname));
            m_lastExtendedError = QDBusMessage::createError(QDBusError::Failed, errorMessage);
            qWarning() << Q_FUNC_INFO << errorMessage;
            return Internal();
        }

        asyncProperty(propname);
        return *propertyPtr;
    }
}
}
}

#endif /* DBUSEXTENDEDABSTRACTINTERFACE_H */
