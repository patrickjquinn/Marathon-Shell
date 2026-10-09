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

#ifndef DECLARATIVEDBUSADAPTOR_H
#define DECLARATIVEDBUSADAPTOR_H

#include <QObject>
#include <QtQml>
#include <QQmlParserStatus>
#include <QUrl>
#include <QJSValue>

#include <QDBusVirtualObject>

#include "declarativedbus.h"

class DeclarativeDBusAdaptor : public QDBusVirtualObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_PROPERTY(QString service READ service WRITE setService NOTIFY serviceChanged)
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString iface READ interface WRITE setInterface NOTIFY interfaceChanged)
    Q_PROPERTY(QString xml READ xml WRITE setXml NOTIFY xmlChanged)
    Q_PROPERTY(DeclarativeDBus::BusType bus READ bus WRITE setBus NOTIFY busChanged)

    Q_INTERFACES(QQmlParserStatus)

public:
    DeclarativeDBusAdaptor(QObject *parent = 0);
    ~DeclarativeDBusAdaptor();

    QString service() const;
    void setService(const QString &service);

    QString path() const;
    void setPath(const QString &path);

    QString interface() const;
    void setInterface(const QString &interface);

    QString xml() const;
    void setXml(const QString &xml);

    DeclarativeDBus::BusType bus() const;
    void setBus(DeclarativeDBus::BusType bus);

    void classBegin();
    void componentComplete();

    QString introspect(const QString &path) const;
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection);

    Q_INVOKABLE void emitSignal(const QString &name,
                                const QJSValue &arguments = QJSValue::UndefinedValue);

signals:
    void serviceChanged();
    void pathChanged();
    void interfaceChanged();
    void xmlChanged();
    void busChanged();

private:
    QString m_service;
    QString m_path;
    QString m_interface;
    QString m_xml;
    DeclarativeDBus::BusType m_bus;
};

#endif
