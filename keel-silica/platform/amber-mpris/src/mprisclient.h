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


#ifndef MPRISCLIENT_H
#define MPRISCLIENT_H

#include <ambermpris.h>
#include <Mpris>
#include <MprisMetaData>

#include <QDBusConnection>

#include <QObject>
#include <QString>
#include <QStringList>

namespace Amber {

class MprisClientPrivate;

class AMBER_MPRIS_EXPORT MprisClient : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString service READ service)

    Q_PROPERTY(int positionInterval READ positionInterval WRITE setPositionInterval NOTIFY positionIntervalChanged)
    Q_PROPERTY(bool isValid READ isValid NOTIFY isValidChanged)

    // Mpris2 Root Interface
    Q_PROPERTY(bool canQuit READ canQuit NOTIFY canQuitChanged)
    Q_PROPERTY(bool canRaise READ canRaise NOTIFY canRaiseChanged)
    Q_PROPERTY(bool canSetFullscreen READ canSetFullscreen NOTIFY canSetFullscreenChanged)
    Q_PROPERTY(QString desktopEntry READ desktopEntry NOTIFY desktopEntryChanged)
    Q_PROPERTY(bool fullscreen READ fullscreen WRITE setFullscreen NOTIFY fullscreenChanged)
    Q_PROPERTY(bool hasTrackList READ hasTrackList NOTIFY hasTrackListChanged)
    Q_PROPERTY(QString identity READ identity NOTIFY identityChanged)
    Q_PROPERTY(QStringList supportedUriSchemes READ supportedUriSchemes NOTIFY supportedUriSchemesChanged)
    Q_PROPERTY(QStringList supportedMimeTypes READ supportedMimeTypes NOTIFY supportedMimeTypesChanged)

    // Mpris2 Player Interface
    Q_PROPERTY(bool canControl READ canControl NOTIFY canControlChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY canGoNextChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY canGoPreviousChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY canPauseChanged)
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY canPlayChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY canSeekChanged)
    Q_PROPERTY(bool hasShuffle READ hasShuffle NOTIFY hasShuffleChanged)
    Q_PROPERTY(bool hasLoopStatus READ hasLoopStatus NOTIFY hasLoopStatusChanged)
    Q_PROPERTY(Amber::Mpris::LoopStatus loopStatus READ loopStatus WRITE setLoopStatus NOTIFY loopStatusChanged)
    Q_PROPERTY(double maximumRate READ maximumRate NOTIFY maximumRateChanged)
    Q_PROPERTY(Amber::MprisMetaData *metaData READ metaData CONSTANT)
    Q_PROPERTY(double minimumRate READ minimumRate NOTIFY minimumRateChanged)
    Q_PROPERTY(Amber::Mpris::PlaybackStatus playbackStatus READ playbackStatus NOTIFY playbackStatusChanged)
    Q_PROPERTY(qlonglong position READ position NOTIFY positionChanged)
    Q_PROPERTY(double rate READ rate WRITE setRate NOTIFY rateChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)

public:
    MprisClient(const QString &service, const QDBusConnection &connection, QObject *parent = 0);
    ~MprisClient();

    bool isValid() const;

    int positionInterval() const;
    void setPositionInterval(int interval);

    // Mpris2 Root Interface
    Q_INVOKABLE bool quit();
    Q_INVOKABLE bool raise();

    // Mpris2 Player Interface
    Q_INVOKABLE bool next();
    Q_INVOKABLE bool openUri(const QUrl &uri);
    Q_INVOKABLE bool pause();
    Q_INVOKABLE bool play();
    Q_INVOKABLE bool playPause();
    Q_INVOKABLE bool previous();
    Q_INVOKABLE bool seek(qlonglong offset);
    Q_INVOKABLE bool setPosition(qlonglong position);
    Q_INVOKABLE bool setPosition(const QVariant &aTrackId, qlonglong position);
    Q_INVOKABLE bool stop();

    QString service() const;

    // Mpris2 Root Interface
    bool canQuit() const;
    bool canRaise() const;
    bool canSetFullscreen() const;
    QString desktopEntry() const;
    bool fullscreen() const;
    void setFullscreen(bool fullscreen);
    bool hasTrackList() const;
    QString identity() const;
    QStringList supportedUriSchemes() const;
    QStringList supportedMimeTypes() const;

    // Mpris2 Player Interface
    bool canControl() const;
    bool canGoNext() const;
    bool canGoPrevious() const;
    bool canPause() const;
    bool canPlay() const;
    bool canSeek() const;
    bool hasShuffle() const;
    bool hasLoopStatus() const;

    Mpris::LoopStatus loopStatus() const;
    void setLoopStatus(Mpris::LoopStatus loopStatus);

    double maximumRate() const;
    MprisMetaData *metaData() const;
    double minimumRate() const;

    Mpris::PlaybackStatus playbackStatus() const;

    qlonglong position() const;
    void requestPosition() const;

    double rate() const;
    void setRate(double rate);

    bool shuffle() const;
    void setShuffle(bool shuffle);

    double volume() const;
    void setVolume(double volume);

Q_SIGNALS:
    void positionIntervalChanged();
    void isValidChanged();

    // Mpris2 Root Interface
    void canQuitChanged();
    void canRaiseChanged();
    void canSetFullscreenChanged();
    void desktopEntryChanged();
    void fullscreenChanged();
    void hasTrackListChanged();
    void identityChanged();
    void supportedUriSchemesChanged();
    void supportedMimeTypesChanged();

    // Mpris2 Player Interface
    void canControlChanged();
    void canGoNextChanged();
    void canGoPreviousChanged();
    void canPauseChanged();
    void canPlayChanged();
    void canSeekChanged();
    void hasShuffleChanged();
    void hasLoopStatusChanged();
    void loopStatusChanged();
    void maximumRateChanged();
    void minimumRateChanged();
    void playbackStatusChanged();
    void positionChanged(qlonglong position);
    void rateChanged();
    void shuffleChanged();
    void volumeChanged();
    void seeked(qlonglong position);

protected:
    virtual void connectNotify(const QMetaMethod &method);
    virtual void disconnectNotify(const QMetaMethod &method);

private:
    MprisClientPrivate *priv;
};
}

#endif /* MPRISCLIENT_H */
