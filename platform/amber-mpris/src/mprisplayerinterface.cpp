// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 *
 * Copyright (C) 2015-2023 Jolla Ltd.
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

#include <QLoggingCategory>
#include "mprisclient_p.h"
#include "mpris.h"

namespace {
    Q_LOGGING_CATEGORY(lcPlayerIface, "org.amber.mpris.player.iface", QtWarningMsg)
}

using namespace Amber;


/*
 * Implementation of interface class MprisPlayerInterface
 */

MprisPlayerInterface::MprisPlayerInterface(const QString &service, const QString &path, const QDBusConnection &connection, QObject *parent)
    : DBusExtendedAbstractInterface(service, path, staticInterfaceName(), connection, parent)
    , m_canControl(false)
    , m_canGoNext(false)
    , m_canGoPrevious(false)
    , m_canPause(false)
    , m_canPlay(false)
    , m_canSeek(false)
    , m_hasShuffle(false)
    , m_hasLoopStatus(false)
    , m_loopStatus(Mpris::LoopNone)
    , m_maximumRate(1)
    , m_minimumRate(1)
    , m_playbackStatus(Mpris::Stopped)
    , m_position(0)
    , m_rate(1)
    , m_shuffle(false)
    , m_volume(0)
{
    connect(this, SIGNAL(propertyChanged(QString, QVariant)), this, SLOT(onPropertyChanged(QString, QVariant)));
}

MprisPlayerInterface::~MprisPlayerInterface()
{
}

void MprisPlayerInterface::onPropertyChanged(const QString &propertyName, const QVariant &value)
{
    if (propertyName == QStringLiteral("CanControl")) {
        bool canControl = value.toBool();
        if (m_canControl != canControl) {
            m_canControl = canControl;
            Q_EMIT canControlChanged(m_canControl);
        }
    } else if (propertyName == QStringLiteral("CanGoNext")) {
        bool canGoNext = value.toBool();
        if (m_canGoNext != canGoNext) {
            m_canGoNext = canGoNext;
            Q_EMIT canGoNextChanged(m_canGoNext);
        }
    } else if (propertyName == QStringLiteral("CanGoPrevious")) {
        bool canGoPrevious = value.toBool();
        if (m_canGoPrevious != canGoPrevious) {
            m_canGoPrevious = canGoPrevious;
            Q_EMIT canGoPreviousChanged(m_canGoPrevious);
        }
    } else if (propertyName == QStringLiteral("CanPause")) {
        bool canPause = value.toBool();
        if (m_canPause != canPause) {
            m_canPause = canPause;
            Q_EMIT canPauseChanged(m_canPause);
        }
    } else if (propertyName == QStringLiteral("CanPlay")) {
        bool canPlay = value.toBool();
        if (m_canPlay != canPlay) {
            m_canPlay = canPlay;
            Q_EMIT canPlayChanged(m_canPlay);
        }
    } else if (propertyName == QStringLiteral("CanSeek")) {
        bool canSeek = value.toBool();
        if (m_canSeek != canSeek) {
            m_canSeek = canSeek;
            Q_EMIT canSeekChanged(m_canSeek);
        }
    } else if (propertyName == QStringLiteral("LoopStatus")) {
        if (!m_hasLoopStatus) {
            m_hasLoopStatus = true;
            Q_EMIT hasLoopStatusChanged(true);
        }
        Mpris::LoopStatus loopStatus = MprisPrivate::stringToLoopStatus(value.toString());
        if (m_loopStatus != loopStatus) {
            m_loopStatus = loopStatus;
            Q_EMIT loopStatusChanged(MprisPrivate::loopStatusToString(m_loopStatus));
        }
    } else if (propertyName == QStringLiteral("MaximumRate")) {
        bool maximumRate = value.toDouble();
        if (m_maximumRate != maximumRate) {
            m_maximumRate = maximumRate;
            Q_EMIT maximumRateChanged(m_maximumRate);
        }
    } else if (propertyName == QStringLiteral("Metadata")) {
        QVariantMap metadata = value.toMap();
        if (m_metadata != metadata) {
            m_metadata = metadata;
            Q_EMIT metadataChanged(m_metadata);
        }
    } else if (propertyName == QStringLiteral("MinimumRate")) {
        double minimumRate = value.toDouble();
        if (m_minimumRate != minimumRate) {
            m_minimumRate = minimumRate;
            Q_EMIT minimumRateChanged(m_minimumRate);
        }
    } else if (propertyName == QStringLiteral("PlaybackStatus")) {
        Mpris::PlaybackStatus playbackStatus = MprisPrivate::stringToPlaybackStatus(value.toString());
        if (m_playbackStatus != playbackStatus) {
            m_playbackStatus = playbackStatus;
            Q_EMIT playbackStatusChanged(MprisPrivate::playbackToString(m_playbackStatus));
        }
    } else if (propertyName == QStringLiteral("Position")) {
        qlonglong position = value.toLongLong();
        if (m_position != position) {
            m_position = position;
            Q_EMIT positionChanged(m_position);
        }
    } else if (propertyName == QStringLiteral("Rate")) {
        double rate = value.toDouble();
        if (m_rate != rate) {
            m_rate = rate;
            Q_EMIT rateChanged(m_rate);
        }
    } else if (propertyName == QStringLiteral("Shuffle")) {
        if (!m_hasShuffle) {
            m_hasShuffle = true;
            Q_EMIT hasShuffleChanged(true);
        }
        bool shuffle = value.toBool();
        if (m_shuffle != shuffle) {
            m_shuffle = shuffle;
            Q_EMIT shuffleChanged(m_shuffle);
        }
    } else if (propertyName == QStringLiteral("Volume")) {
        double volume = value.toDouble();
        if (m_volume != volume) {
            m_volume = volume;
            Q_EMIT volumeChanged(m_volume);
        }
    } else {
        qCWarning(lcPlayerIface) << Q_FUNC_INFO
                                 << "Received PropertyChanged signal from unknown property: "
                                 << propertyName;
    }
}

