// SPDX-FileCopyrightText: 2021-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*!
 *
 * Copyright (C) 2021-2023 Jolla Ltd.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef MPRISPLAYER_P_H
#define MPRISPLAYER_P_H

#include <QObject>
#include <QVariantMap>
#include <QDBusContext>
#include "mprismetadata.h"
#include "mprisplayeradaptor_p.h"
#include "mprisserviceadaptor_p.h"
#include "mprispropertiesadaptor_p.h"
#include "mprisintrospectableadaptor_p.h"
#include "mprisplayer.h"

namespace Amber {
class MprisPlayerPrivate : public QObject, public QDBusContext
{
    Q_OBJECT

public:
    MprisPlayerPrivate(MprisPlayer *parent);
    ~MprisPlayerPrivate();

    void quit();
    void raise();

    MprisPlayer *q_ptr;
    QDBusConnection *m_connection;
    MprisServiceAdaptor m_serviceAdaptor;
    MprisPlayerAdaptor m_playerAdaptor;
    MprisPropertiesAdaptor m_playerPropertiesAdaptor;
    MprisIntrospectableAdaptor m_playerIntrospectableAdaptor;

    QString m_serviceName;
    bool m_canQuit;
    bool m_canRaise;
    bool m_canSetFullscreen;
    QString m_desktopEntry;
    bool m_fullscreen;
    bool m_hasTrackList;
    QString m_identity;
    QStringList m_supportedUriSchemes;
    QStringList m_supportedMimeTypes;
    QMap<QString, QPair<QVariantMap, QSet<QString>>> m_changedProperties;
    QTimer m_changedDelay;

    MprisMetaData m_metaData;
    bool m_canControl;
    bool m_canGoNext;
    bool m_canGoPrevious;
    bool m_canPause;
    bool m_canPlay;
    bool m_canSeek;
    bool m_hasShuffle;
    bool m_hasLoopStatus;
    Mpris::LoopStatus m_loopStatus;
    double m_maximumRate;
    double m_minimumRate;
    Mpris::PlaybackStatus m_playbackStatus;
    qlonglong m_position;
    double m_rate;
    bool m_shuffle;
    double m_volume;
    bool m_inPositionRequested;

public Q_SLOTS:
    // Player Adaptor
    qlonglong position() const;
    void setLoopStatus(const QString &value);
    QString loopStatus() const;
    QString playbackStatus() const;
    QVariantMap metaData() const;

    void setVolume(double volume);
    void setRate(double rate);
    void setShuffle(bool shuffle);

    // Service Adaptor
    bool canQuit() const;
    bool canRaise() const;
    bool canSetFullscreen() const;
    QString desktopEntry() const;
    bool fullscreen() const;
    bool hasTrackList() const;
    QString identity() const;
    QStringList supportedMimeTypes() const;
    QStringList supportedUriSchemes() const;

    void setFullscreen(bool value);

public:
    void Next();
    void OpenUri(const QString &Uri);
    void Pause();
    void Play();
    void PlayPause();
    void Previous();
    void Seek(qlonglong Offset);
    void SetPosition(const QDBusObjectPath &TrackId, qlonglong position);
    void Stop();

    void propertyChanged(const QString &iface, const QString &name, const QVariant &value);

private Q_SLOTS:
    void emitPropertiesChanged();
};
}

#endif
