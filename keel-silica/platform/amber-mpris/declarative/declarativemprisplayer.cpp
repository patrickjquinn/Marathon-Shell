// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 *
 * Copyright (C) 2021 Jolla Ltd.
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

#include <QVariant>
#include <QCoreApplication>
#include "declarativemprisplayer_p.h"

using namespace Amber;

/*!
    \qmltype MprisPlayer
    \inqmlmodule Amber.Mpris
    \brief Allows a media player to be remote controlled

    Enables the possibility to receive remote control commands over MPRIS
    interface.

    All property changes are slightly delayed and bundled together for
    performance reasons.

    The serviceName property must be set for any functionality.
*/

/*!
    \qmlproperty string MprisPlayer::serviceName
    \brief Sets the name under which the player is registered

    This property must be set to receive or publish anything. Must
    be a valid D-Bus service name part.

    The actual name on D-Bus will be prepended with "org.mpris.MediaPlayer2.",
    and appended with the current process id.
*/

/*!
    \qmlproperty bool MprisPlayer::canQuit
    \brief Sets indication whether the player can be told to quit remotely

    When set to true, a remote controller can emit the quitRequested signal.
    Defaults to false.

    \sa MprisPlayer::quitRequested
*/

/*!
    \qmlproperty bool MprisPlayer::canRaise
    \brief Sets indication whether the player can be told to present itself

    When set to true, a remote controller can emit the raiseRequested signal.
    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canSetFullscreen
    \brief Sets indication whether the player can be told to go full screen

    When set to true, a remote controller can emit the fullScreenRequested signal.
    Defaults to false.
*/

/*!
    \qmlproperty string MprisPlayer::desktopEntry
    \brief Sets the name of the desktop file that identifies the player

    Can be set to the base name of a desktop entry of the player, allowing
    remote controllers to gain information about the player
    (icon, localized name).

    Empty by default.
*/

/*!
    \qmlproperty bool MprisPlayer::fullscreen
    \brief Indicates whether the player is in fullscreen mode

    Should be set to true, if the player is currently in fullscreen mode.
    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::hasTrackList
    \brief Indicates whether the player has a track list
    \internal

    Currently unsupported. Always false.
*/

/*!
    \qmlproperty string MprisPlayer::identity
    \brief Indicates the name of the player

    Should be set to a human-readable name of the player, normally should
    match a name found in desktopEntry.

    Empty by default.
*/

/*!
    \qmlproperty list<string> MprisPlayer::supportedUriSchemes
    \brief Indicates the procotols the player supports

    Should be set to a list of protocol schemes the player supports.
    Common examples are "file" and "http". Note, this is not enforced,
    and remote controllers can still request opening uris with other schemes.

    Empty by default.
*/

/*!
    \qmlproperty list<string> MprisPlayer::supportedMimeTypes
    \brief Indicates the mime types the player supports

    Should be set to a list of mime types the player is able to play.
    Common examples are "audio/mpeg" and "application/ogg". Note, this
    is not enforced, and remote controllers can still request opening
    uris of other types.

    Empty by default.
*/

/*!
    \qmlproperty bool MprisPlayer::canControl
    \brief Indicates whether the player can be controlled remotely

    Should be set to true if the player can receive any remote control
    commands.

    This value must remain constant during the lifetime of the
    player and the value can't be changed after the first controller
    has connected.

    In order to change the value, a new \l MprisPlayer should be
    instantiated.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canGoNext
    \brief Indicates whether the player can jump to next item

    Should be set to true if the player has a next item to play, normally
    if there are more items on the playlist, or repeat is enabled.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canGoPrevious
    \brief Indicates whether the player can jump the previous item

    Should be set to true if the player has a next item to play, normally
    if there are previous items on the playlist, or repeat is enabled.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canPause
    \brief Indicates whether the player can be paused

    Should be set to true if the player is in a state that it can be paused.
    If set to true, remote controllers can emit the pauseRequested and
    playPauseRequested signals.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canPlay
    \brief Indicates whether the player can be started

    Should be set to true if the player is in a state that it can be started
    or resumed. If set to true, remote controllers can emit the playRequested
    and playPauseRequested signals.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::canSeek
    \brief Indicates whether the player can seek in the current media

    Should be set to true if the current media in the player can be seeked.
    If set to true, remote controllers can emit the seekRequested and
    setPositionRequested signals.

    Defaults to false.
*/

/*!
    \qmlproperty bool MprisPlayer::hasShuffle
    \brief Indicates whether the player has shuffle property

    Should be set to true if shuffle property of the play queue can be
    accessed. If set to true, remote controllers can read and set shuffle
    property.

    This value must remain constant during the lifetime of the
    player and the value can't be changed after the first controller
    has connected.

    In order to change the value, a new \l MprisPlayer should be
    instantiated.

    Defaults to true.
*/

/*!
    \qmlproperty bool MprisPlayer::hasLoopStatus
    \brief Indicates whether the player has loopStatus property

    Should be set to true if the loop status can be accessed. If set to true,
    remote controllers can read and set loopStatus property.

    This value must remain constant during the lifetime of the
    player and the value can't be changed after the first controller
    has connected.

    In order to change the value, a new \l MprisPlayer should be
    instantiated.

    Defaults to true.
*/

/*!
    \qmlproperty int MprisPlayer::loopStatus
    \brief Indicates the current looping mode of the player

    Should be set to either Mpris.LoopNone, Mpris.LoopTrack or Mpris.LoopTrackList
    to indicate the current looping mode of the player.

    Defaults to Mpris.LoopNone.
*/

/*!
    \qmlproperty double MprisPlayer::maximumRate
    \brief Indicates the maximum playback rate of the player

    Should be set to indicate the fastest playback speed the player
    can use.

    Defaults to 1.0.
*/

/*!
    \qmlproperty MprisMetaData MprisPlayer::metaData
    \brief An MprisMetaData object for the current media

    The properties of the returned object should be filled with details
    about the current media in the player.
*/

/*!
    \qmlproperty double MprisPlayer::minimumRate
    \brief Indicates the minimum playback rate of the player

    Should be set to indicate the slowest playback speed the player
    can use.

    Defaults to 1.0.
*/

/*!
    \qmlproperty Mpris::PlaybackStatus MprisPlayer::playbackStatus
    \brief Indicates the current status of the player

    Should be set to Mpris.Stopped, Mpris.Playing or Mpris.Paused to indicate
    the current state of the player.
*/

/*!
    \qmlsignal MprisPlayer::positionRequested()

    When emitted, indicates that a remote controller wants to
    read the position property, and it should be updated.
*/

/*!
    \qmlproperty int MprisPlayer::position
    \brief Indicates the position in current item in milliseconds

    Should be set to the current playback position in the current media, in
    milliseconds.

    For more accurate timing, this should be set in a positionRequested signal
    handler, property binding may lead to inaccurate time being reported.

    Defaults to 0.

    \sa MprisPlayer::positionRequested()
*/

/*!
    \qmlproperty double MprisPlayer::rate
    \brief Indicates the current playback rate of the player

    Should be set to a real number that indicates current relative
    playback speed.

    Defaults to 1.0.
*/

/*!
    \qmlproperty bool MprisPlayer::shuffle
    \brief Indicates whether the playlist is played in random order

    Should be set to true if the current playlist is being played in random
    order.

    Defaults to false.
*/

/*!
    \qmlproperty double MprisPlayer::volume
    \brief Indicates the current playing volume of the player

    Should be set to current relative playing volume used by the player.

    Defaults to 1.0.
*/

/*!
    \qmlsignal MprisPlayer::quitRequested()

    This signal is emitted when there is an incoming request
    to close the application.
*/

/*!
    \qmlsignal MprisPlayer::raiseRequested()

    This signal is emitted when there is an incoming request
    to present the application to the user.
*/

/*!
    \qmlsignal MprisPlayer::loopStatusRequested(int loopStatus)

    This signal is emitted when there is an incoming request
    to change the way the current media playlist is to be repeated.

    \sa MprisPlayer::loopStatus
*/

/*!
    \qmlsignal MprisPlayer::rateRequested(double rate)

    This signal is emitted when there is an incoming request to change
    the playback rate.

    \sa MprisPlayer::rate
    \sa MprisPlayer::minimumRate
    \sa MprisPlayer::maximumRate
*/

/*!
    \qmlsignal MprisPlayer::shuffleRequested(bool shuffle)

    This signal is emitted when there is an incoming request to change
    whether the current media playlist should be played in random order.

    \sa MprisPlayer::shuffle
*/

/*!
    \qmlsignal MprisPlayer::volumeRequested(double volume)

    This signal is emitted when there is an incoming request to change
    the current playback volume.

    \sa MprisPlayer::volume
*/

/*!
    \qmlsignal MprisPlayer::nextRequested()

    This signal is emitted when there is an incoming request to move
    to the next item on the playlist.

    \sa MprisPlayer::canGoNext
*/

/*!
    \qmlsignal MprisPlayer::openUriRequested(url uri)

    This signal is emitted when there is an incoming request to
    play media from specified location.

    \sa MprisPlayer::supportedUriSchemes
    \sa MprisPlayer::supportedMimeTypes
*/

/*!
    \qmlsignal MprisPlayer::pauseRequested()

    This signal is emitted when there is an incoming request to
    pause current playback.

    \sa MprisPlayer::canPause
*/

/*!
    \qmlsignal MprisPlayer::playRequested()

    This signal is emitted when there is an incoming request to
    start or resume playback.

    \sa MprisPlayer::canPlay
*/

/*!
    \qmlsignal MprisPlayer::playPauseRequested()

    This signal is emitted when there is an incoming request to
    start, resume or pause current playback.

    \sa MprisPlayer::canPlay
    \sa MprisPlayer::canPause
*/

/*!
    \qmlsignal MprisPlayer::previousRequested()

    This signal is emitted when there is an incoming request to move
    to the previous item on the playlist.

    \sa MprisPlayer::canGoPrevious
*/

/*!
    \qmlsignal MprisPlayer::seekRequested(int offset)

    This signal is emitted when there is an incoming request to change
    the position within the currently playing media. The offset should be
    interpreted as an millisecond offset from the current playing position.

    \sa MprisPlayer::position
    \sa MprisPlayer::seeked(int position)
*/

/*!
    \qmlsignal MprisPlayer::seeked(int position)

    This signal should be emitted whenever there has been a non-linear change
    in the position within the currently playing media. The value is the new
    position after seek in milliseconds.
*/

/*!
    \qmlsignal MprisPlayer::setPositionRequested(string trackId, int position)

    This signal is emitted when there is an incoming request to move to a
    certain millisecond position in the currently playing media.

    If trackId does not match the identifier of the currently playing track,
    the request should be ignored.
*/

/*!
    \qmlsignal MprisPlayer::stopRequested()

    This signal is emitted when there is an incoming request to stop current
    playback.
*/

void DeclarativeMprisPlayer::setServiceName(const QString &serviceName)
{
    MprisPlayer::setServiceName(QStringLiteral("%1.instance%2").arg(serviceName).arg(QCoreApplication::applicationPid()));
}
