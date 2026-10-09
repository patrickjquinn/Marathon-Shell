// SPDX-FileCopyrightText: 2015-2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 *
 * Copyright (C) 2015-2021 Jolla Ltd.
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

#ifndef MPRIS_PLAYER_H
#define MPRIS_PLAYER_H

#include <QObject>
#include <ambermpris.h>
#include <Mpris>
#include <MprisMetaData>

namespace Amber {

class MprisPlayerPrivate;

class AMBER_MPRIS_EXPORT MprisPlayer : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString serviceName READ serviceName WRITE setServiceName NOTIFY serviceNameChanged)

    Q_PROPERTY(bool canQuit READ canQuit WRITE setCanQuit NOTIFY canQuitChanged)
    Q_PROPERTY(bool canRaise READ canRaise WRITE setCanRaise NOTIFY canRaiseChanged)
    Q_PROPERTY(bool canSetFullscreen READ canSetFullscreen WRITE setCanSetFullscreen NOTIFY canSetFullscreenChanged)
    Q_PROPERTY(QString desktopEntry READ desktopEntry WRITE setDesktopEntry NOTIFY desktopEntryChanged)
    Q_PROPERTY(bool fullscreen READ fullscreen WRITE setFullscreen NOTIFY fullscreenChanged)
    Q_PROPERTY(bool hasTrackList READ hasTrackList WRITE setHasTrackList NOTIFY hasTrackListChanged)
    Q_PROPERTY(QString identity READ identity WRITE setIdentity NOTIFY identityChanged)
    Q_PROPERTY(QStringList supportedUriSchemes READ supportedUriSchemes WRITE setSupportedUriSchemes NOTIFY supportedUriSchemesChanged)
    Q_PROPERTY(QStringList supportedMimeTypes READ supportedMimeTypes WRITE setSupportedMimeTypes NOTIFY supportedMimeTypesChanged)

    Q_PROPERTY(bool canControl READ canControl WRITE setCanControl NOTIFY canControlChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext WRITE setCanGoNext NOTIFY canGoNextChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious WRITE setCanGoPrevious NOTIFY canGoPreviousChanged)
    Q_PROPERTY(bool canPause READ canPause WRITE setCanPause NOTIFY canPauseChanged)
    Q_PROPERTY(bool canPlay READ canPlay WRITE setCanPlay NOTIFY canPlayChanged)
    Q_PROPERTY(bool canSeek READ canSeek WRITE setCanSeek NOTIFY canSeekChanged)
    Q_PROPERTY(Amber::Mpris::LoopStatus loopStatus READ loopStatus WRITE setLoopStatus NOTIFY loopStatusChanged)
    Q_PROPERTY(double maximumRate READ maximumRate WRITE setMaximumRate NOTIFY maximumRateChanged)
    Q_PROPERTY(Amber::MprisMetaData *metaData READ metaData NOTIFY metaDataChanged)
    Q_PROPERTY(double minimumRate READ minimumRate WRITE setMinimumRate NOTIFY minimumRateChanged)
    Q_PROPERTY(Amber::Mpris::PlaybackStatus playbackStatus READ playbackStatus WRITE setPlaybackStatus NOTIFY playbackStatusChanged)
    Q_PROPERTY(qlonglong position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(double rate READ rate WRITE setRate NOTIFY rateChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool hasShuffle READ hasShuffle WRITE setHasShuffle NOTIFY hasShuffleChanged)
    Q_PROPERTY(bool hasLoopStatus READ hasLoopStatus WRITE setHasLoopStatus NOTIFY hasLoopStatusChanged)

public:
    MprisPlayer(QObject *parent = 0);
    virtual ~MprisPlayer();

    QString serviceName() const;
    bool canQuit() const;
    bool canRaise() const;
    bool canSetFullscreen() const;
    QString desktopEntry() const;
    bool fullscreen() const;
    bool hasTrackList() const;
    QString identity() const;
    QStringList supportedUriSchemes() const;
    QStringList supportedMimeTypes() const;

    bool canControl() const;
    bool canGoNext() const;
    bool canGoPrevious() const;
    bool canPause() const;
    bool canPlay() const;
    bool canSeek() const;
    bool hasShuffle() const;
    bool hasLoopStatus() const;
    Mpris::LoopStatus loopStatus() const;
    double maximumRate() const;
    MprisMetaData *metaData() const;
    double minimumRate() const;
    Mpris::PlaybackStatus playbackStatus() const;
    virtual qlonglong position() const;
    double rate() const;
    bool shuffle() const;
    double volume() const;

    virtual void setServiceName(const QString &serviceName);
    void setCanQuit(bool canQuit);
    void setCanRaise(bool canRaise);
    void setCanSetFullscreen(bool canSetFullscreen);
    void setDesktopEntry(const QString &desktopEntry);
    void setFullscreen(bool fullscreen);
    void setHasTrackList(bool hasTrackList);
    void setIdentity(const QString &identity);
    void setSupportedUriSchemes(const QStringList &supportedUriSchemes);
    void setSupportedMimeTypes(const QStringList &supportedMimeTypes);

    void setCanControl(bool canControl);
    void setCanGoNext(bool canGoNext);
    void setCanGoPrevious(bool canGoPrevious);
    void setCanPause(bool canPause);
    void setCanPlay(bool canPlay);
    void setCanSeek(bool canSeek);
    void setLoopStatus(Mpris::LoopStatus loopStatus);
    void setMaximumRate(double maximumRate);
    void setMinimumRate(double minimumRate);
    void setPlaybackStatus(Mpris::PlaybackStatus playbackStatus);
    void setPosition(qlonglong position);
    void setRate(double rate);
    void setShuffle(bool shuffle);
    void setVolume(double volume);
    void setHasShuffle(bool hasShuffle);
    void setHasLoopStatus(bool hasLoopStatus);

Q_SIGNALS:
    void serviceNameChanged();
    void canQuitChanged();
    void canRaiseChanged();
    void canSetFullscreenChanged();
    void desktopEntryChanged();
    void fullscreenChanged();
    void hasTrackListChanged();
    void identityChanged();
    void supportedUriSchemesChanged();
    void supportedMimeTypesChanged();
    void fullscreenRequested(bool fullscreen);

    void quitRequested();
    void raiseRequested();

    void canControlChanged();
    void canGoNextChanged();
    void canGoPreviousChanged();
    void canPauseChanged();
    void canPlayChanged();
    void canSeekChanged();
    void loopStatusChanged();
    void maximumRateChanged();
    void metaDataChanged();
    void minimumRateChanged();
    void playbackStatusChanged();
    void positionChanged();
    void rateChanged();
    void shuffleChanged();
    void volumeChanged();
    void hasShuffleChanged();
    void hasLoopStatusChanged();

    void positionRequested();
    void loopStatusRequested(int loopStatus);
    void rateRequested(double rate);
    void shuffleRequested(bool shuffle);
    void volumeRequested(double volume);
    void nextRequested();
    void openUriRequested(const QUrl &uri);
    void pauseRequested();
    void playRequested();
    void playPauseRequested();
    void previousRequested();
    void seekRequested(qlonglong offset);
    void seeked(qlonglong position);
    void setPositionRequested(const QString &trackId, qlonglong position);
    void stopRequested();

private:
    MprisPlayerPrivate *priv;
};
}

#endif // MPRIS_PLAYER_H
