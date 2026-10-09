// SPDX-FileCopyrightText: 2012 Robin Burchell <robin+nemo@viroteck.net>
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Robin Burchell <robin+nemo@viroteck.net>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#ifndef NEMOTHUMBNAILCACHE_H
#define NEMOTHUMBNAILCACHE_H

#include <nemothumbnailexports.h>

#include <QImage>
#include <QSize>
#include <QString>

QT_BEGIN_NAMESPACE
class QImageReader;
QT_END_NAMESPACE

class NEMO_QML_PLUGIN_THUMBNAILER_EXPORT NemoThumbnailCache
{
public:
    enum {
        None = 0,
        Small = 128,
        Medium = 256,
        Large = 512,
        ExtraLarge = 768
    };

    class ThumbnailData
    {
    public:
        ThumbnailData();
        ThumbnailData(const QString &path, const QImage &image, unsigned size);

        bool validPath() const;
        QString path() const;

        bool validImage() const;
        QImage image() const;

        unsigned size() const;

        QImage getScaledImage(const QSize &requestedSize, bool crop = false,
                              Qt::TransformationMode mode = Qt::FastTransformation) const;

    private:
        QString path_;
        QImage image_;
        unsigned size_;
    };

    static NemoThumbnailCache *instance();

    ThumbnailData requestThumbnail(const QString &path, const QSize &requestedSize, bool crop,
                                   bool unbounded = true, const QString &mimeType = QString());

    ThumbnailData existingThumbnail(const QString &path, const QSize &requestedSize,
                                    bool crop, bool unbounded = true) const;

protected:
    NemoThumbnailCache(const QString &cachePath);
    virtual ~NemoThumbnailCache();

    virtual ThumbnailData generateThumbnail(const QString &path, const QByteArray &key,
                                            int size, bool crop, const QString &mimeType);
    QString writeCacheFile(const QByteArray &key, const QImage &image);

    static QImage readImageThumbnail(
            QImageReader *reader, QSize requestedSize, bool crop, Qt::TransformationMode mode);

private:
    inline NemoThumbnailCache::ThumbnailData generateImageThumbnail(
            const QString &path, const QByteArray &key, int requestedSize, bool crop);

    const QString cachePath_;
    unsigned screenWidth_;
    unsigned screenHeight_;
};

#endif // NEMOTHUMBNAILCACHE_H
