// SPDX-FileCopyrightText: 2012 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * NgfClient - Qt Non-Graphic Feedback daemon client library
 *
 * Copyright (C) 2012 Jolla Ltd.
 * Contact: juho.hamalainen@tieto.com
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

#include <QObject>
#include <QDebug>

#include "ngfclient.h"
#include "clientprivate.h"

Ngf::Client::Client(QObject *parent)
    : QObject(parent), d_ptr(new ClientPrivate(this))
{
}

Ngf::Client::~Client()
{
    delete d_ptr;
}

bool Ngf::Client::connect()
{
    return d_ptr->connect();
}

bool Ngf::Client::isConnected()
{
    return d_ptr->isConnected();
}

void Ngf::Client::disconnect()
{
    d_ptr->disconnect();
}

quint32 Ngf::Client::play(const QString &event)
{
    return d_ptr->play(event);
}

quint32 Ngf::Client::play(const QString &event, const QMap<QString, QVariant> &properties)
{
    return d_ptr->play(event, properties);
}

bool Ngf::Client::pause(quint32 event_id)
{
    return d_ptr->pause(event_id);
}

bool Ngf::Client::pause(const QString &event)
{
    return d_ptr->pause(event);
}

bool Ngf::Client::resume(quint32 event_id)
{
    return d_ptr->resume(event_id);
}

bool Ngf::Client::resume(const QString &event)
{
    return d_ptr->resume(event);
}

bool Ngf::Client::stop(quint32 event_id)
{
    return d_ptr->stop(event_id);
}

bool Ngf::Client::stop(const QString &event)
{
    return d_ptr->stop(event);
}
