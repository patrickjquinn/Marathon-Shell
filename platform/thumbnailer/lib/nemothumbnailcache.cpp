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


#include <QLibrary>
#include <QFile>
#include <QUrl>
#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QImageReader>
#include <QDateTime>
#include <QtEndian>
#include <QElapsedTimer>
#include <QLoggingCategory>
#ifdef HAS_MLITE5
#include <MDConfItem>
#endif
#include <QStandardPaths>
#include <QProcess>
#include <QThreadStorage>

#include <QtGui/private/qimage_p.h>

#include "nemothumbnailcache.h"

Q_LOGGING_CATEGORY(thumbnailer, "Nemo.Thumbnailer", QtWarningMsg)

namespace {

template <typename T, int N> constexpr int lengthOf(const T(&)[N]) { return N; }

bool acceptableUnboundedSize(const QSize &requestedSize, bool crop, unsigned maxSize)
{
    const bool sufficientWidth = (unsigned) requestedSize.width() <= maxSize;
    const bool sufficientHeight = (unsigned) requestedSize.height() <= maxSize;
    return crop ? (sufficientWidth && sufficientHeight)
                : (sufficientWidth || sufficientHeight);
}

unsigned selectUnboundedSize(const QSize &requestedSize, unsigned screenWidth, unsigned screenHeight, bool crop)
{
    // Prefer a thumbnail size at least as large as the requested size
    const unsigned candidates[] = { NemoThumbnailCache::Small, NemoThumbnailCache::Medium, NemoThumbnailCache::Large,
                                    NemoThumbnailCache::ExtraLarge, screenWidth};
    for (int i = 0; i < lengthOf(candidates); ++i) {
        if (acceptableUnboundedSize(requestedSize, crop, candidates[i])) {
            return candidates[i];
        }
    }
    if (!acceptableUnboundedSize(requestedSize, crop, screenHeight)) {
        qCWarning(thumbnailer) << Q_FUNC_INFO << "Invalid thumbnail size"
                               << requestedSize << "requested; using:" << screenHeight;
    }
    return screenHeight;
}

bool acceptableBoundedSize(const QSize &requestedSize, unsigned size)
{
    const bool manageableWidth(size <= (unsigned)requestedSize.width());
    const bool manageableHeight(size <= (unsigned)requestedSize.height());
    return manageableWidth && manageableHeight;
}

unsigned selectBoundedSize(const QSize &requestedSize, unsigned screenWidth, unsigned screenHeight)
{
    // Select a size that does not exceed the requested size
    const unsigned candidates[] = { screenHeight, screenWidth, NemoThumbnailCache::ExtraLarge,
                                    NemoThumbnailCache::Large, NemoThumbnailCache::Medium };
    for (int i = 0; i < lengthOf(candidates); ++i) {
        if (acceptableBoundedSize(requestedSize, candidates[i])) {
            return candidates[i];
        }
    }
    if (!acceptableBoundedSize(requestedSize, NemoThumbnailCache::Small)) {
        qCWarning(thumbnailer) << Q_FUNC_INFO << "Invalid thumbnail size" << requestedSize << "requested; using:"
                               << NemoThumbnailCache::Small;
    }
    return NemoThumbnailCache::Small;
}

unsigned selectSize(const QSize &requestedSize, unsigned screenWidth, unsigned screenHeight, bool crop, bool unbounded)
{
    return unbounded
            ? selectUnboundedSize(requestedSize, screenWidth, screenHeight, crop)
            : selectBoundedSize(requestedSize, screenWidth, screenHeight);
}

unsigned increaseSize(unsigned size, unsigned screenWidth, unsigned screenHeight)
{
    const unsigned candidates[] = { NemoThumbnailCache::Small, NemoThumbnailCache::Medium, NemoThumbnailCache::Large,
                                    NemoThumbnailCache::ExtraLarge, screenWidth, screenHeight };
    for (int i = 0; i < lengthOf(candidates) - 1; ++i) {
        if (candidates[i] == size) {
            return candidates[i] + 1;
        }
    }
    return NemoThumbnailCache::None;
}

unsigned decreaseSize(unsigned size, unsigned screenWidth, unsigned screenHeight)
{
    const unsigned candidates[] = { screenHeight, screenWidth, NemoThumbnailCache::ExtraLarge, NemoThumbnailCache::Large,
                                    NemoThumbnailCache::Medium, NemoThumbnailCache::Small };
    for (int i = 0; i < lengthOf(candidates) - 1; ++i) {
        if (candidates[i] == size) {
            return candidates[i] + 1;
        }
    }
    return NemoThumbnailCache::None;
}

unsigned nextSize(unsigned size, unsigned screenWidth, unsigned screenHeight, bool unbounded)
{
    return unbounded
            ? increaseSize(size, screenWidth, screenHeight)
            : decreaseSize(size, screenWidth, screenHeight);
}

inline QString thumbnailsCachePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
            + QLatin1String("/org.nemomobile/thumbnails");
}

QString cachePath(const QString &thumbnailsCachePath, const QByteArray &key, bool makePath = false)
{
    QString subfolder = QString(key.left(2));
    if (makePath) {
        QDir d(thumbnailsCachePath);
        d.mkdir(subfolder);
    }

    return thumbnailsCachePath + QLatin1Char('/') + subfolder + QLatin1Char('/') + key;

}

QByteArray cacheKey(const QString &id, unsigned size, bool crop)
{
    const QByteArray baId = id.toUtf8(); // is there a more efficient way than a copy?

    QCryptographicHash hash(QCryptographicHash::Sha1);
    hash.addData(baId.constData(), baId.length());
    return hash.result().toHex() + "-" + QString::number(size).toLatin1() + (crop ? "" : "F");
}

QString attemptCachedServe(const QString &thumbnailsCachePath, const QString &id, const QByteArray &key)
{
    QFile fi(cachePath(thumbnailsCachePath, key));
    QFileInfo info(fi);
    if (info.exists() && info.lastModified() >= QFileInfo(id).lastModified()) {
        if (fi.open(QIODevice::ReadOnly)) {
            // cached file exists! hooray.
            return fi.fileName();
        }
    }

    return QString();
}

QString imagePath(const QString &uri)
{
    if (uri.startsWith("file://")) {
        return QUrl(uri).toLocalFile();
    } else {
        return uri;
    }
}

QImage scaleImage(const QImage &image, const QSize &requestedSize, bool crop, Qt::TransformationMode mode)
{
    const QImage scaledImage(image.size() != requestedSize
            ? image.scaled(requestedSize, crop ? Qt::KeepAspectRatioByExpanding : Qt::KeepAspectRatio, mode)
            : image);

    if (crop && scaledImage.size() != requestedSize) {
        QRect cropRect(0, 0, requestedSize.width(), requestedSize.height());
        cropRect.moveCenter(QPoint(scaledImage.width() / 2, scaledImage.height() / 2));

        return scaledImage.copy(cropRect);
    } else {
        return scaledImage;
    }
}

QStringList generatorArgs(const QString &path, const QString &thumbnailPath, const QSize &requestedSize, bool crop)
{
    QStringList args = {
        QFile::encodeName(path),
        "-w", QString::number(requestedSize.width()),
        "-h", QString::number(requestedSize.height()),
        "-o", QFile::encodeName(thumbnailPath)
    };
    if (crop) {
        args.append("-c");
    }

    return args;
}

NemoThumbnailCache::ThumbnailData generateVideoThumbnail(const QString &thumbnailsCachePath, const QString &path,
                                                         const QByteArray &key, const QSize &requestedSize, bool crop)
{
    const QString thumbnailPath(cachePath(thumbnailsCachePath, key, true));

    int rv = QProcess::execute(QStringLiteral("/usr/bin/thumbnaild-video"),
                               generatorArgs(path, thumbnailPath, requestedSize, crop));
    if (rv == 0) {
        return NemoThumbnailCache::ThumbnailData(thumbnailPath, QImage(), requestedSize.width());
    } else {
        qCWarning(thumbnailer) << Q_FUNC_INFO << "Could not generateVideoThumbnail:" << path << requestedSize << crop;
    }

    return NemoThumbnailCache::ThumbnailData();
}

NemoThumbnailCache::ThumbnailData generatePdfThumbnail(const QString &thumbnailsCachePath, const QString &path,
                                                       const QByteArray &key, const QSize &requestedSize, bool crop)
{
    const QString thumbnailPath(cachePath(thumbnailsCachePath, key, true));

    int rv = QProcess::execute(QStringLiteral("/usr/bin/thumbnaild-pdf"),
                               generatorArgs(path, thumbnailPath, requestedSize, crop));
    if (rv == 0) {
        return NemoThumbnailCache::ThumbnailData(thumbnailPath, QImage(), requestedSize.width());
    } else {
        qCWarning(thumbnailer) << Q_FUNC_INFO << "Could not generatePdfThumbnail:" << path << requestedSize << crop;
    }

    return NemoThumbnailCache::ThumbnailData();
}

class ConversionImage : public QImage
{
public:
    using QImage::convertToFormat_inplace;
};

static void convertImageToFormat(QImage *image, QImage::Format format)
{
    if (!static_cast<ConversionImage *>(image)->convertToFormat_inplace(format, Qt::AutoColor)) {
        *image = image->convertToFormat(format);
    }
}

static void optimizeImageForTexture(QImage *image)
{
    if (image->hasAlphaChannel()) {
        convertImageToFormat(image, QImage::Format_RGBA8888_Premultiplied);
    } else {
        convertImageToFormat(image, QImage::Format_RGBX8888);
    }
}

class NemoThumbnailCacheInstance : public NemoThumbnailCache
{
public:
    NemoThumbnailCacheInstance()
        : NemoThumbnailCache(thumbnailsCachePath())
    {
    }
};

static QThreadStorage<NemoThumbnailCacheInstance> cacheInstance;

}

NemoThumbnailCache::ThumbnailData::ThumbnailData()
    : size_(NemoThumbnailCache::None)
{
}

NemoThumbnailCache::ThumbnailData::ThumbnailData(const QString &path, const QImage &image, unsigned size)
    : path_(path)
    , image_(image)
    , size_(size)
{
}

bool NemoThumbnailCache::ThumbnailData::validPath() const
{
    return !path_.isEmpty();
}

QString NemoThumbnailCache::ThumbnailData::path() const
{
    return path_;
}

bool NemoThumbnailCache::ThumbnailData::validImage() const
{
    return !image_.isNull();
}

QImage NemoThumbnailCache::ThumbnailData::image() const
{
    return image_;
}

unsigned NemoThumbnailCache::ThumbnailData::size() const
{
    return size_;
}

QImage NemoThumbnailCache::ThumbnailData::getScaledImage(const QSize &requestedSize, bool crop,
                                                         Qt::TransformationMode mode) const
{
    if (!image_.isNull()) {
        return scaleImage(image_, requestedSize, crop, mode);
    } else if (!path_.isEmpty()) {
        QImageReader reader(path_);

        QImage image = readImageThumbnail(&reader, requestedSize, crop, mode);

        optimizeImageForTexture(&image);

        return image;
    } else {
        return QImage();
    }
}

static unsigned int MaximumSaneSize = 6000;

NemoThumbnailCache::NemoThumbnailCache(const QString &cachePath)
    : cachePath_(cachePath)
#ifdef HAS_MLITE5
    , screenWidth_(MDConfItem(QStringLiteral("/lipstick/screen/primary/width")).value(540).toInt())
    , screenHeight_(MDConfItem(QStringLiteral("/lipstick/screen/primary/height")).value(960).toInt())
#else
    , screenWidth_(540)
    , screenHeight_(960)
#endif
{
    if (screenWidth_ > screenHeight_) {
        std::swap(screenWidth_, screenHeight_);
    }

    if (screenWidth_ > MaximumSaneSize || screenHeight_ > MaximumSaneSize) {
        qWarning() << "Invalid screen dimensions, capping to" << MaximumSaneSize;
        screenWidth_ = std::min(screenWidth_, MaximumSaneSize);
        screenHeight_ = std::min(screenHeight_, MaximumSaneSize);
    }

    QDir directory(cachePath_);
    if (!directory.exists()) {
        directory.mkpath(QStringLiteral("."));
    }
}

NemoThumbnailCache::~NemoThumbnailCache()
{
}

NemoThumbnailCache *NemoThumbnailCache::instance()
{
    return &cacheInstance.localData();
}

NemoThumbnailCache::ThumbnailData NemoThumbnailCache::requestThumbnail(const QString &uri, const QSize &requestedSize,
                                                                       bool crop, bool unbounded, const QString &mimeType)
{
    const QString path(imagePath(uri));
    if (!path.isEmpty()) {
        ThumbnailData existing(existingThumbnail(uri, requestedSize, crop, unbounded));
        if (existing.validPath()) {
            return existing;
        }

        const unsigned size = selectSize(requestedSize, screenWidth_, screenHeight_, crop, unbounded);
        if (size != None) {
            const QByteArray key = cacheKey(path, size, crop);
            return generateThumbnail(path, key, size, crop, mimeType);
        } else {
            qCWarning(thumbnailer) << Q_FUNC_INFO << "Invalid thumbnail size " << requestedSize << " for " << path;
        }
    }

    return ThumbnailData();
}

NemoThumbnailCache::ThumbnailData NemoThumbnailCache::existingThumbnail(const QString &uri, const QSize &requestedSize,
                                                                        bool crop, bool unbounded) const
{
    const QString path(imagePath(uri));
    if (!path.isEmpty()) {
        for (unsigned size = selectSize(requestedSize, screenWidth_, screenHeight_, crop, unbounded);
                size != None;
                size = nextSize(size, screenWidth_, screenHeight_, unbounded)) {
            const QByteArray key = cacheKey(path, size, crop);
            QString thumbnailPath = attemptCachedServe(cachePath_, path, key);
            if (!thumbnailPath.isEmpty()) {
                return ThumbnailData(thumbnailPath, QImage(), size);
            }
        }
    }

    return ThumbnailData();
}

NemoThumbnailCache::ThumbnailData NemoThumbnailCache::generateThumbnail(
        const QString &path, const QByteArray &key, int size, bool crop, const QString &mimeType)
{
    const QSize boundsSize(size, size);

    if (mimeType == QStringLiteral("application/pdf")) {
        return generatePdfThumbnail(cachePath_, path, key, boundsSize, crop);
    }

    if (mimeType.startsWith("video/")) {
        return generateVideoThumbnail(cachePath_, path, key, boundsSize, crop);
    }

    // Assume image data
    return generateImageThumbnail(path, key, size, crop);
}


NemoThumbnailCache::ThumbnailData NemoThumbnailCache::generateImageThumbnail(const QString &path,
                                                                             const QByteArray &key,
                                                                             int requestedSize,
                                                                             bool crop)
{
    // image was not in cache thus we read it
    QImageReader ir(path);
    if (ir.canRead()) {
        const QSize originalSize = ir.size();

        if ((ir.transformation() == QImageIOHandler::TransformationNone
             || requestedSize > NemoThumbnailCache::ExtraLarge)
                && (originalSize.width() * 9 < requestedSize * 10
                    || originalSize.height() * 9 < requestedSize * 10)) {
            return NemoThumbnailCache::ThumbnailData(path, QImage(), requestedSize);
        }

        QImage img = readImageThumbnail(&ir, QSize(requestedSize, requestedSize), crop, Qt::FastTransformation);

        if (img.data_ptr() && !img.data_ptr()->checkForAlphaPixels()) {
            convertImageToFormat(&img, QImage::Format_RGB32);
        }

        // write the scaled image to cache
        QString thumbnailPath = writeCacheFile(key, img);

        optimizeImageForTexture(&img);

        return NemoThumbnailCache::ThumbnailData(thumbnailPath, img, requestedSize);
    }

    qCDebug(thumbnailer) << Q_FUNC_INFO << "Could not generateImageThumbnail:" << path << requestedSize << crop;
    return NemoThumbnailCache::ThumbnailData();
}

QImage NemoThumbnailCache::readImageThumbnail(
        QImageReader *reader,
        QSize requestedSize,
        bool crop,
        Qt::TransformationMode mode)
{
    if (mode == Qt::FastTransformation) {
        // Quality in the jpeg reader is binary. >= 50: high quality, < 50 fast.
        reader->setQuality(49);
    }
    const QSize originalSize = reader->size();
    const QSize rotatedSize = (reader->transformation() & QImageIOHandler::TransformationRotate90)
            ? requestedSize.transposed()
            : requestedSize;

    reader->setAutoTransform(true);

    if (originalSize.isValid()) {
        if (crop) {
            // scales arbitrary sized source image to requested size scaling either up or down
            // keeping aspect ratio of the original image intact by maximizing either width or height
            // and cropping the rest of the image away
            QSize scaledSize(originalSize);

            // now scale it filling the original rectangle by keeping aspect ratio, but expand if needed.
            scaledSize.scale(requestedSize, Qt::KeepAspectRatioByExpanding);

            // set the adjusted clipping rectangle in the center of the scaled image
            QPoint center((scaledSize.width() - 1) / 2, (scaledSize.height() - 1) / 2);
            QRect cr(0, 0, rotatedSize.width(), rotatedSize.height());
            cr.moveCenter(center);
            reader->setScaledClipRect(cr);

            // set requested target size of a thumbnail
            reader->setScaledSize(scaledSize);
        } else {
            // Maintains correct aspect ratio without cropping, as such the final image may
            // be smaller than requested in one dimension.
            QSize scaledSize(originalSize);
            scaledSize.scale(rotatedSize, Qt::KeepAspectRatio);
            reader->setScaledSize(scaledSize);
        }
    }

    QImage image(reader->read());

    if (!originalSize.isValid()) {
        image = scaleImage(image, rotatedSize, crop, mode);
    }

    return image;
}

QString NemoThumbnailCache::writeCacheFile(const QByteArray &key, const QImage &img)
{
    const QString thumbnailPath(cachePath(cachePath_, key, true));
    QFile thumbnailFile(thumbnailPath);
    if (!thumbnailFile.open(QIODevice::WriteOnly)) {
        qCWarning(thumbnailer) << "Couldn't cache to " << thumbnailFile.fileName();
        return QString();
    }
    img.save(&thumbnailFile, img.hasAlphaChannel() ? "PNG" : "JPG");
    thumbnailFile.flush();
    thumbnailFile.close();
    return thumbnailPath;
}
