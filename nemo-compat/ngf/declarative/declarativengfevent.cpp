// SPDX-FileCopyrightText: 2013-2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/* Copyright (C) 2013-2021 Jolla Ltd.
 *
 * Contact: Juho Hämäläinen <juho.hamalainen@jolla.com>
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

#include "declarativengfevent.h"
#include <NgfClient>
#include <QMap>

/*!
   \qmlclass NonGraphicalFeedback DeclarativeNgfEvent
   \brief Playback of non-graphical feedback events

   NonGraphicalFeedback allows playback of system-defined events via the ngf
   daemon, such as notification sounds and effects.

   An event's actions are defined by a string which is mapped to configuration
   files installed on the system. Examples include "ringtone", "chat", or "battery_low".

   \qml
   NonGraphicalFeedback {
       id: ringtone
       event: "voip_ringtone"

       Connections {
           target: phone
           onIncomingCall: ringtone.play()
           onCallAnswered: ringtone.stop()
       }

   }
   \endqml
 */

/*!
   \qmlproperty string event

   Set the NGF event name. Events are defined in system-installed configuration files
   with a short name like "ringtone" or "battery_low".

   If the event is changed while playing, playback will be restarted
   automatically with the new event.
 */

/*!
   \qmlproperty EventStatus status

   Current status of playback. This property is updated asynchronously after
   requests to play, pause, or stop the event.
 */

static QSharedPointer<Ngf::Client> clientInstance()
{
    static QWeakPointer<Ngf::Client> client;

    QSharedPointer<Ngf::Client> re = client.toStrongRef();
    if (re.isNull()) {
        re = QSharedPointer<Ngf::Client>(new Ngf::Client);
        client = re.toWeakRef();
    }

    return re;
}

DeclarativeNgfEvent::DeclarativeNgfEvent(QObject *parent)
    : QObject(parent)
    , client(clientInstance())
    , m_status(Stopped)
    , m_eventId(0)
    , m_autostart(false)
    , m_properties()
{
    connect(client.data(), SIGNAL(connectionStatus(bool)), SLOT(connectionStatusChanged(bool)));
    connect(client.data(), SIGNAL(eventFailed(quint32)), SLOT(eventFailed(quint32)));
    connect(client.data(), SIGNAL(eventCompleted(quint32)), SLOT(eventCompleted(quint32)));
    connect(client.data(), SIGNAL(eventPlaying(quint32)), SLOT(eventPlaying(quint32)));
    connect(client.data(), SIGNAL(eventPaused(quint32)), SLOT(eventPaused(quint32)));
}

DeclarativeNgfEvent::~DeclarativeNgfEvent()
{
    stop();
}

void DeclarativeNgfEvent::setEvent(const QString &event)
{
    if (m_event == event)
        return;

    if (m_eventId) {
        stop();
        m_autostart = true;
    }

    m_event = event;

    emit eventChanged();
    if (m_autostart)
        play();
}

/*!
   \qmlmethod void NonGraphicalFeedback::play()

   Begins playing the defined event. If already playing, playback will be
   restarted from the beginning.

   Actual playback happens asynchronously. The \c status property will change
   when playback begins and ends, or in case of failure.
 */
void DeclarativeNgfEvent::play()
{
    if (!isConnected())
        client->connect();

    m_autostart = true;

    if (m_eventId)
        stop();

    if (!m_event.isEmpty() && isConnected()) {
        if (m_properties.count() > 0) {
            QMap<QString, QVariant> prop;

            for (int i = 0; i < m_properties.count(); ++i) {
                DeclarativeNgfEventProperty *property = m_properties.at(i);
                QVariant value = property->value();
                QMetaType::Type t = static_cast<QMetaType::Type>(value.type());
                // NGF only allows boolean, integer, or string types for property values.
                if (t == QMetaType::Bool || t == QMetaType::Int || t == QMetaType::QString)
                    prop.insert(property->name(), value);
            }
            m_eventId = client->play(m_event, prop);
        } else {
            m_eventId = client->play(m_event);
        }
    }
}

/*!
   \qmlmethod void NonGraphicalFeedback::pause()

   Pause the currently playing event. Playback can be resumed with \a resume()
 */
void DeclarativeNgfEvent::pause()
{
    if (!m_eventId)
        return;

    client->pause(m_eventId);
}

/*!
   \qmlmethod void NonGraphicalFeedback::resume()

   Resume a paused event.
 */
void DeclarativeNgfEvent::resume()
{
    if (!m_eventId)
        return;

    client->resume(m_eventId);
}

/*!
   \qmlmethod void NonGraphicalFeedback::stop()

   Stop playback of the event.
 */
void DeclarativeNgfEvent::stop()
{
    m_autostart = false;

    if (!m_eventId)
        return;

    client->stop(m_eventId);
    m_eventId = 0;
    m_status = Stopped;
    emit statusChanged();
}

/*!
   \qmlproperty bool connected

   Indicates if the NGF daemon is connected and active. The connection
   will be established automatically when needed.
 */
bool DeclarativeNgfEvent::isConnected() const
{
    return client->isConnected();
}

void DeclarativeNgfEvent::connectionStatusChanged(bool connected)
{
    if (connected && m_autostart) {
        m_autostart = false;
        play();
    }

    emit connectedChanged();
}

void DeclarativeNgfEvent::eventFailed(quint32 id)
{
    if (id != m_eventId)
        return;

    m_eventId = 0;
    m_status = Failed;
    emit statusChanged();
}

void DeclarativeNgfEvent::eventCompleted(quint32 id)
{
    if (id != m_eventId)
        return;

    m_eventId = 0;
    m_status = Stopped;
    emit statusChanged();
}

void DeclarativeNgfEvent::eventPlaying(quint32 id)
{
    if (id != m_eventId)
        return;

    m_status = Playing;
    m_autostart = false;
    emit statusChanged();
}

void DeclarativeNgfEvent::eventPaused(quint32 id)
{
    if (id != m_eventId)
        return;

    m_status = Paused;
    emit statusChanged();
}

QQmlListProperty<DeclarativeNgfEventProperty> DeclarativeNgfEvent::properties()
{
    return QQmlListProperty<DeclarativeNgfEventProperty>(this, this,
             &DeclarativeNgfEvent::appendProperty,
             &DeclarativeNgfEvent::propertyCount,
             &DeclarativeNgfEvent::property,
             &DeclarativeNgfEvent::clearProperties);
}

void DeclarativeNgfEvent::appendProperty(DeclarativeNgfEventProperty* property)
{
    m_properties.append(property);
}

int DeclarativeNgfEvent::propertyCount() const
{
    return m_properties.count();
}

DeclarativeNgfEventProperty* DeclarativeNgfEvent::property(int index) const
{
    return m_properties.at(index);
}

void DeclarativeNgfEvent::clearProperties()
{
    m_properties.clear();
}

// QQmlListProperty

void DeclarativeNgfEvent::appendProperty(QQmlListProperty<DeclarativeNgfEventProperty> *list, DeclarativeNgfEventProperty *property)
{
    reinterpret_cast< DeclarativeNgfEvent* >(list->data)->appendProperty(property);
}
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
int DeclarativeNgfEvent::propertyCount(QQmlListProperty<DeclarativeNgfEventProperty>* list)
#else
qsizetype DeclarativeNgfEvent::propertyCount(QQmlListProperty<DeclarativeNgfEventProperty>* list)
#endif
{
    return reinterpret_cast< DeclarativeNgfEvent* >(list->data)->propertyCount();
}
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
DeclarativeNgfEventProperty* DeclarativeNgfEvent::property(QQmlListProperty<DeclarativeNgfEventProperty> *list, int i)
#else
DeclarativeNgfEventProperty* DeclarativeNgfEvent::property(QQmlListProperty<DeclarativeNgfEventProperty> *list, qsizetype i)
#endif
{
    return reinterpret_cast< DeclarativeNgfEvent* >(list->data)->property(i);
}

void DeclarativeNgfEvent::clearProperties(QQmlListProperty<DeclarativeNgfEventProperty> *list)
{
    reinterpret_cast< DeclarativeNgfEvent* >(list->data)->clearProperties();
}
