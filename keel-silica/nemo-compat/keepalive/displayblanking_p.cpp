// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
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

#include <QTimer>
#include "displayblanking_p.h"

#include <mce/dbus-names.h>
#include <mce/mode-names.h>

/* ========================================================================= *
 * class DisplayBlankingSingleton
 * ========================================================================= */

DisplayBlankingSingleton::DisplayBlankingSingleton()
    : m_renew_period(60 * 1000)
    , m_renew_timer(0)
    , m_preventAllowed(false)
    , m_displayStatus(DisplayBlanking::Unknown)
    , m_instanceRefCount(0)
{
    m_mce_req_iface = new ComNokiaMceRequestInterface(MCE_SERVICE,
                                                      MCE_REQUEST_PATH,
                                                      QDBusConnection::systemBus(),
                                                      this);

    m_mce_signal_iface = new ComNokiaMceSignalInterface(MCE_SERVICE,
                                                        MCE_SIGNAL_PATH,
                                                        QDBusConnection::systemBus(),
                                                        this);

    /* Track blank prevent allowed */
    {
        connect(m_mce_signal_iface, SIGNAL(display_blanking_pause_allowed_ind(bool)),
                this, SLOT(updatePreventMode(bool)));

        QDBusPendingReply<bool> reply = m_mce_req_iface->get_display_blanking_pause_allowed();
        QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher *)),
                SLOT(getPreventModeComplete(QDBusPendingCallWatcher *)));
    }

    /* Track display state */
    {
        connect(m_mce_signal_iface, SIGNAL(display_status_ind(const QString &)),
                this, SLOT(updateDisplayStatus(QString)));

        QDBusPendingReply<QString> reply = m_mce_req_iface->get_display_status();
        QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher *)),
                SLOT(getDisplayStatusComplete(QDBusPendingCallWatcher *)));
    }

}

DisplayBlanking::Status DisplayBlankingSingleton::displayStatus() const
{
    return m_displayStatus;
}

QTimer *DisplayBlankingSingleton::keepaliveTimer()
{
    if (!m_renew_timer) {
        m_renew_timer = new QTimer(this);
        connect(m_renew_timer, SIGNAL(timeout()), this, SLOT(renewKeepalive()));
    }
    return m_renew_timer;
}

void DisplayBlankingSingleton::startKeepalive()
{
    m_mce_req_iface->req_display_blanking_pause();
    keepaliveTimer()->setInterval(m_renew_period);
    keepaliveTimer()->start();
}

void DisplayBlankingSingleton::renewKeepalive()
{
    m_mce_req_iface->req_display_blanking_pause();
}

void DisplayBlankingSingleton::stopKeepalive()
{
    keepaliveTimer()->stop();
    m_mce_req_iface->req_display_cancel_blanking_pause();
}

void DisplayBlankingSingleton::evaluateKeepalive()
{
    bool have = keepaliveTimer()->isActive();
    bool want = m_preventAllowed && !m_preventingObjects.empty();

    if (have != want) {
        if (want)
            startKeepalive();
        else
            stopKeepalive();
    }
}

void DisplayBlankingSingleton::updatePreventMode(bool preventAllowed)
{
    if (m_preventAllowed != preventAllowed) {
        m_preventAllowed = preventAllowed;
        evaluateKeepalive();
    }
}

void DisplayBlankingSingleton::getPreventModeComplete(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<bool> reply = *call;
    if (!reply.isError()) {
        updatePreventMode(reply.value());
    }

    call->deleteLater();
}

void DisplayBlankingSingleton::updateDisplayStatus(const QString &status)
{
    DisplayBlanking::Status newStatus = DisplayBlanking::Unknown;

    if (status == MCE_DISPLAY_OFF_STRING) {
        newStatus = DisplayBlanking::Off;
    } else if (status == MCE_DISPLAY_ON_STRING) {
        newStatus = DisplayBlanking::On;
    } else if (status == MCE_DISPLAY_DIM_STRING) {
        newStatus = DisplayBlanking::Dimmed;
    }

    if (newStatus != m_displayStatus) {
        m_displayStatus = newStatus;
        Q_EMIT displayStatusChanged();
    }
}

void DisplayBlankingSingleton::getDisplayStatusComplete(QDBusPendingCallWatcher *call)
{
    QDBusPendingReply<QString> reply = *call;
    if (!reply.isError()) {
        updateDisplayStatus(reply.value());
    }

    call->deleteLater();
}

DisplayBlankingSingleton *DisplayBlankingSingleton::s_instance = nullptr;

DisplayBlankingSingleton *DisplayBlankingSingleton::instance()
{
    if (!s_instance) {
        s_instance = new DisplayBlankingSingleton();
    }

    ++s_instance->m_instanceRefCount;

    return s_instance;
}

void DisplayBlankingSingleton::releaseInstance()
{
    if (s_instance && s_instance == this) {
        if (s_instance->m_instanceRefCount > 0) {
            if (--s_instance->m_instanceRefCount == 0) {
                delete s_instance;
                s_instance = nullptr;
            }
        }
    }
}

void DisplayBlankingSingleton::attachPreventingObject(DisplayBlankingPrivate *object)
{
    m_preventingObjects.insert(object);
    evaluateKeepalive();
}

void DisplayBlankingSingleton::detachPreventingObject(DisplayBlankingPrivate *object)
{
    m_preventingObjects.remove(object);
    evaluateKeepalive();
}

/* ========================================================================= *
 * DisplayBlankingPrivate
 * ========================================================================= */

DisplayBlankingPrivate::DisplayBlankingPrivate(DisplayBlanking *parent)
    : m_singleton(nullptr)
    , m_parent(parent)
    , m_preventBlanking(false)
{
    m_singleton = DisplayBlankingSingleton::instance();

    QObject::connect(m_singleton, &DisplayBlankingSingleton::displayStatusChanged,
                     parent, &DisplayBlanking::statusChanged);
}

DisplayBlankingPrivate::~DisplayBlankingPrivate()
{
    setPreventBlanking(false);

    if (m_singleton) {
        m_singleton->releaseInstance();
        m_singleton = nullptr;
    }
}

DisplayBlanking::Status DisplayBlankingPrivate::displayStatus() const
{
    return m_singleton->displayStatus();
}

bool DisplayBlankingPrivate::preventBlanking() const
{
    return m_preventBlanking;
}

void DisplayBlankingPrivate::setPreventBlanking(bool preventBlanking)
{
    if (m_preventBlanking != preventBlanking) {
        if ((m_preventBlanking = preventBlanking)) {
            m_singleton->attachPreventingObject(this);
        } else {
            m_singleton->detachPreventingObject(this);
        }
        Q_EMIT m_parent->preventBlankingChanged();
    }
}
