// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2016 - 2019 Jolla Ltd
// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only

/***************************************************************************
**
** Copyright (C) 2021 Open Mobile Platform LLC.
** Copyright (C) 2016 - 2019 Jolla Ltd.
** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
** All rights reserved.
** Contact: Nokia Corporation (directui@nokia.com)
**
** This file is part of libmeegotouch.
**
** If you have questions regarding the use of this file, please contact
** Nokia at directui@nokia.com.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#include "mremoteaction.h"
#include "mremoteaction_p.h"

#include <QDBusInterface>
#include <QDBusPendingCall>
#include <QBuffer>
#include <QStringList>
#include <QDataStream>

#include <unistd.h>

namespace {
    int RemoteActionTimeout = 120 * 1000; // D-Bus activation timeout
}

MRemoteActionPrivate::MRemoteActionPrivate()
{
}

MRemoteActionPrivate::~MRemoteActionPrivate()
{
}

void MRemoteActionPrivate::trigger(bool wait)
{
    const int uid = getuid();
    const int gid = getgid();
    const int euid = geteuid();
    const int egid = getegid();

    if (!keepPrivileges && (uid != euid || gid != egid)) {
        QProcess::startDetached(QStringLiteral("/usr/libexec/mliteremoteaction"), { toString() });
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(serviceName, objectPath, interface, methodName);
    msg.setArguments(arguments);

    QDBusConnection::sessionBus().call(msg, wait ? QDBus::Block : QDBus::NoBlock, RemoteActionTimeout);
}

QString MRemoteActionPrivate::toString() const
{
    QString s;
    if (!serviceName.isEmpty() && !objectPath.isEmpty() && !interface.isEmpty() && !methodName.isEmpty()) {
        s.append(serviceName).append(' ');
        s.append(objectPath).append(' ');
        s.append(interface).append(' ');
        s.append(methodName);

        for (const QVariant &arg : arguments) {
            // Serialize the QVariant into a QBuffer
            QBuffer buffer;
            buffer.open(QIODevice::ReadWrite);
            QDataStream stream(&buffer);
            stream << arg;
            buffer.close();

            // Encode the contents of the QBuffer in Base64
            s.append(' ');
            s.append(buffer.buffer().toBase64().data());
        }
    }

    return s;
}

MRemoteAction::MRemoteAction(const QString &serviceName, const QString &objectPath, const QString &interface,
                             const QString &methodName, const QList<QVariant> &arguments, QObject *parent)
    : QObject(parent)
    , d_ptr(new MRemoteActionPrivate)
{
    Q_D(MRemoteAction);

    d->serviceName = serviceName;
    d->objectPath = objectPath;
    d->interface = interface;
    d->methodName = methodName;
    d->arguments = arguments;
}

MRemoteAction::MRemoteAction(const QString &string, QObject *parent)
    : QObject(parent)
    , d_ptr(new MRemoteActionPrivate)
{
    fromString(string);
}

MRemoteAction::~MRemoteAction()
{
    delete d_ptr;
}

QString MRemoteAction::toString() const
{
    Q_D(const MRemoteAction);
    return d->toString();
}

void MRemoteAction::fromString(const QString &string)
{
    Q_D(MRemoteAction);

    QStringList l = string.split(' ');

    if (l.count() > 3) {
        d->serviceName = l.at(0);
        d->objectPath = l.at(1);
        d->interface = l.at(2);
        d->methodName = l.at(3);
    }

    const int count = l.count();
    for (int i = 4; i < count; ++i) {
        QByteArray byteArray = QByteArray::fromBase64(l.at(i).toLatin1());
        QBuffer buffer(&byteArray);
        buffer.open(QIODevice::ReadOnly);
        QDataStream stream(&buffer);
        QVariant arg;
        stream >> arg;
        buffer.close();

        d->arguments.append(arg);
    }
}

MRemoteAction::MRemoteAction(const MRemoteAction &action)
    : QObject(action.parent())
    , d_ptr(new MRemoteActionPrivate(*action.d_ptr))
{
}

bool MRemoteAction::isValid() const
{
    Q_D(const MRemoteAction);
    return !d->serviceName.isEmpty()
            && !d->objectPath.isEmpty()
            && !d->interface.isEmpty()
            && !d->methodName.isEmpty();
}

QString MRemoteAction::serviceName() const
{
    Q_D(const MRemoteAction);
    return d->serviceName;
}

QString MRemoteAction::objectPath() const
{
    Q_D(const MRemoteAction);
    return d->objectPath;
}

QString MRemoteAction::interface() const
{
    Q_D(const MRemoteAction);
    return d->interface;
}

QString MRemoteAction::methodName() const
{
    Q_D(const MRemoteAction);
    return d->methodName;
}

QVariantList MRemoteAction::arguments() const
{
    Q_D(const MRemoteAction);
    return d->arguments;
}

void MRemoteAction::setServiceName(const QString &service)
{
    Q_D(MRemoteAction);
    d->serviceName = service;
}

void MRemoteAction::setObjectPath(const QString &path)
{
    Q_D(MRemoteAction);
    d->objectPath = path;
}

void MRemoteAction::setInterface(const QString &interface)
{
    Q_D(MRemoteAction);
    d->interface = interface;
}

void MRemoteAction::setArguments(const QVariantList &arguments)
{
    Q_D(MRemoteAction);
    d->arguments = arguments;
}

bool MRemoteAction::keepPrivileges() const
{
    Q_D(const MRemoteAction);
    return d->keepPrivileges;
}

void MRemoteAction::setKeepPrivileges(bool keep)
{
    Q_D(MRemoteAction);
    d->keepPrivileges = keep;
}

void MRemoteAction::trigger()
{
    Q_D(MRemoteAction);
    d->trigger(false);
}

void MRemoteAction::triggerAndWait()
{
    Q_D(MRemoteAction);
    d->trigger(true);
}
