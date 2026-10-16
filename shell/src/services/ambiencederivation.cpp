#include "ambiencederivation.h"

#include <QFileInfo>
#include <QHash>

#include <array>

AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper) {
    AmbienceSeed seed;
    if (wallpaper.isNull())
        return seed;

    const QImage img = wallpaper.scaled(64, 64, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                           .convertToFormat(QImage::Format_RGB32);

    constexpr int kBuckets = 12;
    struct Bucket {
        double weight = 0;
        double r = 0, g = 0, b = 0;
        int    count = 0;
    };
    std::array<Bucket, kBuckets> buckets{};
    double                       sumR = 0, sumG = 0, sumB = 0, sumLum = 0;
    const int                    pixels = img.width() * img.height();

    for (int y = 0; y < img.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QColor c = QColor::fromRgb(line[x]);
            sumR += c.red();
            sumG += c.green();
            sumB += c.blue();
            sumLum += 0.2126 * c.red() + 0.7152 * c.green() + 0.0722 * c.blue();
            const double s = c.hsvSaturationF();
            const double v = c.valueF();
            if (s < 0.25 || v < 0.15 || c.hsvHue() < 0)
                continue;
            Bucket &bk = buckets[c.hsvHue() * kBuckets / 360];
            bk.weight += s;
            bk.r += c.red();
            bk.g += c.green();
            bk.b += c.blue();
            ++bk.count;
        }
    }

    const Bucket *best = nullptr;
    for (const Bucket &bk : buckets)
        if (bk.count >= pixels / 20 && (!best || bk.weight > best->weight))
            best = &bk;

    const QColor dominant = best ? QColor(qRound(best->r / best->count), qRound(best->g / best->count),
                                          qRound(best->b / best->count))
                                 : QColor(qRound(sumR / pixels), qRound(sumG / pixels), qRound(sumB / pixels));
    seed.light = sumLum / pixels / 255.0 > 0.6;

    // The wallpaper's hue as a restrained highlight: a light pastel on a
    // dark ambience, a deep quiet tone on a light one. A grey wallpaper
    // keeps a near-neutral highlight.
    const qreal hue    = qMax<qreal>(0, dominant.hsvHueF());
    const bool  greyed = !best;
    if (seed.light)
        seed.base = QColor::fromHsvF(hue, greyed ? 0.1 : 0.65, 0.5);
    else
        seed.base = QColor::fromHsvF(hue, greyed ? 0.06 : 0.32, 1.0);
    return seed;
}

QColor bundledHighlight(const QString &wallpaperPath) {
    // Each picks up its wallpaper's accent, which is Marathon teal on all of
    // them; Tundra leans to its sky, Dawn to its warmer glow.
    static const QHash<QString, QColor> highlights = {
        {QStringLiteral("aurora-myvatn"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("slate-aurora"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("long-run"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("carbon"), QColor(0x7d, 0xe6, 0xcf)},
        {QStringLiteral("indigo-dusk"), QColor(0x84, 0xe8, 0xda)},
        {QStringLiteral("track"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("mesh"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("contour"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("stride"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("tundra"), QColor(0x88, 0xe3, 0xea)},
        {QStringLiteral("striae"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("halftone"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("pulse"), QColor(0x7d, 0xf0, 0xd4)},
        {QStringLiteral("dawn"), QColor(0xa3, 0xee, 0xc9)},
    };
    const QFileInfo info(wallpaperPath);
    if (!wallpaperPath.contains(QLatin1String("wallpapers/")))
        return {};
    return highlights.value(info.completeBaseName());
}
