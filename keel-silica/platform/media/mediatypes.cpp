// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "mediatypes.h"

#include "tagreader.h"

#include <QFileInfo>

QString MetadataReader::tagTitle(const QString &path)
{
    return keel::readTitleTag(path);
}

QString MetadataReader::getTitle(const QUrl &url) const
{
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    if (path.isEmpty())
        return {};
    const QString title = tagTitle(path);
    return title.isEmpty() ? QFileInfo(path).completeBaseName() : title;
}
