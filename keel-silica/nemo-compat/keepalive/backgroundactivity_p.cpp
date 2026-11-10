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
#include "heartbeat.h"
#include "common.h"

#include <QtGlobal>

#include <errno.h>

#include <mce/dbus-names.h>

/* ========================================================================= *
 * class BackgroundActivityPrivate
 * ========================================================================= */

static QString get_unique_id()
{
    static unsigned id = 0;
    char temp[32];
    snprintf(temp, sizeof temp, "BlockSuspend-%u", ++id);
    return QString(temp);
}

/* ------------------------------------------------------------------------- *
 * contructors & destructor
 * ------------------------------------------------------------------------- */

BackgroundActivityPrivate::BackgroundActivityPrivate(BackgroundActivity *parent)
    : QObject(parent)
{
    pub = parent;

    m_id = get_unique_id();

    // Default to: Stopped
    m_state = BackgroundActivity::Stopped;

    // Default to: No wakeup defined
    m_wakeup_freq = BackgroundActivity::Range;
    m_wakeup_range_min = 0;
    m_wakeup_range_max = 0;

    m_heartbeat = new Heartbeat(this);

    // The MCE D-Bus interface is created on demand
    m_mce_interface = 0;

    // Renew period has not been queried from MCE, but default to 1 minute
    m_keepalive_queried = false;
    m_keepalive_period  = 60; // [s]
    m_keepalive_timer   = new QTimer();
    connect(m_keepalive_timer, SIGNAL(timeout()), this, SLOT(renewKeepalivePeriod()));
}

BackgroundActivityPrivate::~BackgroundActivityPrivate()
{
    delete m_heartbeat;
    delete m_keepalive_timer;
    delete m_mce_interface;
}

/* ------------------------------------------------------------------------- *
 * keepalive timer
 * ------------------------------------------------------------------------- */

void
BackgroundActivityPrivate::startKeepalivePeriod()
{
    // Sanity check
    if (m_state != BackgroundActivity::Running) {
        return;
    }
    TRACE

    mceInterface()->req_cpu_keepalive_start(m_id);
    m_keepalive_timer->setInterval(m_keepalive_period * 1000); // [ms]
    m_keepalive_timer->start();
}

void
BackgroundActivityPrivate::renewKeepalivePeriod()
{
    TRACE
    mceInterface()->req_cpu_keepalive_start(m_id);
}

void
BackgroundActivityPrivate::stopKeepalivePeriod()
{
    TRACE
    m_keepalive_timer->stop();
    mceInterface()->req_cpu_keepalive_stop(m_id);
}

/* ------------------------------------------------------------------------- *
 * IPC with MCE
 * ------------------------------------------------------------------------- */

ComNokiaMceRequestInterface *
BackgroundActivityPrivate::mceInterface()
{
    if (!m_mce_interface) {
        //qDebug("@ %s\n", __PRETTY_FUNCTION__);
        m_mce_interface = new ComNokiaMceRequestInterface(MCE_SERVICE,
                                                          MCE_REQUEST_PATH,
                                                          QDBusConnection::systemBus(),
                                                          this);
    }
    return m_mce_interface;
}

void
BackgroundActivityPrivate::keepalivePeriodReply(QDBusPendingCallWatcher *call)
{
    TRACE

    QDBusPendingReply<int> pc = *call;

    if (!pc.isValid()) {
        qWarning("INVALID keepalive period reply");
    } else if (pc.isError()) {
        qWarning() << pc.error();
    } else {
        int period = pc.value(); // [s]

        if (m_keepalive_period != period) {
            m_keepalive_period = period;

            // if timer is already active
            if (m_keepalive_timer->isActive()) {
                // stop timer
                m_keepalive_timer->stop();
                // make extra renew request
                renewKeepalivePeriod();
                // restart timer with modified period
                m_keepalive_timer->setInterval(m_keepalive_period * 1000); // [ms]
                m_keepalive_timer->start();
            }
        }
    }

    call->deleteLater();
}

void
BackgroundActivityPrivate::queryKeepalivePeriod()
{
    if (m_keepalive_queried) {
        // Already done
        return;
    }
    TRACE

    m_keepalive_queried = true;

    QDBusPendingReply<int> pc = mceInterface()->req_cpu_keepalive_period();

    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pc, this);

    connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher *)),
            this, SLOT(keepalivePeriodReply(QDBusPendingCallWatcher *)));
}

/* ------------------------------------------------------------------------- *
 * STATE
 * ------------------------------------------------------------------------- */

BackgroundActivity::State
BackgroundActivityPrivate::state() const
{
    return m_state;
}

void
BackgroundActivityPrivate::setState(BackgroundActivity::State new_state)
{
    /* do nothing if the state does not change */
    if (m_state == new_state) {
        return;
    }

    TRACE

    /* leave old state */
    bool was_running = false;

    switch (m_state) {
    case BackgroundActivity::Stopped:
        break;

    case BackgroundActivity::Waiting:
        /* heartbeat timer can be cancelled before state transition */
        m_heartbeat->stop();
        break;

    case BackgroundActivity::Running:
        /* keepalive timer must be cancelled after state transition */
        was_running = true;
        break;
    }

    /* enter new state */
    m_state = new_state;
    switch (m_state) {
    case BackgroundActivity::Stopped:
        break;
    case BackgroundActivity::Waiting:
        queryKeepalivePeriod();

        if (m_wakeup_freq != BackgroundActivity::Range) {
            m_heartbeat->setInterval(m_wakeup_freq);
        } else {
            m_heartbeat->setInterval(m_wakeup_range_min, m_wakeup_range_max);
        }

        m_heartbeat->start();
        break;
    case BackgroundActivity::Running:
        queryKeepalivePeriod();
        startKeepalivePeriod();
        break;
    }

    /* special case: allow heartbeat timer reprogramming
     * to occur before stopping the keepalive period */
    if ( was_running ) {
        stopKeepalivePeriod();
    }

    /* emit state transition signals */
    Q_EMIT pub->stateChanged();
    switch (m_state) {
    case BackgroundActivity::Stopped:
        Q_EMIT pub->stopped();
        break;
    case BackgroundActivity::Waiting:
        Q_EMIT pub->waiting();
        break;
    case BackgroundActivity::Running:
        Q_EMIT pub->running();
        break;
    }
}

BackgroundActivity::Frequency
BackgroundActivityPrivate::wakeupSlot() const
{
    return m_wakeup_freq;
}

void
BackgroundActivityPrivate::wakeupRange(int &range_min, int &range_max) const
{
    range_min = m_wakeup_range_min;
    range_max = m_wakeup_range_max;
}

void
BackgroundActivityPrivate::setWakeup(BackgroundActivity::Frequency slot,
                                     int range_min, int range_max)
{
    TRACE
    // TODO: need a way not to hardcode this
    const int heartbeat_interval = 12;

    BackgroundActivity::Frequency old_slot = m_wakeup_freq;
    int old_wakeup_range_min = m_wakeup_range_min;
    int old_wakeup_range_max = m_wakeup_range_max;

    if (slot != BackgroundActivity::Range) {
        m_wakeup_freq = slot;
        m_wakeup_range_min = 0;
        m_wakeup_range_max = 0;
    } else {
        if (range_max < range_min) {
            range_max = range_min + heartbeat_interval;
        }
        m_wakeup_freq = BackgroundActivity::Range;
        m_wakeup_range_min = range_min;
        m_wakeup_range_max = range_max;
    }

    if (old_slot !=  m_wakeup_freq) {
        Q_EMIT pub->wakeupFrequencyChanged();
    }

    if (old_wakeup_range_min != m_wakeup_range_min ||
            old_wakeup_range_max != m_wakeup_range_max) {
        Q_EMIT pub->wakeupRangeChanged();
    }
}

void
BackgroundActivityPrivate::setWakeupFrequency(BackgroundActivity::Frequency slot)
{
    TRACE
    setWakeup(slot, 0, 0);
}

void
BackgroundActivityPrivate::setWakeupRange(int range_min, int range_max)
{
    TRACE
    setWakeup(BackgroundActivity::Range, range_min, range_max);
}

QString
BackgroundActivityPrivate::id() const
{
    return m_id;
}
