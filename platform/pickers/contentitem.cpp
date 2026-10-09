// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "contentitem.h"

#include "tagreader.h"

#include <QFileInfo>
#include <QRegularExpression>

namespace keel::pickers {

QVariantMap ContentItem::toMap() const
{
    return {
        { QStringLiteral("fileName"), fileName },
        { QStringLiteral("filePath"), filePath },
        { QStringLiteral("url"), url() },
        { QStringLiteral("title"), title },
        { QStringLiteral("mimeType"), mimeType },
        { QStringLiteral("fileSize"), fileSize },
        { QStringLiteral("lastModified"), lastModified },
        { QStringLiteral("contentType"), categoryName(category) },
    };
}

QString categoryName(Category category)
{
    switch (category) {
    case Category::Document:
        return QStringLiteral("document");
    case Category::Image:
        return QStringLiteral("image");
    case Category::Video:
        return QStringLiteral("video");
    case Category::Music:
        return QStringLiteral("music");
    case Category::Download:
        return QStringLiteral("download");
    case Category::Any:
    case Category::File:
        break;
    }
    return QStringLiteral("file");
}

Category categoryForMime(const QString &mimeType)
{
    if (mimeType.startsWith(QLatin1String("image/")))
        return Category::Image;
    if (mimeType.startsWith(QLatin1String("video/")))
        return Category::Video;
    if (mimeType.startsWith(QLatin1String("audio/")))
        return Category::Music;
    static const QStringList documentPrefixes {
        QStringLiteral("text/"),
        QStringLiteral("application/pdf"),
        QStringLiteral("application/rtf"),
        QStringLiteral("application/msword"),
        QStringLiteral("application/vnd.oasis.opendocument."),
        QStringLiteral("application/vnd.openxmlformats-officedocument."),
        QStringLiteral("application/vnd.ms-"),
        QStringLiteral("application/epub+zip"),
        QStringLiteral("application/x-mobipocket-ebook"),
        QStringLiteral("application/vnd.comicbook"),
    };
    for (const QString &p : documentPrefixes) {
        if (mimeType.startsWith(p))
            return Category::Document;
    }
    return Category::File;
}

QString titleFor(const QString &path, Category category)
{
    if (category == Category::Music) {
        const QString tag = keel::readTitleTag(path);
        if (!tag.isEmpty())
            return tag;
    }
    return QFileInfo(path).completeBaseName();
}

bool matchesNameFilters(const QString &fileName, const QStringList &nameFilters)
{
    if (nameFilters.isEmpty())
        return true;
    for (const QString &f : nameFilters) {
        const QRegularExpression re(QRegularExpression::wildcardToRegularExpression(f),
                                    QRegularExpression::CaseInsensitiveOption);
        if (re.match(fileName).hasMatch())
            return true;
    }
    return false;
}

} // namespace keel::pickers
