#include "src/components/wallpaperimageprovider.h"

#include <QImageReader>
#include <QPainter>
#include <QSvgRenderer>
#include <QUrl>
#include <QUrlQuery>

#include <array>
#include <cmath>

namespace {
    // MColors.bb10Black, in 8-bit levels.
    constexpr double                            kFloor = 4.0;

    constexpr std::array<std::array<int, 8>, 8> kBayer{{
        {0, 32, 8, 40, 2, 34, 10, 42},
        {48, 16, 56, 24, 50, 18, 58, 26},
        {12, 44, 4, 36, 14, 46, 6, 38},
        {60, 28, 52, 20, 62, 30, 54, 22},
        {3, 35, 11, 43, 1, 33, 9, 41},
        {51, 19, 59, 27, 49, 17, 57, 25},
        {15, 47, 7, 39, 13, 45, 5, 37},
        {63, 31, 55, 23, 61, 29, 53, 21},
    }};

    QImage                                      render(const QString &path, const QSize &target) {
        QImage wide(target, QImage::Format_RGBX64);
        wide.fill(Qt::black);
        QPainter painter(&wide);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        if (path.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive)) {
            QSvgRenderer svg(path);
            if (!svg.isValid())
                return {};
            const QSizeF box = svg.viewBoxF().size();
            const QSizeF drawn =
                box * qMax(target.width() / box.width(), target.height() / box.height());
            svg.render(&painter,
                       QRectF(QPointF((target.width() - drawn.width()) / 2,
                                      (target.height() - drawn.height()) / 2),
                              drawn));
        } else {
            QImageReader reader(path);
            reader.setAutoTransform(true);
            const QImage source = reader.read();
            if (source.isNull())
                return {};
            const QSize drawn = source.size().scaled(target, Qt::KeepAspectRatioByExpanding);
            painter.drawImage(QRect(QPoint((target.width() - drawn.width()) / 2,
                                           (target.height() - drawn.height()) / 2),
                                    drawn),
                              source.convertToFormat(QImage::Format_RGBA64));
        }
        return wide;
    }
} // namespace

WallpaperImageProvider::WallpaperImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image,
                          QQmlImageProviderBase::ForceAsynchronousImageLoading) {}

QImage WallpaperImageProvider::dither(const QImage &wide, bool oled) {
    const QImage source = wide.convertToFormat(QImage::Format_RGBX64);
    QImage       out(source.size(), QImage::Format_RGB32);
    for (int y = 0; y < source.height(); ++y) {
        const auto *in   = reinterpret_cast<const QRgba64 *>(source.constScanLine(y));
        auto       *line = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < source.width(); ++x) {
            const double step  = (kBayer[y & 7][x & 7] + 0.5) / 64.0;
            const auto   level = [&](quint16 c) {
                double v = c * 255.0 / 65535.0;
                if (oled)
                    v = qMax(0.0, (v - kFloor) * 255.0 / (255.0 - kFloor));
                return qMin(255, int(std::floor(v + step)));
            };
            line[x] = qRgb(level(in[x].red()), level(in[x].green()), level(in[x].blue()));
        }
    }
    return out;
}

QImage WallpaperImageProvider::requestImage(const QString &id, QSize *size,
                                            const QSize &requested) {
    const qsizetype q      = id.lastIndexOf(QLatin1Char('?'));
    const QString   source = QUrl::fromPercentEncoding((q < 0 ? id : id.left(q)).toUtf8());
    const QUrl      url(source);
    const QString   path = url.isLocalFile() ? url.toLocalFile() : source;
    const bool      oled =
        QUrlQuery(q < 0 ? QString() : id.mid(q + 1)).queryItemValue(QStringLiteral("oled")) ==
        QLatin1String("1");
    const QSize  target = requested.isEmpty() ? QSize(1080, 2340) : requested;
    const QImage wide   = render(path, target);
    if (wide.isNull())
        return {};
    QImage image = dither(wide, oled);
    if (size)
        *size = image.size();
    return image;
}
