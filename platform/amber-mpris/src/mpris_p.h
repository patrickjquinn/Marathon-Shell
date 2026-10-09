// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
// -*- c++ -*-

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


#ifndef MPRIS_P_H
#define MPRIS_P_H

#include <mpris.h>

#include <QObject>
#include <QString>

namespace Amber {
class MprisPrivate
{
public:
    static Mpris::LoopStatus stringToLoopStatus(const QString &value, bool *ok);
    static QString loopStatusToString(Mpris::LoopStatus value);
    static Mpris::PlaybackStatus stringToPlaybackStatus(const QString &value, bool *ok);
    static QString playbackToString(Mpris::PlaybackStatus value);

    static inline Mpris::LoopStatus stringToLoopStatus(QString value)
    { return stringToLoopStatus(value, nullptr); }
    static inline Mpris::PlaybackStatus stringToPlaybackStatus(QString value)
    { return stringToPlaybackStatus(value, nullptr); }
};
}

#endif /* MPRIS_P_H */
