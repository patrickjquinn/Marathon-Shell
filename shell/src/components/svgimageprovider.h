#pragma once

#include "marathon-shell-native/src/svg.cxxqt.h"

#include <QFile>
#include <QImage>
#include <QQuickImageProvider>

// image://svg/<path>: an absolute file path, or a resource's without its ':'. Rendered by
// resvg (svg.rs), which draws clip paths and text that Qt Svg does not.
class SvgImageProvider : public QQuickImageProvider {
  public:
    SvgImageProvider()
        : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override {
        const QString path = QLatin1Char('/') + id;
        QFile         file(QFile::exists(path) ? path : QLatin1Char(':') + path);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        const QByteArray         svg    = file.readAll();
        const int                w      = requested.width() > 0 ? requested.width() : 128;
        const int                h      = requested.height() > 0 ? requested.height() : 128;
        const rust::Vec<uint8_t> pixels = marathon::svg::render(
            rust::Slice<const uint8_t>(reinterpret_cast<const uint8_t *>(svg.constData()),
                                       static_cast<size_t>(svg.size())),
            w, h);
        if (pixels.empty())
            return {};
        QImage image =
            QImage(pixels.data(), w, h, qsizetype(w) * 4, QImage::Format_RGBA8888_Premultiplied)
                .copy();
        if (size)
            *size = image.size();
        return image;
    }
};
