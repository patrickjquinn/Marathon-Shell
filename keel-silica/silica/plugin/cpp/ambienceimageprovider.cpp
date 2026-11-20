// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "ambienceimageprovider.h"

#include <QColor>
#include <QImageReader>
#include <QUrl>
#include <QUrlQuery>

#include <algorithm>
#include <vector>

KeelAmbienceImageProvider::KeelAmbienceImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

static QString localSource(const QString &text)
{
    const QUrl url(text);
    if (url.scheme() == QLatin1String("qrc"))
        return QLatin1Char(':') + url.path();
    if (url.isLocalFile())
        return url.toLocalFile();
    return text;
}

// One horizontal box pass of `radius` over every row (edges clamped).
static void boxPassRows(QImage &image, int radius)
{
    const int w = image.width();
    const int h = image.height();
    const int span = 2 * radius + 1;
    std::vector<QRgb> row(static_cast<size_t>(w), 0);
    for (int y = 0; y < h; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        std::copy(line, line + w, row.begin());
        int r = 0, g = 0, b = 0;
        for (int i = -radius; i <= radius; ++i) {
            const QRgb c = row[static_cast<size_t>(std::clamp(i, 0, w - 1))];
            r += qRed(c);
            g += qGreen(c);
            b += qBlue(c);
        }
        for (int x = 0; x < w; ++x) {
            line[x] = qRgb(r / span, g / span, b / span);
            const QRgb out = row[static_cast<size_t>(std::clamp(x - radius, 0, w - 1))];
            const QRgb in = row[static_cast<size_t>(std::clamp(x + radius + 1, 0, w - 1))];
            r += qRed(in) - qRed(out);
            g += qGreen(in) - qGreen(out);
            b += qBlue(in) - qBlue(out);
        }
    }
}

static QImage transposed(const QImage &image)
{
    QImage out(image.height(), image.width(), QImage::Format_RGB32);
    for (int y = 0; y < image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x)
            reinterpret_cast<QRgb *>(out.scanLine(x))[y] = line[x];
    }
    return out;
}

void KeelAmbienceImageProvider::boxBlur(QImage &image, int radius)
{
    if (radius < 1 || image.isNull())
        return;
    image = image.convertToFormat(QImage::Format_RGB32);
    for (int pass = 0; pass < 3; ++pass)
        boxPassRows(image, radius);
    image = transposed(image);
    for (int pass = 0; pass < 3; ++pass)
        boxPassRows(image, radius);
    image = transposed(image);
}

QImage KeelAmbienceImageProvider::process(const QImage &source, const QSize &window)
{
    if (source.isNull() || window.isEmpty())
        return QImage();
    // The largest centred region of the source with the window's aspect.
    const qreal aspect = static_cast<qreal>(window.width()) / window.height();
    QRect crop = source.rect();
    if (static_cast<qreal>(source.width()) / source.height() > aspect) {
        const int w = qMax(1, qRound(source.height() * aspect));
        crop = QRect((source.width() - w) / 2, 0, w, source.height());
    } else {
        const int h = qMax(1, qRound(source.width() / aspect));
        crop = QRect(0, (source.height() - h) / 2, source.width(), h);
    }
    const QSize small(qMax(8, window.width() / 8), qMax(8, window.height() / 8));
    QImage image = source.copy(crop).scaled(small, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    // A Gaussian of about 7.5% of the window width; three box passes of
    // radius r approximate a Gaussian of sigma r.
    boxBlur(image, qMax(1, qRound(window.width() * 0.075 / 8)));
    return image;
}

// Blends every pixel `amount` of the way to `color`.
static void blendTowards(QImage &image, QColor color, qreal amount)
{
    if (amount <= 0 || image.isNull())
        return;
    const int a = qRound(qMin<qreal>(amount, 1) * 256);
    const int r = color.red() * a, g = color.green() * a, b = color.blue() * a;
    for (int y = 0; y < image.height(); ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QRgb c = line[x];
            line[x] = qRgb((qRed(c) * (256 - a) + r) >> 8, (qGreen(c) * (256 - a) + g) >> 8, (qBlue(c) * (256 - a) + b) >> 8);
        }
    }
}

QImage KeelAmbienceImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int q = id.lastIndexOf(QLatin1Char('?'));
    const QString path = localSource(QUrl::fromPercentEncoding((q < 0 ? id : id.left(q)).toUtf8()));
    const QUrlQuery query(q < 0 ? QString() : id.mid(q + 1));
    QSize window(query.queryItemValue(QStringLiteral("w")).toInt(),
                 query.queryItemValue(QStringLiteral("h")).toInt());
    if (window.isEmpty())
        window = requestedSize.isEmpty() ? QSize(540, 960) : requestedSize;
    QImageReader reader(path);
    reader.setAutoTransform(true);
    // Wallpapers are large (2048 px squares): decode at most at twice the
    // size needed.
    const QSize full = reader.size();
    if (full.isValid() && full.width() > 2 * window.width() && full.height() > 2 * window.height()) {
        const qreal f = qMax(2.0 * window.width() / full.width(), 2.0 * window.height() / full.height());
        reader.setScaledSize(QSize(qRound(full.width() * f), qRound(full.height() * f)));
    }
    QImage image = process(reader.read(), window);
    // The tone and the dimmer the ambience lays over its wallpaper, baked in
    // once here: the image comes out opaque and is drawn as it is.
    const bool light = query.queryItemValue(QStringLiteral("light")) == QLatin1String("1");
    blendTowards(image, light ? Qt::white : Qt::black, query.queryItemValue(QStringLiteral("tone")).toDouble());
    const QColor dim(QLatin1Char('#') + query.queryItemValue(QStringLiteral("dim")));
    if (dim.isValid())
        blendTowards(image, dim, 0.12);
    if (size)
        *size = image.size();
    return image;
}
