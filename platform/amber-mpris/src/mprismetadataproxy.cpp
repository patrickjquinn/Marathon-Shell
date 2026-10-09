// SPDX-FileCopyrightText: 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
#include "mprismetadataproxy.h"

#include <QDebug>

MprisMetaDataProxy::MprisMetaDataProxy(QObject *parent)
    : Amber::MprisMetaData(parent)
{
}

MprisMetaDataProxy::~MprisMetaDataProxy()
{
}

QVariant MprisMetaDataProxy::trackId() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->trackId();
}

void MprisMetaDataProxy::setTrackId(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::duration() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->duration();
}

void MprisMetaDataProxy::setDuration(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::artUrl() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->artUrl();
}

void MprisMetaDataProxy::setArtUrl(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::albumTitle() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->albumTitle();
}

void MprisMetaDataProxy::setAlbumTitle(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::albumArtist() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->albumArtist();
}

void MprisMetaDataProxy::setAlbumArtist(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::contributingArtist() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->contributingArtist();
}

void MprisMetaDataProxy::setContributingArtist(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::lyrics() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->lyrics();
}

void MprisMetaDataProxy::setLyrics(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::comment() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->comment();
}

void MprisMetaDataProxy::setComment(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::composer() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->composer();
}

void MprisMetaDataProxy::setComposer(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::year() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->year();
}

void MprisMetaDataProxy::setYear(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::date() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->date();
}

void MprisMetaDataProxy::setDate(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::discNumber() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->discNumber();
}

void MprisMetaDataProxy::setDiscNumber(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::genre() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->genre();
}

void MprisMetaDataProxy::setGenre(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::writer() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->writer();
}

void MprisMetaDataProxy::setWriter(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::title() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->title();
}

void MprisMetaDataProxy::setTitle(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::trackNumber() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->trackNumber();
}

void MprisMetaDataProxy::setTrackNumber(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::userRating() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->userRating();
}

void MprisMetaDataProxy::setUserRating(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::audioBpm() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->audioBpm();
}

void MprisMetaDataProxy::setAudioBpm(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::autoRating() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->autoRating();
}

void MprisMetaDataProxy::setAutoRating(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::firstUsed() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->firstUsed();
}

void MprisMetaDataProxy::setFirstUsed(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::lastUsed() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->lastUsed();
}

void MprisMetaDataProxy::setLastUsed(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::url() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->url();
}

void MprisMetaDataProxy::setUrl(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::useCount() const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->useCount();
}

void MprisMetaDataProxy::setUseCount(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariantMap MprisMetaDataProxy::extraFields() const
{
    if (!m_target) {
        return QVariantMap();
    }
    return m_target->extraFields();
}

QVariant MprisMetaDataProxy::extraField(const QString &key) const
{
    if (!m_target) {
        return QVariant();
    }
    return m_target->extraField(key);
}

void MprisMetaDataProxy::setExtraFields(const QVariantMap &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

void MprisMetaDataProxy::setExtraField(const QString &, const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

QVariant MprisMetaDataProxy::fillFrom() const
{
    return QVariant();
}

void MprisMetaDataProxy::setFillFrom(const QVariant &)
{
    qWarning() << "Invalid call to" << Q_FUNC_INFO;
}

void MprisMetaDataProxy::setTarget(Amber::MprisMetaData *target)
{
    if (target == m_target.data()) {
        return;
    }

    m_target = target;
    if (m_target.data()) {
        connect(m_target.data(), &Amber::MprisMetaData::metaDataChanged,
                this, &Amber::MprisMetaData::metaDataChanged);
    }

    metaDataChanged();
}
