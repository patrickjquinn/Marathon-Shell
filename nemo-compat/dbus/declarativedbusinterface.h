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

#ifndef DECLARATIVEDBUSINTERFACE_H
#define DECLARATIVEDBUSINTERFACE_H

#include <QObject>
#include <QMap>
#include <QPair>
#include <QPointer>
#include <QVariant>
#include <QDBusArgument>
#include <QJSValue>
#include <QQmlParserStatus>
#include <QUrl>
#include <QDBusPendingCallWatcher>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QPair>

#include "declarativedbus.h"

class DeclarativeDBusInterface : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_PROPERTY(bool watchServiceStatus READ watchServiceStatus WRITE setWatchServiceStatus NOTIFY watchServiceStatusChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString service READ service WRITE setService NOTIFY serviceChanged)
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString iface READ interface WRITE setInterface NOTIFY interfaceChanged)
    Q_PROPERTY(DeclarativeDBus::BusType bus READ bus WRITE setBus NOTIFY busChanged)
    Q_PROPERTY(bool signalsEnabled READ signalsEnabled WRITE setSignalsEnabled NOTIFY signalsEnabledChanged)
    Q_PROPERTY(bool propertiesEnabled READ propertiesEnabled WRITE setPropertiesEnabled NOTIFY propertiesEnabledChanged)

    Q_INTERFACES(QQmlParserStatus)

public:
    enum Status { Unknown, Unavailable, Available };
    Q_ENUM(Status)

    DeclarativeDBusInterface(QObject *parent = 0);
    ~DeclarativeDBusInterface();

    bool watchServiceStatus() const;
    void setWatchServiceStatus(bool watchServiceStatus);

    Status status() const;

    QString service() const;
    void setService(const QString &service);

    QString path() const;
    void setPath(const QString &path);

    QString interface() const;
    void setInterface(const QString &interface);

    DeclarativeDBus::BusType bus() const;
    void setBus(DeclarativeDBus::BusType bus);

    bool signalsEnabled() const;
    void setSignalsEnabled(bool enabled);

    bool signalsConnected() const;

    bool propertiesEnabled() const;
    void setPropertiesEnabled(bool enabled);

    void propertiesConnected() const;

    Q_INVOKABLE void call(const QString &method,
                          const QJSValue &arguments = QJSValue::UndefinedValue,
                          const QJSValue &callback = QJSValue::UndefinedValue,
                          const QJSValue &errorCallback = QJSValue::UndefinedValue);
    Q_INVOKABLE bool typedCall(const QString &method, const QJSValue &arguments,
                               const QJSValue &callback = QJSValue::UndefinedValue,
                               const QJSValue &errorCallback = QJSValue::UndefinedValue);

    Q_INVOKABLE QVariant getProperty(const QString &name);
    Q_INVOKABLE void setProperty(const QString &name, const QVariant &newValue);

    void classBegin();
    void componentComplete();

    static QVariantList argumentsFromScriptValue(const QJSValue &arguments);

signals:
    void watchServiceStatusChanged();
    void statusChanged();
    void serviceChanged();
    void pathChanged();
    void interfaceChanged();
    void busChanged();
    void signalsEnabledChanged();
    void propertiesEnabledChanged();
    void propertiesChanged();

private slots:
    void pendingCallFinished(QDBusPendingCallWatcher *watcher);
    void signalHandler(const QDBusMessage &message);
    void introspectionDataReceived(const QString &introspectionData);
    void notifyPropertyChange(const QDBusMessage &message);
    void propertyValuesReceived(const QDBusMessage &message);

    void serviceRegistered();
    void serviceUnregistered();

private:
    void invalidateIntrospection();
    void introspect();
    bool dispatch(
            const QDBusMessage &message, const QJSValue &callback, const QJSValue &errorCallback);
    void failCall(const QJSValue &errorCallback, const QString &name, const QString &message);
    void disconnectSignalHandler();
    void connectSignalHandler();
    void disconnectPropertyHandler();
    void connectPropertyHandler();
    void queryPropertyValues();
    void updatePropertyValues(const QDBusArgument &values);

    bool marshallDBusArgument(QDBusMessage &msg, const QJSValue &arg);
    QDBusMessage constructMessage(const QString &service,
                                  const QString &path,
                                  const QString &interface,
                                  const QString &method,
                                  const QJSValue &arguments);

    void updateServiceWatcher();
    bool serviceAvailable() const;

    bool m_watchServiceStatus;
    Status m_status;
    QString m_service;
    QString m_path;
    QString m_interface;
    DeclarativeDBus::BusType m_bus;
    QMap<QDBusPendingCallWatcher *, QPair<QJSValue, QJSValue> >
    m_pendingCalls; // pair: success and error callback
    QMap<QString, QMetaMethod> m_signals;
    QMap<QString, QMetaProperty> m_properties;
    bool m_componentCompleted;
    bool m_signalsEnabled;
    bool m_signalsConnected;
    bool m_propertiesEnabled;
    bool m_propertiesConnected;
    bool m_introspected;
    bool m_providesPropertyInterface;

    QDBusServiceWatcher *m_serviceWatcher;
};

#endif
