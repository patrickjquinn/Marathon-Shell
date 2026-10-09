// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
// -*- c++ -*-

/*!
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

#ifndef MPRISMETADATA_H
#define MPRISMETADATA_H

#include <QObject>
#include <QVariant>
#include <mpris.h>
#include <ambermpris.h>

namespace Amber {
class MprisMetaDataPrivate;

// TODO: this should probably be split into read-only api on the controller side and
// writable api on the media app side. Would be a slight API break, at least for naming.
// also the change delay probably makes sense mostly on the media app side.

class AMBER_MPRIS_EXPORT MprisMetaData : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariant trackId READ trackId WRITE setTrackId NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant duration READ duration WRITE setDuration NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant artUrl READ artUrl WRITE setArtUrl NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant albumTitle READ albumTitle WRITE setAlbumTitle NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant albumArtist READ albumArtist WRITE setAlbumArtist NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant contributingArtist READ contributingArtist WRITE setContributingArtist NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant lyrics READ lyrics WRITE setLyrics NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant audioBpm READ audioBpm WRITE setAudioBpm NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant autoRating READ autoRating WRITE setAutoRating NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant comment READ comment WRITE setComment NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant composer READ composer WRITE setComposer NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant year READ year WRITE setYear NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant date READ date WRITE setDate NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant discNumber READ discNumber WRITE setDiscNumber NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant firstUsed READ firstUsed WRITE setFirstUsed NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant genre READ genre WRITE setGenre NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant lastUsed READ lastUsed WRITE setLastUsed NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant writer READ writer WRITE setWriter NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant title READ title WRITE setTitle NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant trackNumber READ trackNumber WRITE setTrackNumber NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant url READ url WRITE setUrl NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant useCount READ useCount WRITE setUseCount NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant userRating READ userRating WRITE setUserRating NOTIFY metaDataChanged)

    Q_PROPERTY(QVariantMap extraFields READ extraFields WRITE setExtraFields NOTIFY metaDataChanged)
    Q_PROPERTY(QVariant fillFrom READ fillFrom WRITE setFillFrom NOTIFY fillFromChanged)

public:
    MprisMetaData(QObject *parent = 0);
    MprisMetaData();
    virtual ~MprisMetaData();

    virtual QVariant trackId() const;
    virtual void setTrackId(const QVariant &trackId);

    virtual QVariant duration() const;
    virtual void setDuration(const QVariant &duration);
    virtual QVariant artUrl() const;
    virtual void setArtUrl(const QVariant &url);
    virtual QVariant albumTitle() const;
    virtual void setAlbumTitle(const QVariant &title);
    virtual QVariant albumArtist() const;
    virtual void setAlbumArtist(const QVariant &artist);
    virtual QVariant contributingArtist() const;
    virtual void setContributingArtist(const QVariant &artist);
    virtual QVariant lyrics() const;
    virtual void setLyrics(const QVariant &lyrics);

    virtual QVariant comment() const;
    virtual void setComment(const QVariant &comment);
    virtual QVariant composer() const;
    virtual void setComposer(const QVariant &composer);
    virtual QVariant year() const;
    virtual void setYear(const QVariant &year);
    virtual QVariant date() const;
    virtual void setDate(const QVariant &date);
    virtual QVariant discNumber() const;
    virtual void setDiscNumber(const QVariant &disc);

    virtual QVariant genre() const;
    virtual void setGenre(const QVariant &genre);

    virtual QVariant writer() const;
    virtual void setWriter(const QVariant &writer);

    virtual QVariant title() const;
    virtual void setTitle(const QVariant &title);
    virtual QVariant trackNumber() const;
    virtual void setTrackNumber(const QVariant &track);

    virtual QVariant userRating() const;
    virtual void setUserRating(const QVariant &rating);

    virtual QVariant audioBpm() const;
    virtual void setAudioBpm(const QVariant &bpm);
    virtual QVariant autoRating() const;
    virtual void setAutoRating(const QVariant &rating);
    virtual QVariant firstUsed() const;
    virtual void setFirstUsed(const QVariant &used);
    virtual QVariant lastUsed() const;
    virtual void setLastUsed(const QVariant &used);
    virtual QVariant url() const;
    virtual void setUrl(const QVariant &url);
    virtual QVariant useCount() const;
    virtual void setUseCount(const QVariant &count);

    virtual QVariantMap extraFields() const;
    virtual QVariant extraField(const QString &key) const;
    virtual void setExtraFields(const QVariantMap &fields);
    virtual void setExtraField(const QString &key, const QVariant &value);

    virtual QVariant fillFrom() const;
    virtual void setFillFrom(const QVariant &fillFrom);

Q_SIGNALS:
    void metaDataChanged();
    void fillFromChanged();

private:
    MprisMetaDataPrivate *priv;
    friend class MprisPlayerPrivate;
    friend class MprisClientPrivate;
};
}
#endif
