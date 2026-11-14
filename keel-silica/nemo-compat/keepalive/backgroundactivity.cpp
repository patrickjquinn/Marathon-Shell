// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Valerio Valerio <valerio.valerio@jollamobile.com>
**
** All rights reserved.
**
** This file is part of nemo-keepalive package.
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

#include "backgroundactivity_p.h"
#include "common.h"

/* ========================================================================= *
 * class BackgroundActivity
 * ========================================================================= */

BackgroundActivity::BackgroundActivity(QObject *parent)
    : QObject(parent)
{
    TRACE
    priv = new BackgroundActivityPrivate(this);

    QObject::connect(priv->m_heartbeat, SIGNAL(timeout()),
                     this, SLOT(run()));
}

BackgroundActivity::~BackgroundActivity()
{
    TRACE
    delete priv;
}

BackgroundActivity::Frequency BackgroundActivity::wakeupFrequency() const
{
    return priv->wakeupSlot();
}

void BackgroundActivity::wakeupRange(int &min_delay, int &max_delay) const
{
    priv->wakeupRange(min_delay, max_delay);
}

void BackgroundActivity::setWakeupFrequency(Frequency slot)
{
    TRACE
    priv->setWakeupFrequency(slot);
}

void BackgroundActivity::setWakeupRange(int min_delay, int max_delay)
{
    TRACE
    priv->setWakeupRange(min_delay, max_delay);
}

BackgroundActivity::State BackgroundActivity::state() const
{
    return priv->state();
}

void BackgroundActivity::setState(BackgroundActivity::State new_state)
{
    TRACE
    priv->setState(new_state);
}

void BackgroundActivity::wait()
{
    TRACE
    setState(BackgroundActivity::Waiting);
}

void BackgroundActivity::wait(Frequency slot)
{
    TRACE
    setWakeupFrequency(slot), wait();
}

void BackgroundActivity::wait(int min_delay, int max_delay)
{
    TRACE
    setWakeupRange(min_delay, max_delay), wait();
}

void BackgroundActivity::run()
{
    TRACE
    setState(BackgroundActivity::Running);
}

void BackgroundActivity::stop()
{
    TRACE
    setState(BackgroundActivity::Stopped);
}

bool BackgroundActivity::isWaiting() const
{
    return state() == BackgroundActivity::Waiting;
}

bool BackgroundActivity::isRunning() const
{
    return state() == BackgroundActivity::Running;
}

bool BackgroundActivity::isStopped() const
{
    return state() == BackgroundActivity::Stopped;
}

QString BackgroundActivity::id() const
{
    return priv->id();
}
