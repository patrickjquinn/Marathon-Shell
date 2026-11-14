// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// One file offered by a Keel picker, and the content categories the
// Sailfish.Pickers documentation names (documents, images, videos, music,
// downloads, any file).
#ifndef KEEL_PICKERS_CONTENTITEM_H
#define KEEL_PICKERS_CONTENTITEM_H

#include <QDateTime>
#include <QList>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>

namespace keel::pickers {

enum class Category { Any, Document, Image, Video, Music, Download, File };

struct ContentItem
{
    QString fileName;
    QString filePath;
    QString title;
    QString mimeType;
    qint64 fileSize = 0;
    QDateTime lastModified;
    bool isDir = false;
    bool selected = false;
    Category category = Category::File;

    QUrl url() const { return QUrl::fromLocalFile(filePath); }
    // The members Sailfish.Pickers documents for selectedContentProperties
    // and the selectedContent ListModel roles (fileName, filePath, url,
    // title, mimeType), plus fileSize, lastModified and contentType.
    QVariantMap toMap() const;
};

QString categoryName(Category category);

// The category of a MIME type (Image, Video, Music, Document, else File).
Category categoryForMime(const QString &mimeType);

// The fallback title: the tag title for music, else the file name without
// its extension.
QString titleFor(const QString &path, Category category);

// Glob name filters ("*.pdf", "*.doc") as Sailfish's nameFilters use them;
// an empty list matches everything.
bool matchesNameFilters(const QString &fileName, const QStringList &nameFilters);

} // namespace keel::pickers

#endif // KEEL_PICKERS_CONTENTITEM_H
