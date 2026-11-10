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

#ifndef NGF_CLIENT_H
#define NGF_CLIENT_H

#include <QObject>
#include <QMap>
#include <QString>
#include <QVariant>
#include "ngfclient_global.h"

namespace Ngf
{
    class ClientPrivate;

    /*!
     * \class Ngf::Client ngfclient.h NgfClient
     * \author Juho Hämäläinen <juho.hamalainen@jolla.com>
     * \version 0.7.0
     *
     * \brief Qt-based client library for NGF daemon (Non-Graphic Feedback)
     *
     * Ngf::Client is Qt-based client library for NGF daemon (Non-Graphic Feedback). Client can
     * be used to initiate non-graphical events, for example audio and vibra.
     *
     * NGF daemon defines set of actions for each event, for example "ringtone" event might be associated
     * with audio playback and vibra sequence. NGF daemon communicates with profiled to stay in sync
     * with the system sounds and volume levels settings. NGF daemon then uses for example PulseAudio
     * Stream Restore module to store volume levels and GStreamer to play audio streams.
     *
     * NGF::Client is introduced to allow simple use of NGF daemon without the need to know communication
     * details between daemon and client.
     *
     * \section LICENSE
     *
     * NgfClient - Qt Non-Graphic Feedback daemon client library
     *
     * Copyright (C) 2012-2021 Jolla Ltd.
     * Contact: juho.hamalainen@jolla.com
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
     *
     * \section Example
     *      \code
     *      #include <NgfClient>
     *
     *      // Create new client instance
     *      Ngf::Client *client = new Ngf::Client(this);
     *
     *      // Connect connection status signal
     *      QObject::connect(client, SIGNAL(connectionStatus(bool)), this, SLOT(connection(bool)));
     *
     *      // Connect status signals
     *      QObject::connect(client, SIGNAL(eventCompleted(quint32)), this, SLOT(completed(quint32)));
     *      QObject::connect(client, SIGNAL(eventFailed(quint32)), this, SLOT(failed(quint32)));
     *      QObject::connect(client, SIGNAL(eventPlaying(quint32)), this, SLOT(playing(quint32)));
     *
     *      // Connect to NGF daemon and after connection is open start event
     *      if (client->connect()) {
     *
     *          // Define properties for event
     *          QMap<QString, QVariant> properties;
     *          properties.insert("media.audio", true);
     *          properties.insert("file", "my-ringtone.mp3");
     *
     *          // Initiate event playback and store identifier. Remembering identifiers for events
     *          // is not usually important, since events can be stopped using their name as well.
     *          quint32 event_id = client->play("ringtone", properties);
     *
     *          // Somewhere else we want to stop ringtone playback
     *          client->stop("ringtone");
     *      }
     *      \endcode
     *
     */
    class NGFCLIENT_EXPORT Client : public QObject
    {

        Q_OBJECT

    public:
        /*!
         * Constructs new client instance.
         *
         * \param parent Parent object of the new instance.
         */
        Client(QObject *parent = 0);
        virtual ~Client();

        /*!
         * Connect to NGF daemon.
         *
         * Connection changes are forwarded using signal connectionStatus(bool), when
         * connection to NGF daemon is disconnected event playing or modifying functions
         * won't do anything.
         * If NGF daemon connection is severed after connect() is called, NGF Client makes
         * sure to reconnect to NGF daemon when it reappears.
         *
         * \return True if connection to NGF daemon was successful.
         */
        virtual bool connect();

        /*!
         * Get connection status to NGF daemon.
         *
         * \return True if connected to NGF daemon.
         */
        virtual bool isConnected();

        /*!
         * Disconnect from NGF daemon.
         *
         * There is no need to call disconnect() specially when discarding NGF Client,
         * disconnect() is called when object is destroyed anyway.
         */
        virtual void disconnect();

        /*!
         * Play event.
         *
         * When event is created and play returns true for successful event creation, it still
         * doesn't guarantee that event will be successfully started. User needs to watch for
         * event signals for determining whether event is really started.
         *
         * \param event String name of wanted event.
         * \return 0 if no connection to NGF daemon or identifier of new event on success.
         */
        virtual quint32 play(const QString &event);

        /*!
         * Play event.
         *
         * \param event String name of wanted event.
         * \param properties Extra properties for new event in key:value pairs.
         * \return 0 if no connection to NGF daemon or identifier of new event on success.
         */
        virtual quint32 play(const QString &event, const QMap<QString, QVariant> &properties);

        /*!
         * Pause running event by id.
         *
         * \param event_id Identifier of event that is going to be paused.
         * \return False if no connection to NGF daemon.
         */
        virtual bool pause(quint32 event_id);

        /*!
         * Pause running events by event name.
         *
         * Pause all running events with given name.
         *
         * \param event Event name.
         * \return False if no connection to NGF daemon.
         */
        virtual bool pause(const QString &event);

        /*!
         * Resume paused event by id.
         *
         * \param event_id Identifier of paused event that is going to be resumed.
         * \return False if no connection to NGF daemon.
         */
        virtual bool resume(quint32 event_id);

        /*!
         * Resume paused events by event name.
         *
         * Resume all paused events with given name.
         *
         * \param event Event name.
         * \return False if no connection to NGF daemon.
         */
        virtual bool resume(const QString &event);

        /*!
         * Stop running or paused event by id.
         *
         * \param event_id Identifier of running or paused event that is going to be stopped.
         * \return False if no connection to NGF daemon.
         */
        virtual bool stop(quint32 event_id);

        /*!
         * Stop running or paused events by event name.
         *
         * Stop all running or paused events with given name.
         *
         * \param event Event name.
         * \return False if no connection to NGF daemon.
         */
        virtual bool stop(const QString &event);

    signals:

        /*!
         * Signal emitted when connection status to NGF daemon changes.
         *
         * \param connected Connection status to NGF daemon.
         */
        void connectionStatus(bool connected);

        /*!
         * Signal emitted when event playing failed.
         *
         * \param event_id Event identifier number.
         */
        void eventFailed(quint32 event_id);

        /*!
         * Signal emitted when event playing is finished or stopped.
         *
         * \param event_id Event identifier number.
         */
        void eventCompleted(quint32 event_id);

        /*!
         * Signal emitted when event starts playing. This is also emitted when paused event is resumed.
         *
         * \param event_id Event identifier number.
         */
        void eventPlaying(quint32 event_id);

        /*!
         * Signal emitted when event is paused.
         *
         * \param event_id Event identifier number.
         */
        void eventPaused(quint32 event_id);

    private:
        Q_DISABLE_COPY(Client)
        Q_DECLARE_PRIVATE(Client)
        ClientPrivate* const d_ptr;
    };

}

#endif
