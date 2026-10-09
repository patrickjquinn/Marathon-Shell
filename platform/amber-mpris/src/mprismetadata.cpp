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

/*!
    \qmltype MprisMetaData
    \inqmlmodule Amber.Mpris
    \brief Provides media metadata information

    Provides access to information about media content.

    All properties may be undefined if not applicable or known.
    A default trackId of \c{/org/mpris/MediaPlayer2/TrackList/NoTrack}
    will be returned if one is not defined.
*/

/*!
    \qmlproperty var MprisMetaData::trackId
    \brief Identifies the track inside a playlist

    Identifier for the current track, must be formatted as a valid DBus
    object path. No object needs to be registered on the path.

    Maps to MPRIS property 'mpris:trackid'.
*/

/*!
    \qmlproperty var MprisMetaData::duration
    \brief Length of the media in milliseconds

    Maps top MPRIS property 'mpris.length'.
*/

/*!
    \qmlproperty var MprisMetaData::artUrl
    \brief URL of an image representing the media

    Maps to MPRIS property 'mpris:artUrl'.
*/

/*!
    \qmlproperty var MprisMetaData::albumTitle
    \brief Title of the album of the media

    The name of an album the media is a part of, or undefined
    if not applicable or known.
    Maps to MPRIS property 'xesam:album'.
*/

/*!
    \qmlproperty var MprisMetaData::albumArtist
    \brief Artist of the album of the media

    The artist of an album the media is part of.
    Maps to MPRIS property 'xesam:albumArtist'.
*/

/*!
    \qmlproperty var MprisMetaData::contributingArtist
    \brief Artist or artists who contributed the media

    The artist or artists who have made the media.
    Eg. band, DJ, singer, director.
    Maps to MPRIS property 'xesam:artist'.
*/

/*!
    \qmlproperty var MprisMetaData::lyrics
    \brief Lyrics of the media

    Maps to MPRIS property 'xesam:asText'.
*/

/*!
    \qmlproperty var MprisMetaData::audioBpm
    \brief Beats per minute of audio

    Maps to MPRIS property 'xesam:audioBPM'.
*/

/*!
    \qmlproperty var MprisMetaData::autoRating
    \brief An automatic rating for the media

    A rating for the media decided via automated means in the range [0, 1].

    Maps to MPRIS property 'xesam:autoRating'.
*/

/*!
    \qmlproperty var MprisMetaData::comment
    \brief A list of free form comments about the media.

    Maps to MPRIS property 'xesam:comment'.
*/

/*!
    \qmlproperty var MprisMetaData::composer
    \brief List of composers of the media.

    Maps to MPRIS property 'xesam:composer'.
*/

/*!
    \qmlproperty var MprisMetaData::year
    \brief The year the media was produced.

    Convenience accessor for setting or getting the year part of the date
    property. Commonly only the year part of the date is meaningful.

    \sa MprisMetaData::date
*/

/*!
    \qmlproperty var MprisMetaData::date
    \brief The date the media was produced.

    Maps to MPRIS property 'xesam:contentCreated'.
*/

/*!
    \qmlproperty var MprisMetaData::discNumber
    \brief

    Maps to MPRIS property 'xesam:discNumber'
*/

/*!
    \qmlproperty var MprisMetaData::firstUsed
    \brief The date the media was played for the first time.

    Maps to MPRIS property 'xesam:firstUsed'.
*/

/*!
    \qmlproperty var MprisMetaData::genre
    \brief List of genres the media represents.

    Maps to MPRIS property 'xesam:genre'.
*/

/*!
    \qmlproperty var MprisMetaData::lastUsed
    \brief The date the media was played latest.

    Maps to MPRIS propery 'xesam:lastUsed'.
*/

/*!
    \qmlproperty var MprisMetaData::writer
    \brief The author of the lyrics/script of the media.

    Maps to MPRIS property 'xesam:lyricist'.
*/

/*!
    \qmlproperty var MprisMetaData::title
    \brief The title of the media.

    Maps to MPRIS propery 'xesam:title'.
*/

/*!
    \qmlproperty var MprisMetaData::trackNumber
    \brief The index of the media on an album.

    Maps to MPRIS property 'xesam:trackNumber'.
*/

/*!
    \qmlproperty var MprisMetaData::url
    \brief The url where the media is located.

    Maps to MPRIS property 'xesam:url'.
*/

/*!
    \qmlproperty var MprisMetaData::useCount
    \brief The number of times the media has been played.

    Maps to MPRIS property 'xesam:useCount'.
*/

/*!
    \qmlproperty var MprisMetaData::userRating
    \brief A manual rating for the media.

    A rating the user has assigned to the media in range [0, 1].
*/

/*!
    \qmlproperty QtObject MprisMetaData::fillFrom
    \brief An object to fill the meta data from.
    \internal

    Sets an object from where the meta data fields can be filled from.
    All matching properties will be read and bound to.
*/

#include <QVariant>
#include <QTimer>
#include <QMetaObject>
#include <QMetaProperty>
#include <QDateTime>
#include <QUrl>
#include <QDir>
#include <QDBusObjectPath>

#include <QDebug>
#include <QLoggingCategory>

#include "mprismetadata.h"
#include "mprismetadata_p.h"

using namespace Amber;

namespace {
    Q_LOGGING_CATEGORY(lcMetaData, "org.amber.mpris.metadata", QtWarningMsg)

    const QString MetaFieldTrackId = QStringLiteral("mpris:trackid");
    const QString MetaFieldLength = QStringLiteral("mpris:length");
    const QString MetaFieldArtUrl = QStringLiteral("mpris:artUrl");
    const QString MetaFieldAlbum = QStringLiteral("xesam:album");
    const QString MetaFieldAlbumArtist = QStringLiteral("xesam:albumArtist");
    const QString MetaFieldArtist = QStringLiteral("xesam:artist");
    const QString MetaFieldAsText = QStringLiteral("xesam:asText");
    const QString MetaFieldAudioBPM = QStringLiteral("xesam:audioBPM");
    const QString MetaFieldAutoRating = QStringLiteral("xesam:autoRating");
    const QString MetaFieldComment = QStringLiteral("xesam:comment");
    const QString MetaFieldComposer = QStringLiteral("xesam:composer");
    const QString MetaFieldContentCreated = QStringLiteral("xesam:contentCreated");
    const QString MetaFieldDiscNumber = QStringLiteral("xesam:discNumber");
    const QString MetaFieldFirstUsed = QStringLiteral("xesam:firstUsed");
    const QString MetaFieldGenre = QStringLiteral("xesam:genre");
    const QString MetaFieldLastUsed = QStringLiteral("xesam:lastUsed");
    const QString MetaFieldLyricist = QStringLiteral("xesam:lyricist");
    const QString MetaFieldTitle = QStringLiteral("xesam:title");
    const QString MetaFieldTrackNumber = QStringLiteral("xesam:trackNumber");
    const QString MetaFieldUrl = QStringLiteral("xesam:url");
    const QString MetaFieldUseCount = QStringLiteral("xesam:useCount");
    const QString MetaFieldUserRating = QStringLiteral("xesam:userRating");

    const QString MetaFieldInternalYear = QStringLiteral("year");

    const QString NoTrackObjectPath = QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack");

    bool validateTrackIdAsObjectPath(const QString &trackId)
    {
        return !QDBusObjectPath(trackId).path().isEmpty();
    }

    template<class T> QVariant ensureType(const QVariant &from)
    {
        if (from.isNull())
            return QVariant();
        return QVariant::fromValue(qvariant_cast<T>(from));
    }

    template<> QVariant ensureType<QDateTime>(const QVariant &from)
    {
        if (from.isNull())
            return QVariant();
        QDateTime d = from.toDateTime();
        return d.toString(Qt::ISODate);
    }

    template<> QVariant ensureType<QDBusObjectPath>(const QVariant &from)
    {
        QDBusObjectPath path;

        if (from.userType() == qMetaTypeId<QDBusObjectPath>()) {
            path = from.value<QDBusObjectPath>();
        } else if (from.userType() == qMetaTypeId<QString>()) {
            path = QDBusObjectPath(from.toString());
        }

        if (path.path().isEmpty()) {
            path = QDBusObjectPath(NoTrackObjectPath);
        }

        return QVariant::fromValue(path);
    }

    const QMap<QString, QVariant (*)(const QVariant &)> converters {
        { MetaFieldTrackId, ensureType<QDBusObjectPath> },
        { MetaFieldLength, ensureType<qint64> },
        { MetaFieldArtUrl, ensureType<QString> },
        { MetaFieldAlbum, ensureType<QString> },
        { MetaFieldAlbumArtist, ensureType<QStringList> },
        { MetaFieldArtist, ensureType<QStringList> },
        { MetaFieldAsText, ensureType<QString> },
        { MetaFieldAudioBPM, ensureType<qint32> },
        { MetaFieldAutoRating, ensureType<double> },
        { MetaFieldComment, ensureType<QString> },
        { MetaFieldComposer, ensureType<QStringList> },
        { MetaFieldContentCreated, ensureType<QDateTime> },
        { MetaFieldDiscNumber, ensureType<qint32> },
        { MetaFieldFirstUsed, ensureType<QDateTime> },
        { MetaFieldGenre, ensureType<QStringList> },
        { MetaFieldLastUsed, ensureType<QDateTime> },
        { MetaFieldLyricist, ensureType<QStringList> },
        { MetaFieldTitle, ensureType<QString> },
        { MetaFieldTrackNumber, ensureType<qint32> },
        { MetaFieldUrl, ensureType<QString> },
        { MetaFieldUseCount, ensureType<qint32> },
        { MetaFieldUserRating, ensureType<double> },
    };
}

MprisMetaDataPrivate::MprisMetaDataPrivate(MprisMetaData *metaData)
    : QObject(metaData)
    , q_ptr(metaData)
{
    m_changedDelay.setInterval(50);
    m_changedDelay.setSingleShot(true);
    m_fillFromDelay.setInterval(10);
    m_fillFromDelay.setSingleShot(true);
    connect(&m_changedDelay, &QTimer::timeout, this, [=] { Q_EMIT metaData->metaDataChanged(); });
    connect(&m_fillFromDelay, &QTimer::timeout, this, &MprisMetaDataPrivate::fillFrom);
}

MprisMetaDataPrivate::~MprisMetaDataPrivate() {}

void MprisMetaDataPrivate::fillFromPropertyChange()
{
    for (auto p : m_signalPropertyMap[senderSignalIndex()]) {
        m_changedProperties << p;
    }

    m_fillFromDelay.start();
}

void MprisMetaDataPrivate::fillFrom()
{
    if (!m_fillFromObject) {
        return;
    }

    for (auto p : m_changedProperties) {
        q_ptr->setProperty(p, m_fillFromObject->property(p));
    }

    m_changedProperties.clear();
}

QVariantMap MprisMetaDataPrivate::typedMetaData() const
{
    QVariantMap rv;

    (void)m_metaData[MetaFieldTrackId];
    for (auto c = m_metaData.cbegin();
         c != m_metaData.cend();
         ++c) {
        if (converters.contains(c.key())) {
            QVariant v = converters[c.key()](c.value());
            if (!v.isNull()) {
                rv[c.key()] = v;
            }
        } else if (c.key() == MetaFieldInternalYear) {
            if (!m_metaData.contains(MetaFieldContentCreated) || m_metaData[MetaFieldContentCreated].isNull()) {
                QDateTime d = QDateTime::fromString(QStringLiteral("%1-01-02T00:00:00Z").arg(c.value().toString()), Qt::ISODate);
                rv[MetaFieldContentCreated] = d.toString(Qt::ISODate);
            }
        } else if (c.key().count(':') == 1) {
            rv[c.key()] = c.value();
        }
    }

    if (!rv.contains(MetaFieldTrackId)) {
        rv[MetaFieldTrackId] = converters[MetaFieldTrackId](QVariant());
    }

    return rv;
}

void MprisMetaDataPrivate::setMetaData(const QString &key, const QVariant &value)
{
    if (!value.isValid() || value.isNull()) {
        if (!m_metaData.remove(key))
            return;
    } else if (m_metaData.value(key) != value) {
        m_metaData[key] = value;
    } else {
        return;
    }
    m_changedDelay.start();
}

void MprisMetaDataPrivate::setMetaData(const QVariantMap &metaData)
{
    if (metaData != m_metaData) {
        m_metaData = metaData;
        Q_EMIT q_ptr->metaDataChanged();
    }
}

MprisMetaData::MprisMetaData(QObject *parent)
    : QObject(parent)
    , priv(new MprisMetaDataPrivate(this))
{
}

MprisMetaData::~MprisMetaData()
{
}

QVariant MprisMetaData::trackId() const
{
    if (priv->m_metaData.contains(MetaFieldTrackId)) {
        return priv->m_metaData[MetaFieldTrackId];
    }

    return QVariant();
}

void MprisMetaData::setTrackId(const QVariant &trackId)
{
    // Accepts a string, QDBusObjectPath or null.
    // String must validate as object path or the last element of a path.
    QVariant value;
    if (trackId.userType() == qMetaTypeId<QDBusObjectPath>()) {
        value = trackId.value<QDBusObjectPath>().path();
    } else if (trackId.isNull()) {
        // Pass, null QVariant makes D-Bus interface to advertise NoTrack value
    } else {
        QString id = trackId.toString();
        if (!validateTrackIdAsObjectPath(id))
            qCWarning(lcMetaData) << "Invalid value given for mpris:trackid:" << id;
        else
            value = id;
    }
    priv->setMetaData(MetaFieldTrackId, value);
}

QVariant MprisMetaData::duration() const
{
    if (priv->m_metaData.contains(MetaFieldLength)) {
        return qvariant_cast<qint64>(priv->m_metaData[MetaFieldLength]) / 1000;
    }

    return QVariant();
}

void MprisMetaData::setDuration(const QVariant &duration)
{
    if (duration.toLongLong() <= 0)
        priv->setMetaData(MetaFieldLength, QVariant());
    else
        priv->setMetaData(MetaFieldLength, duration.toLongLong() * 1000);
}

QVariant MprisMetaData::artUrl() const
{
    return priv->m_metaData.value(MetaFieldArtUrl);
}

void MprisMetaData::setArtUrl(const QVariant &url)
{
    priv->setMetaData(MetaFieldArtUrl, url);
}

QVariant MprisMetaData::contributingArtist() const
{
    return priv->m_metaData.value(MetaFieldArtist);
}

void MprisMetaData::setContributingArtist(const QVariant &artist)
{
    priv->setMetaData(MetaFieldArtist, artist);
}

QVariant MprisMetaData::albumTitle() const
{
    return priv->m_metaData.value(MetaFieldAlbum);
}

void MprisMetaData::setAlbumTitle(const QVariant &title)
{
    priv->setMetaData(MetaFieldAlbum, title);
}

QVariant MprisMetaData::albumArtist() const
{
    return priv->m_metaData.value(MetaFieldAlbumArtist);
}

void MprisMetaData::setAlbumArtist(const QVariant &artist)
{
    priv->setMetaData(MetaFieldAlbumArtist, artist);
}

QVariant MprisMetaData::lyrics() const
{
    return priv->m_metaData.value(MetaFieldAsText);
}

void MprisMetaData::setLyrics(const QVariant &lyrics)
{
    priv->setMetaData(MetaFieldAsText, lyrics);
}

QVariant MprisMetaData::comment() const
{
    return priv->m_metaData.value(MetaFieldComment);
}

void MprisMetaData::setComment(const QVariant &comment)
{
    priv->setMetaData(MetaFieldComment, comment);
}

QVariant MprisMetaData::composer() const
{
    return priv->m_metaData.value(MetaFieldComposer);
}

void MprisMetaData::setComposer(const QVariant &composer)
{
    priv->setMetaData(MetaFieldComposer, composer);
}

QVariant MprisMetaData::year() const
{
    if (priv->m_metaData.contains(MetaFieldInternalYear)) {
        return priv->m_metaData[MetaFieldInternalYear];
    }
    if (priv->m_metaData.contains(MetaFieldContentCreated) &&
        priv->m_metaData[MetaFieldContentCreated].isValid()) {
        QDateTime d = QDateTime::fromString(priv->m_metaData[MetaFieldContentCreated].toString(), Qt::ISODate);
        return d.date().year();
    }

    return QVariant();
}

void MprisMetaData::setYear(const QVariant &year)
{
    priv->setMetaData(MetaFieldInternalYear, year);
}

QVariant MprisMetaData::date() const
{
    if (priv->m_metaData.contains(MetaFieldContentCreated)) {
        return QDateTime::fromString(priv->m_metaData[MetaFieldContentCreated].toString(), Qt::ISODate);
    }
    return QVariant();
}

void MprisMetaData::setDate(const QVariant &date)
{
    priv->setMetaData(MetaFieldContentCreated, date);
}

QVariant MprisMetaData::discNumber() const
{
    return priv->m_metaData.value(MetaFieldDiscNumber);
}

void MprisMetaData::setDiscNumber(const QVariant &chapter)
{
    priv->setMetaData(MetaFieldDiscNumber, chapter);
}

QVariant MprisMetaData::genre() const
{
    return priv->m_metaData.value(MetaFieldGenre);
}

void MprisMetaData::setGenre(const QVariant &genre)
{
    priv->setMetaData(MetaFieldGenre, genre);
}

QVariant MprisMetaData::writer() const
{
    return priv->m_metaData.value(MetaFieldLyricist);
}

void MprisMetaData::setWriter(const QVariant &writer)
{
    priv->setMetaData(MetaFieldLyricist, writer);
}

QVariant MprisMetaData::title() const
{
    return priv->m_metaData.value(MetaFieldTitle);
}

void MprisMetaData::setTitle(const QVariant &title)
{
    priv->setMetaData(MetaFieldTitle, title);
}

QVariant MprisMetaData::trackNumber() const
{
    return priv->m_metaData.value(MetaFieldTrackNumber);
}

void MprisMetaData::setTrackNumber(const QVariant &track)
{
    priv->setMetaData(MetaFieldTrackNumber, track);
}

QVariant MprisMetaData::userRating() const
{
    return priv->m_metaData.value(MetaFieldUserRating);
}

void MprisMetaData::setUserRating(const QVariant &rating)
{
    priv->setMetaData(MetaFieldUserRating, rating);
}

QVariant MprisMetaData::audioBpm() const
{
    return priv->m_metaData.value(MetaFieldAudioBPM);
}

void MprisMetaData::setAudioBpm(const QVariant &bpm)
{
    priv->setMetaData(MetaFieldAudioBPM, bpm);
}

QVariant MprisMetaData::autoRating() const
{
    return priv->m_metaData.value(MetaFieldAutoRating);
}

void MprisMetaData::setAutoRating(const QVariant &rating)
{
    priv->setMetaData(MetaFieldAutoRating, rating);
}

QVariant MprisMetaData::firstUsed() const
{
    return priv->m_metaData.value(MetaFieldFirstUsed);
}

void MprisMetaData::setFirstUsed(const QVariant &used)
{
    priv->setMetaData(MetaFieldFirstUsed, used);
}

QVariant MprisMetaData::lastUsed() const
{
    return priv->m_metaData.value(MetaFieldLastUsed);
}

void MprisMetaData::setLastUsed(const QVariant &used)
{
    priv->setMetaData(MetaFieldLastUsed, used);
}

QVariant MprisMetaData::url() const
{
    return priv->m_metaData.value(MetaFieldUrl);
}

void MprisMetaData::setUrl(const QVariant &url)
{
    priv->setMetaData(MetaFieldUrl, url);
}

QVariant MprisMetaData::useCount() const
{
    return priv->m_metaData.value(MetaFieldUseCount);
}

void MprisMetaData::setUseCount(const QVariant &count)
{
    priv->setMetaData(MetaFieldUseCount, count);
}

void MprisMetaData::setFillFrom(const QVariant &fillFrom)
{
    const QMetaObject *thisMeta = this->metaObject();

    if (priv->m_fillFromObject) {
        priv->m_fillFromObject->disconnect(priv);
        priv->m_fillFromObject.clear();

        for (const auto &i : priv->m_signalPropertyMap) {
            for (const char *prop : i) {
                setProperty(prop, QVariant());
            }
        }
        priv->m_signalPropertyMap.clear();
    }

    priv->m_fillFromObject = qvariant_cast<QObject *>(fillFrom);

    if (priv->m_fillFromObject) {
        const QMetaObject *privMeta = priv->metaObject();
        const QMetaObject *thatMeta = priv->m_fillFromObject->metaObject();
        QMetaMethod fillFromChanged = privMeta->method(privMeta->indexOfSlot("fillFromPropertyChange()"));

        for (int i = thisMeta->propertyOffset(); i < thisMeta->propertyCount(); i++) {
            QMetaProperty thisProp = thisMeta->property(i);
            if (QLatin1String("fillFrom") == thisProp.name())
                continue;

            int propertyIndex = thatMeta->indexOfProperty(thisProp.name());

            if (propertyIndex >= 0) {
                QMetaProperty thatProp = thatMeta->property(propertyIndex);
                if (thatProp.hasNotifySignal()) {
                    connect(&*priv->m_fillFromObject, thatProp.notifySignal(),
                            priv, fillFromChanged);
                    priv->m_signalPropertyMap[thatProp.notifySignalIndex()] << thatProp.name();
                }
                setProperty(thisProp.name(), priv->m_fillFromObject->property(thatProp.name()));
            }
        }
    } else {
        if (fillFrom.userType() == qMetaTypeId<QVariantMap>()) {
            QVariantMap map = fillFrom.toMap();
            for (auto i = map.cbegin();
                 i != map.cend();
                 i++) {
                int propertyIndex = thisMeta->indexOfProperty(i.key().toLatin1());

                if (propertyIndex >= 0) {
                    setProperty(thisMeta->property(propertyIndex).name(), i.value());
                }
            }
        }
    }

    priv->m_fillFrom = fillFrom;
}

QVariant MprisMetaData::fillFrom() const
{
    return priv->m_fillFrom;
}

QVariantMap MprisMetaData::extraFields() const
{
    QVariantMap rv;

    for (auto c = priv->m_metaData.cbegin();
         c != priv->m_metaData.cend();
         ++c) {
        if (c.key().count(':') == 1 && !converters.contains(c.key())) { // MetaFieldInternalYear has no namespace
            rv[c.key()] = c.value();
        }
    }

    return rv;
}

QVariant MprisMetaData::extraField(const QString &key) const
{
    if (priv->m_metaData.contains(key) && !converters.contains(key) && key != MetaFieldInternalYear) {
        return priv->m_metaData[key];
    } else {
        return QVariant();
    }
}

void MprisMetaData::setExtraFields(const QVariantMap &fields)
{
    for (auto c = fields.cbegin();
         c != fields.cend();
         ++c) {
        setExtraField(c.key(), c.value());
    }
}

void MprisMetaData::setExtraField(const QString &key, const QVariant &value)
{
    if (!converters.contains(key) && key.count(':') == 1) {
        priv->setMetaData(key, value);
    }
}
