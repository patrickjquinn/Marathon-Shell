// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Andrea Bernabei <and.bernabei@gmail.com>
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

#include <sys/types.h>
#include <sys/socket.h>

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

#include <QtGlobal>

#include "heartbeat.h"

Heartbeat::Heartbeat(QObject *parent) : QObject(parent)
{
    m_started   = false;
    m_waiting   = false;

    m_min_delay = 0;
    m_max_delay = 0;

    m_iphb_handle     = 0;
    m_wakeup_notifier = 0;
    m_connect_timer   = new QTimer();
    QObject::connect(m_connect_timer, SIGNAL(timeout()),
                     this, SLOT(retryConnect()));
}

Heartbeat::~Heartbeat()
{
    disconnect();
    delete m_connect_timer;
}

bool
Heartbeat::tryConnect()
{
    bool   status = false;
    iphb_t handle = 0;

    if (!m_iphb_handle) {
        int fd;

        if (!(handle = iphb_open(0))) {
            qWarning("iphb_open: %s", strerror(errno));
            goto cleanup;
        }

        if ((fd = iphb_get_fd(handle)) == -1) {
            qWarning("iphb_get_fd: %s", strerror(errno));
            goto cleanup;
        }

        m_iphb_handle = handle;
        handle = 0;
        m_wakeup_notifier = new QSocketNotifier(fd, QSocketNotifier::Read);
        QObject::connect(m_wakeup_notifier, SIGNAL(activated(int)),
                         this, SLOT(wakeup(int)));
        m_wakeup_notifier->setEnabled(true);
    }

    status = true;

cleanup:
    if (handle) iphb_close(handle);

    return status;
}

void
Heartbeat::disconnect()
{
    stop();

    m_connect_timer->stop();

    delete m_wakeup_notifier;
    m_wakeup_notifier = 0;

    if (m_iphb_handle) {
        iphb_close(m_iphb_handle);
        m_iphb_handle = 0;
    }
}

void
Heartbeat::retryConnect()
{
    if (tryConnect()) {
        // cancel retry timer
        m_connect_timer->stop();
        // issue IPHB wait
        wait();
    }
}

void
Heartbeat::connect()
{
    if (m_connect_timer->isActive()) {
        // Retry timer already set up
    } else if (!tryConnect()) {
        // Start retry timer
        m_connect_timer->setInterval(5 * 1000);
        m_connect_timer->start();
    }
}

void
Heartbeat::setInterval(int mindelay, int maxdelay)
{
    // TODO: anchor to monotime to preserve over reconnect
    m_min_delay = mindelay;
    m_max_delay = maxdelay;
}

void
Heartbeat::setInterval(int global_slot)
{
    setInterval(global_slot, global_slot);
}

void
Heartbeat::start(int global_slot)
{
    setInterval(global_slot), start();
}

void
Heartbeat::start(int mindelay, int maxdelay)
{
    setInterval(mindelay, maxdelay), start();
}

void
Heartbeat::start()
{
    m_started = true;
    wait();
}

void
Heartbeat::wait()
{
    if (!m_started) {
        return;
    }

    if (m_waiting) {
        return;
    }

    if (m_min_delay <= 0) {
        qWarning("missing heartbeat delay");
        return;
    }

    if (m_max_delay < m_min_delay) {
        qWarning("invalid heartbeat delay");
        return;
    }

    if (!m_iphb_handle) {
        connect();
    }

    if (!m_waiting && m_iphb_handle) {
        int lo = m_min_delay;
        int hi = m_max_delay;
        if (lo != hi) {
            // TODO: from monotime to relative
            // TODO: timeout if already passed
        }
        iphb_wait2(m_iphb_handle, lo, hi, 0, 1);
        m_waiting = true;
    }
}

void
Heartbeat::wakeup(int fd)
{
    /* Assume socket connection is to be kept open */
    bool keep_going = true;

    /* The data itself is not interesting, we just want to
     * know whether the read succeeded or not */
    char buf[256];

    /* Stopping/reprogramming IPHB flushes pending input
     * from the socket. If that happens after decision
     * to call this input callback is already made, simple
     * read could block and that can't be allowed. */
    int rc = recv(fd, buf, sizeof buf, MSG_DONTWAIT);

    /* Deal with I/O errors */
    if (rc == -1) {
        if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
            // Recoverable errors -> ignored
        } else {
            // Irrecoverable errors -> reset connection
            keep_going = false;
        }
        goto cleanup;
    }

    /* Deal with closed socket */
    if (rc == 0) {
        // EOF -> assume DSME restart -> reset connection
        keep_going = false;
        goto cleanup;
    }

    /* Ignore any spurious wakeups */
    if (!m_waiting) {
        qWarning("unexpected heartbeat wakeup; ignored");
        goto cleanup;
    }

    /* Clear state flags first */
    m_waiting = false;
    m_started = false;

    /* Then notify upper level logic */
    Q_EMIT timeout();

cleanup:
    if (!keep_going) {
        // Remember if timer was started
        bool was_started = m_started;

        // Terminate lost connection
        qWarning("lost heartbeat connection; reconnecting");
        disconnect();

        // Restore started flag
        m_started = was_started;

        // Start reconnect attempt
        connect();
    }
}

void
Heartbeat::stop()
{
    if (m_waiting && m_iphb_handle) {
        iphb_wait2(m_iphb_handle, 0, 0, 0, 0);
    }
    m_waiting = false;
    m_started = false;
}
