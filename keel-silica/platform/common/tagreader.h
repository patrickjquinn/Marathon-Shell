// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A small title-tag reader for Keel's platform modules (Sailfish.Media
// MetadataReader, Sailfish.Pickers' `title`): ID3v2.2/2.3/2.4 (TT2/TIT2) and
// ID3v1 in MP3 files, and Vorbis comments (TITLE=) in Ogg Vorbis, Ogg Opus
// and FLAC files. Written for Keel from the public format descriptions
// (id3.org ID3v2.3/2.4 structure, xiph.org Vorbis comment and FLAC format
// pages); no tagging library is used. Reads at most 256 KiB of a file.
#ifndef KEEL_TAGREADER_H
#define KEEL_TAGREADER_H

#include <QString>

namespace keel {

// The title tag of the file at `path`, or an empty string.
QString readTitleTag(const QString &path);

} // namespace keel

#endif // KEEL_TAGREADER_H
