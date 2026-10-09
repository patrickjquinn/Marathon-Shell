// SPDX-FileCopyrightText: 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
#include "mprismetadata.h"

#include <QPointer>

// proxy class for forwarding property access to another instance
class MprisMetaDataProxy : public Amber::MprisMetaData
{
public:
    MprisMetaDataProxy(QObject *parent = nullptr);
    virtual ~MprisMetaDataProxy();

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

    // set metadata instance to track
    void setTarget(Amber::MprisMetaData *target);

private:
    QPointer<Amber::MprisMetaData> m_target;
};
