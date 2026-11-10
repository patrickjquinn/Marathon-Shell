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

#ifndef NGFCLIENTDBUSPRIVATE_H
#define NGFCLIENTDBUSPRIVATE_H

#include <QObject>
#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QList>
#include <QLoggingCategory>
#include "ngfclient.h"

namespace Ngf
{
    class Event;

    typedef QMap<QString, QVariant> Proplist;

    class ClientPrivate : public QObject
    {
        Q_OBJECT

    public:
        ClientPrivate(Client *parent);
        virtual ~ClientPrivate();

        bool connect();
        bool isConnected();
        void disconnect();
        quint32 play(const QString &event);
        quint32 play(const QString &event, const Proplist &properties);
        bool pause(quint32 eventId);
        bool pause(const QString &event);
        bool resume(quint32 eventId);
        bool resume(const QString &event);
        bool stop(quint32 eventId);
        bool stop(const QString &event);

        enum EventState {
            StateNew,
            StatePlaying,
            StatePaused,
            StateStopped
        };

    private slots:
        void playPendingReply(QDBusPendingCallWatcher *watcher);
        void setEventState(quint32 serverEventId, quint32 state);
        void serviceUnregistered(const QString &service);

    private:
        void requestEventState(Event *event, EventState wantedState);
        void removeEvent(Event *event);
        void removeAllEvents();
        bool changeState(quint32 clientEventId, EventState wantedState);
        bool changeState(const QString &clientEventName, EventState wantedState);
        void changeConnected(bool connected);

        Client * const q_ptr;
        Q_DECLARE_PUBLIC(Client)

        QLoggingCategory m_log;
        QDBusServiceWatcher *m_serviceWatcher;
        bool m_connected;
        quint32 m_clientEventId; // Internal counter for client event ids, incremented every time play is called.
        QList<Event*> m_events;
    };
}

#endif
