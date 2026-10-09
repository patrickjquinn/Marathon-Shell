// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MediaPlayerControls (enum holder) and MetadataReader,
// Keel's clean-room versions. Names from the public Sailfish.Media
// documentation (sailfishos.org/develop/docs/sailfish-media/): the
// MediaPlayerControlsPanel page lists MediaPlayerControls.NoRepeat,
// RepeatTrack, RepeatPlayList and NoShuffle, ShuffleTracks,
// ShufflePlaylists; MetadataReader has `string getTitle(url url)`.
// Numeric enum values are Keel's (the documented defaults are 0).
#ifndef KEEL_MEDIATYPES_H
#define KEEL_MEDIATYPES_H

#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class MediaPlayerControls : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("MediaPlayerControls only provides the RepeatType and ShuffleType enums")

public:
    enum RepeatType { NoRepeat, RepeatTrack, RepeatPlayList };
    Q_ENUM(RepeatType)
    enum ShuffleType { NoShuffle, ShuffleTracks, ShufflePlaylists };
    Q_ENUM(ShuffleType)

    using QObject::QObject;
};

// getTitle() reads the title tag of MP3 (ID3v2.3/2.4 TIT2, ID3v1), Ogg
// Vorbis/Opus and FLAC (Vorbis comment TITLE) files, and falls back to the
// file name without its extension, as a picker list shows it.
class MetadataReader : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    using QObject::QObject;

    Q_INVOKABLE QString getTitle(const QUrl &url) const;

    // The tag title of a local file, or an empty string.
    static QString tagTitle(const QString &path);
};

#endif // KEEL_MEDIATYPES_H
