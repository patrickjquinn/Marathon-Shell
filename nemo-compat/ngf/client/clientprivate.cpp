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
#include <QTimer>
#include <QtDBus>
#include <QList>
#include <QtAlgorithms>
#include "clientprivate.h"

namespace Ngf
{
    enum NgfStatusId
    {
        StatusEventFailed       = 0,
        StatusEventCompleted    = 1,
        StatusEventPlaying      = 2,
        StatusEventPaused       = 3,
    };

    const static QString NgfDestination     = "com.nokia.NonGraphicFeedback1.Backend";
    const static QString NgfPath            = "/com/nokia/NonGraphicFeedback1";
    const static QString NgfInterface       = "com.nokia.NonGraphicFeedback1";
    const static QString MethodPlay         = "Play";
    const static QString MethodStop         = "Stop";
    const static QString MethodPause        = "Pause";
    const static QString SignalStatus       = "Status";

    class Event
    {
    public:
        Event(const QString &_name, quint32 _clientEventId, QDBusPendingCallWatcher *_watcher)
            : name(_name), clientEventId(_clientEventId), serverEventId(0),
              wantedState(ClientPrivate::StatePlaying),
              activeState(ClientPrivate::StateNew),
              pendingState(ClientPrivate::StateNew),
              watcher(_watcher)
        {}
        ~Event() {}

        QString name;
        quint32 clientEventId;
        quint32 serverEventId;
        ClientPrivate::EventState wantedState;
        ClientPrivate::EventState activeState;
        ClientPrivate::EventState pendingState;
        QDBusPendingCallWatcher *watcher;
    };
}

QDBusMessage createMethodCall(const QString &method)
{
    return QDBusMessage::createMethodCall(Ngf::NgfDestination, Ngf::NgfPath, Ngf::NgfInterface, method);
}

Ngf::ClientPrivate::ClientPrivate(Client *parent)
    : QObject(parent),
      q_ptr(parent),
      m_log("ngf.client"),
      m_serviceWatcher(0),
      m_connected(false),
      m_clientEventId(0)
{
    m_log.setEnabled(QtDebugMsg, false);
}

Ngf::ClientPrivate::~ClientPrivate()
{
    disconnect();
    removeAllEvents();
}

bool Ngf::ClientPrivate::connect()
{
    if (!m_serviceWatcher) {
        m_serviceWatcher = new QDBusServiceWatcher(NgfDestination,
                                                   QDBusConnection::systemBus(),
                                                   QDBusServiceWatcher::WatchForUnregistration,
                                                   this);

        QObject::connect(m_serviceWatcher, SIGNAL(serviceUnregistered(const QString&)),
                         this, SLOT(serviceUnregistered(const QString&)));

        QDBusConnection::systemBus().connect(QString(), NgfPath, NgfInterface, SignalStatus,
                                             this, SLOT(setEventState(quint32,quint32)));
    }

    // connected doesn't mean much really, mostly just backward compatibility
    changeConnected(true);
    return m_connected;
}

void Ngf::ClientPrivate::disconnect()
{
    changeConnected(false);
}

void Ngf::ClientPrivate::serviceUnregistered(const QString &service)
{
    Q_UNUSED(service);

    // All currently active events are invalid, so clear event list
    removeAllEvents();
}

bool Ngf::ClientPrivate::isConnected()
{
    return m_connected;
}

void Ngf::ClientPrivate::setEventState(quint32 serverEventId, quint32 state)
{
    Event *event = 0;

    // Look through all ongoing events and match serverEventId to internal clientEventId.
    // In case of failing or completing event, we'll also remove that event from event list later.
    for (int i = 0; i < m_events.size(); ++i) {
        Event *e = m_events.at(i);
        if (e->serverEventId == serverEventId) {
            event = e;
            break;
        }
    }

    if (!event)
        return;

    qCDebug(m_log) << event->clientEventId << "server state" << state;

    switch (state) {
        case StatusEventFailed:
            event->activeState = StateStopped;
            emit q_ptr->eventFailed(event->clientEventId);
            break;

        case StatusEventCompleted:
            event->activeState = StateStopped;
            emit q_ptr->eventCompleted(event->clientEventId);
            break;

        case StatusEventPlaying:
            if (event->activeState != StatePlaying) {
                event->activeState = StatePlaying;
                emit q_ptr->eventPlaying(event->clientEventId);
            }
            break;

        case StatusEventPaused:
            event->activeState = StatePaused;
            emit q_ptr->eventPaused(event->clientEventId);
            break;

        default:
            // Undefined state received from NGFD, probably server
            // DBus API has changed and we are out of sync.
            qCWarning(m_log) << "Client received unknown event state id, likely NGFD API has changed. state:" << state;
            event->activeState = StateStopped;
            emit q_ptr->eventFailed(event->clientEventId);
            removeEvent(event);
            return;
    }

    if (state == StatusEventFailed || state == StatusEventCompleted) {
        removeEvent(event);
    } else if (event->pendingState != StateNew) {
        requestEventState(event, event->pendingState);
        event->pendingState = StateNew;
    }
}

quint32 Ngf::ClientPrivate::play(const QString &event)
{
    Proplist empty;

    return play(event, empty);
}

quint32 Ngf::ClientPrivate::play(const QString &event, const Proplist &properties)
{
    ++m_clientEventId;

    // Create asynchronic call to NGFD and connect pending call watcher to slot
    // playPendingReply where it is finally determined if event is really running
    // in the NGFD side.
    QDBusMessage play = createMethodCall(MethodPlay);
    play << event << properties;

    QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(play);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pending, 0);
    Event *e = new Event(event, m_clientEventId, watcher);
    m_events.push_back(e);

    QObject::connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher*)),
                     this, SLOT(playPendingReply(QDBusPendingCallWatcher*)));

    qCDebug(m_log) << e->clientEventId << "set state" << e->wantedState;

    return e->clientEventId;
}

void Ngf::ClientPrivate::playPendingReply(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<quint32> reply = *watcher;
    int i = 0;

    // Play -method reply should contain one argument of type uint32 containing
    // server side event id for started event.

    for (i = 0; i < m_events.size(); ++i) {
        Event *event = m_events.at(i);
        if (event->watcher == watcher) {
            if (reply.isError() || reply.count() != 1) {
                // Starting event failed for some reason, reason can hopefully be determined from
                // NGFD logs.
                quint32 clientEventId = event->clientEventId;
                removeEvent(event);
                qCDebug(m_log) << clientEventId << "play: operation failed";
                emit q_ptr->eventFailed(clientEventId);
            } else {
                event->serverEventId = reply.argumentAt<0>();
                event->watcher = 0;
                event->activeState = StatePlaying;
                qCDebug(m_log) << event->clientEventId << "play: server replied" << event->serverEventId;
                emit q_ptr->eventPlaying(event->clientEventId);

                if (event->pendingState != StateNew) {
                    qCDebug(m_log) << event->clientEventId
                                   << "wanted state" << event->pendingState
                                   << "differs from active state" << event->activeState;
                    requestEventState(event, event->pendingState);
                    event->pendingState = StateNew;
                }
            }
            break;
        }
    }

    watcher->deleteLater();
}

bool Ngf::ClientPrivate::pause(quint32 eventId)
{
    return changeState(eventId, StatePaused);
}

bool Ngf::ClientPrivate::pause(const QString &event)
{
    return changeState(event, StatePaused);
}

bool Ngf::ClientPrivate::resume(quint32 eventId)
{
    return changeState(eventId, StatePlaying);
}

bool Ngf::ClientPrivate::resume(const QString &event)
{
    return changeState(event, StatePlaying);
}

bool Ngf::ClientPrivate::stop(quint32 eventId)
{
    return changeState(eventId, StateStopped);
}

bool Ngf::ClientPrivate::stop(const QString &event)
{
    return changeState(event, StateStopped);
}

void Ngf::ClientPrivate::removeEvent(Event *event)
{
    if (m_events.removeOne(event))
        delete event;
    else
        qCWarning(m_log) << "Couldn't find event from event list.";
}

void Ngf::ClientPrivate::removeAllEvents()
{
    qDeleteAll(m_events);
    m_events.clear();
}

bool Ngf::ClientPrivate::changeState(quint32 clientEventId, EventState wantedState)
{
    for (int i = 0; i < m_events.size(); ++i) {
        Event *e = m_events.at(i);
        if (e->clientEventId == clientEventId) {
            requestEventState(e, wantedState);
            break;
        }
    }

    return true;
}

bool Ngf::ClientPrivate::changeState(const QString &clientEventName, EventState wantedState)
{
    for (int i = 0; i < m_events.size(); ++i) {
        Event *e = m_events.at(i);
        if (e->name == clientEventName) {
            requestEventState(e, wantedState);
            break;
        }
    }

    return true;
}

void Ngf::ClientPrivate::requestEventState(Event *event, EventState wantedState)
{
    if (event->wantedState == wantedState
            || event->activeState == StateStopped) {
        return;
    } else if (event->activeState == StateNew) {
        // can't make further requests before we have an id from play()
        event->pendingState = wantedState;
        return;
    }

    event->wantedState = wantedState;
    qCDebug(m_log) << event->clientEventId << "set state" << event->wantedState;

    switch (event->wantedState) {
    case StatePlaying: {
        QDBusMessage pause = createMethodCall(MethodPause);
        pause << event->serverEventId << QVariant(false);

        QDBusConnection::systemBus().asyncCall(pause);
        break;
    }
    case StatePaused: {
        QDBusMessage pause = createMethodCall(MethodPause);
        pause << event->serverEventId << QVariant(true);

        QDBusConnection::systemBus().asyncCall(pause);
        break;
    }
    case StateStopped: {
        QDBusMessage stop = createMethodCall(MethodStop);
        stop << event->serverEventId;

        QDBusConnection::systemBus().asyncCall(stop);
        break;
    }
    case StateNew:
        break;
    }
}

void Ngf::ClientPrivate::changeConnected(bool connected)
{
    if (m_connected != connected) {
        m_connected = connected;
        emit q_ptr->connectionStatus(m_connected);
    }
}
