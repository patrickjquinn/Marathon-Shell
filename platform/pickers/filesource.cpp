// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "filesource.h"

#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <algorithm>

namespace keel::pickers {

namespace {

bool isUnder(const QString &path, const QString &dir)
{
    return !dir.isEmpty() && (path == dir || path.startsWith(dir + QLatin1Char('/')));
}

struct Scan
{
    Category category;
    QStringList nameFilters;
    QString musicDir;
    const std::atomic_bool &cancel;
    QMimeDatabase mimes;
    QList<ContentItem> found;
    int visited = 0;

    bool wants(Category itemCategory) const
    {
        switch (category) {
        case Category::Any:
            return itemCategory != Category::File;
        case Category::File:
        case Category::Download:
            return true;
        default:
            return itemCategory == category;
        }
    }

    void walk(const QString &dir, int depth)
    {
        if (depth > FileSource::kMaxDepth || cancel.load())
            return;
        const QFileInfoList entries
            = QDir(dir).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable,
                                      QDir::Name);
        for (const QFileInfo &info : entries) {
            if (++visited > FileSource::kMaxVisited || cancel.load())
                return;
            if (info.isDir()) {
                if (!info.isSymLink())
                    walk(info.filePath(), depth + 1);
                continue;
            }
            if (!matchesNameFilters(info.fileName(), nameFilters))
                continue;
            const QString mime = mimes.mimeTypeForFile(info, QMimeDatabase::MatchExtension).name();
            const Category c = categoryForMime(mime);
            if (!wants(c))
                continue;
            if (c == Category::Image && isUnder(info.filePath(), musicDir))
                continue; // cover art
            ContentItem item;
            item.fileName = info.fileName();
            item.filePath = info.filePath();
            item.mimeType = mime;
            item.fileSize = info.size();
            item.lastModified = info.lastModified();
            item.category = category == Category::Download ? Category::Download : c;
            found.append(item);
        }
    }
};

} // namespace

QStringList FileSource::roots()
{
    const QString env = qEnvironmentVariable("KEEL_PICKERS_ROOTS");
    if (!env.isEmpty())
        return env.split(QLatin1Char(':'), Qt::SkipEmptyParts);
    QStringList out { QDir::homePath() };
    const QString user = qEnvironmentVariable("USER");
    if (!user.isEmpty()) {
        const QDir media(QStringLiteral("/run/media/") + user);
        for (const QFileInfo &card : media.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
            out.append(card.filePath());
    }
    return out;
}

QString FileSource::downloadDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
}

QString FileSource::musicDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
}

QList<ContentItem> FileSource::scan(Category category, const QStringList &nameFilters, int limit,
                                    const std::atomic_bool &cancel)
{
    Scan s { category, nameFilters, musicDir(), cancel, {}, {}, 0 };
    if (category == Category::Download) {
        s.walk(downloadDir(), 0);
    } else {
        QStringList seen;
        for (const QString &root : roots()) {
            const QString canonical = QFileInfo(root).canonicalFilePath();
            if (canonical.isEmpty() || seen.contains(canonical))
                continue;
            seen.append(canonical);
            s.walk(root, 0);
        }
    }
    std::stable_sort(s.found.begin(), s.found.end(), [](const ContentItem &a, const ContentItem &b) {
        return a.lastModified > b.lastModified;
    });
    if (s.found.size() > limit)
        s.found.resize(limit);
    for (ContentItem &item : s.found)
        item.title = titleFor(item.filePath, item.category);
    return s.found;
}

} // namespace keel::pickers
