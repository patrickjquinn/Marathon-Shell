#include "ambiencederivation.h"

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

    seed.base  = best ? QColor(qRound(best->r / best->count), qRound(best->g / best->count),
                               qRound(best->b / best->count))
                      : QColor(qRound(sumR / pixels), qRound(sumG / pixels), qRound(sumB / pixels));
    seed.light = sumLum / pixels / 255.0 > 0.6;
    return seed;
}
