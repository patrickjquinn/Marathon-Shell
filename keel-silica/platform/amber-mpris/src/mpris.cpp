// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*!
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

#include "mpris_p.h"
#include "mpris.h"

using namespace Amber;

Mpris::Mpris() {}

Mpris::LoopStatus MprisPrivate::stringToLoopStatus(const QString &value, bool *ok)
{
    Mpris::LoopStatus enumVal = Mpris::LoopNone;
    bool found = true;

    if (value == QLatin1String("None")) {
        enumVal = Mpris::LoopNone;
    } else if (value == QLatin1String("Track")) {
        enumVal = Mpris::LoopTrack;
    } else if (value == QLatin1String("Playlist")) {
        enumVal = Mpris::LoopPlaylist;
    } else {
        found = false;
    }

    if (ok) {
        *ok = found;
    }

    return enumVal;
}

QString MprisPrivate::loopStatusToString(Mpris::LoopStatus value)
{
    switch (value) {
    case Mpris::LoopNone:
        return QStringLiteral("None");
    case Mpris::LoopTrack:
        return QStringLiteral("Track");
    case Mpris::LoopPlaylist:
        return QStringLiteral("Playlist");
    }
    return QString();
}

Mpris::PlaybackStatus MprisPrivate::stringToPlaybackStatus(const QString &value, bool *ok)
{
    Mpris::PlaybackStatus enumVal = Mpris::Stopped;
    bool found = true;

    if (value == QLatin1String("Stopped")) {
        enumVal = Mpris::Stopped;
    } else if (value == QLatin1String("Playing")) {
        enumVal = Mpris::Playing;
    } else if (value == QLatin1String("Paused")) {
        enumVal = Mpris::Paused;
    } else {
        found = false;
    }

    if (ok) {
        *ok = found;
    }

    return enumVal;
}

QString MprisPrivate::playbackToString(Mpris::PlaybackStatus value)
{
    switch (value) {
    case Mpris::Stopped:
        return QStringLiteral("Stopped");
    case Mpris::Playing:
        return QStringLiteral("Playing");
    case Mpris::Paused:
        return QStringLiteral("Paused");
    }
    return QString();
}
