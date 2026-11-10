// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The filesystem fallback for Keel's pickers, used when Tracker is not
// available or fails: a bounded scan of the user's directories.
//
// Roots: KEEL_PICKERS_ROOTS (colon-separated) if set; else the home
// directory and the removable media mounted under /run/media/<user> (where
// Sailfish mounts memory cards). Downloads come from the XDG download
// directory only. Hidden files and directories are skipped; images in the
// XDG music directory (cover art) are not offered as images, as the
// Sailfish.Pickers documentation says of its image picker.
#ifndef KEEL_PICKERS_FILESOURCE_H
#define KEEL_PICKERS_FILESOURCE_H

#include "contentitem.h"

#include <QList>
#include <QStringList>
#include <atomic>

namespace keel::pickers {

class FileSource
{
public:
    static QStringList roots();
    static QString downloadDir();
    static QString musicDir();

    // Scans for `category` (Any matches every category but File) and the
    // name filters, newest first, at most `limit` items. Stops early when
    // `cancel` becomes true.
    static QList<ContentItem> scan(Category category, const QStringList &nameFilters, int limit,
                                   const std::atomic_bool &cancel);

    static constexpr int kMaxDepth = 8;
    static constexpr int kMaxVisited = 50000;
};

} // namespace keel::pickers

#endif // KEEL_PICKERS_FILESOURCE_H
