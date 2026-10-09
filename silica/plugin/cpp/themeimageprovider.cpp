// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "themeimageprovider.h"

#include "keeldconf.h"

#include <QConicalGradient>
#include <QPen>

#include <QColor>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QLoggingCategory>
#include <QPainter>

Q_LOGGING_CATEGORY(lcKeelIcons, "keel.icons")

KeelThemeImageProvider::KeelThemeImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
    bool ok = false;
    double ratio = qEnvironmentVariable("KEEL_THEME_PIXEL_RATIO").toDouble(&ok);
    // The phone's ratio from the start, so that the first icons are looked up
    // in the right z<ratio> directory before Keel.Ambience exists (the
    // directories differ per ratio: z1.0 has no camera icons on a z1.5
    // phone).
    if (!ok)
        ratio = keel::dconf::read(QStringLiteral("/desktop/sailfish/silica/theme_pixel_ratio")).toDouble(&ok);
    setPixelRatio(ok ? ratio : 1.0);
}

static QString ratioDir(double ratio)
{
    if (ratio <= 0)
        ratio = 1.0;
    // "1.0", "1.25", "1.5", "1.75", "2.0": the theme's z<ratio> directories.
    QString s = QString::number(ratio, 'f', 2);
    if (s.endsWith(QLatin1Char('0')))
        s.chop(1);
    return QStringLiteral("z") + s;
}

QStringList KeelThemeImageProvider::searchDirectories() const
{
    QStringList dirs;
    const QString extra = qEnvironmentVariable("KEEL_THEME_ICON_DIRS");
    for (const QString &d : extra.split(QLatin1Char(':'), Qt::SkipEmptyParts))
        dirs << d;
    const QString z = ratioDir(m_ratio.load());
    dirs << QStringLiteral("/usr/share/themes/sailfish-default/silica/%1/icons").arg(z)
         << QStringLiteral("/usr/share/themes/sailfish-default/silica/%1/icons-monochrome").arg(z)
         << QStringLiteral("/usr/share/themes/sailfish-default/meegotouch/%1/icons").arg(z)
         << QStringLiteral("/usr/share/icons/hicolor/scalable/apps")
         << QStringLiteral("/usr/share/icons/hicolor/128x128/apps");
    return dirs;
}

QString KeelThemeImageProvider::findIcon(const QString &name) const
{
    if (name.isEmpty() || name.contains(QLatin1String("..")))
        return QString();
    for (const QString &dir : searchDirectories()) {
        for (const char *ext : {".png", ".svg"}) {
            const QString path = dir + QLatin1Char('/') + name + QLatin1String(ext);
            if (QFileInfo::exists(path))
                return path;
        }
    }
    return QString();
}

QString KeelThemeImageProvider::resolveAlias(const QString &name) const
{
    if (!findIcon(name).isEmpty())
        return name;
    // Sailfish themes ship some icons (file types, weather) only as colour
    // scheme variants: <name>-dark for a dark ambience, <name>-light for a
    // light one.
    const auto variant = [this](const QString &n) -> QString {
        const QString v = n + (m_lightScheme.load() ? QStringLiteral("-light") : QStringLiteral("-dark"));
        return findIcon(v).isEmpty() ? QString() : v;
    };
    QString v = variant(name);
    if (!v.isEmpty())
        return v;
    // Icons that a theme lacks, mapped to icons it has, so a file picker or
    // an attachment never shows a blank (Keel's choice of substitutes).
    static const struct { const char *name; const char *fallback; } kAliases[] = {
        { "icon-m-file-pdf", "icon-m-file-document" },
        { "icon-m-file-formatted", "icon-m-file-document" },
        { "icon-m-file-note", "icon-m-file-document" },
        { "icon-m-file-spreadsheet", "icon-m-file-document" },
        { "icon-m-file-presentation", "icon-m-file-document" },
        { "icon-m-file-document", "icon-m-file-other" },
        { "icon-m-file-other", "icon-m-document" },
        { "icon-m-file-archive", "icon-m-file-compressed" },
        { "icon-m-file-compressed", "icon-m-file-other" },
        { "icon-m-file-image", "icon-m-image" },
        { "icon-m-file-audio", "icon-m-music" },
        { "icon-m-file-video", "icon-m-video" },
        { "icon-m-file-folder", "icon-m-folder" },
        { "icon-l-video", "icon-m-video" },
        { "icon-l-image", "icon-m-image" },
        { "icon-l-document", "icon-m-document" },
        { "icon-l-music", "icon-m-music" },
    };
    QString current = name;
    // Follow the chain (a substitute may itself be missing), a few hops.
    for (int hop = 0; hop < 4; ++hop) {
        QString next;
        for (const auto &a : kAliases) {
            if (current == QLatin1String(a.name)) {
                next = QLatin1String(a.fallback);
                break;
            }
        }
        if (next.isEmpty())
            return name;
        if (!findIcon(next).isEmpty())
            return next;
        v = variant(next);
        if (!v.isEmpty())
            return v;
        current = next;
    }
    return name;
}

bool KeelThemeImageProvider::isMonochrome(const QImage &image)
{
    // A monochrome (single colour, shaded by alpha only) icon: every visible
    // pixel is a shade of grey. Sailfish's monochrome icons are white.
    if (image.isNull())
        return false;
    const QImage img = image.convertToFormat(QImage::Format_ARGB32);
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb c = line[x];
            if (qAlpha(c) < 16)
                continue;
            const int r = qRed(c), g = qGreen(c), b = qBlue(c);
            if (qAbs(r - g) > 24 || qAbs(g - b) > 24 || qAbs(r - b) > 24)
                return false;
        }
    }
    return true;
}

QImage KeelThemeImageProvider::standIn(const QString &name) const
{
    // Keel's Theme base sizes (plugin/cpp/theme.h) at pixelRatio 1.0.
    static const struct { const char *prefix; int size; } kIconSizes[] = {
        { "icon-xs-", 24 }, { "icon-splus-", 48 }, { "icon-s-", 32 }, { "icon-m-", 64 },
        { "icon-l-", 96 }, { "icon-launcher", 86 }, { "icon-cover-", 32 },
    };
    static const struct { const char *suffix; int size; } kBusySizes[] = {
        { "extra-small", 24 }, { "small", 32 }, { "medium", 64 }, { "large", 96 },
    };
    const QString busy = QStringLiteral("graphic-busyindicator-");
    if (name.startsWith(busy)) {
        const QString which = name.mid(busy.size());
        for (const auto &b : kBusySizes) {
            if (which == QLatin1String(b.suffix)) {
                const int px = qRound(b.size * m_ratio.load());
                QImage img(px, px, QImage::Format_ARGB32_Premultiplied);
                img.fill(Qt::transparent);
                QPainter p(&img);
                p.setRenderHint(QPainter::Antialiasing);
                const qreal pen = qMax<qreal>(1.5, px / 16.0);
                const QRectF r(pen, pen, px - 2 * pen, px - 2 * pen);
                // A ring that fades out over three quarters of a turn.
                QConicalGradient g(r.center(), 90);
                g.setColorAt(0.0, QColor(255, 255, 255, 255));
                g.setColorAt(0.75, QColor(255, 255, 255, 0));
                g.setColorAt(1.0, QColor(255, 255, 255, 0));
                p.setPen(QPen(QBrush(g), pen, Qt::SolidLine, Qt::RoundCap));
                p.drawArc(r, 90 * 16, 270 * 16);
                return img;
            }
        }
        return QImage();
    }
    for (const auto &s : kIconSizes) {
        if (name.startsWith(QLatin1String(s.prefix))) {
            const int px = qRound(s.size * m_ratio.load());
            QImage img(px, px, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            return img;
        }
    }
    return QImage();
}

QImage KeelThemeImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QString name = id;
    QColor tint;
    bool monochromeOnly = false;
    const int q = id.indexOf(QLatin1Char('?'));
    if (q >= 0) {
        name = id.left(q);
        QString arg = id.mid(q + 1);
        if (arg.startsWith(QLatin1String("mono="))) {
            monochromeOnly = true;
            arg = arg.mid(5);
        }
        tint = QColor(arg);
    }

    QImage image;
    const QString resolved = resolveAlias(name);
    const QString path = findIcon(resolved);
    if (!path.isEmpty()) {
        QImageReader reader(path);
        if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0)
            reader.setScaledSize(requestedSize);
        image = reader.read();
        // A substitute of another size class (icon-l-video drawn with
        // icon-m-video) is scaled to the size asked for.
        if (!image.isNull() && resolved != name && !requestedSize.isValid()) {
            const QImage want = standIn(name);
            if (!want.isNull() && want.size() != image.size())
                image = image.scaled(want.size(), Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
    }
    if (image.isNull()) {
        {
            QMutexLocker lock(&m_mutex);
            if (!m_warned.contains(name)) {
                m_warned.insert(name);
                qCInfo(lcKeelIcons) << "theme icon not found:" << name;
            }
        }
        image = standIn(name);
        if (image.isNull()) {
            const int w = requestedSize.width() > 0 ? requestedSize.width() : 1;
            const int h = requestedSize.height() > 0 ? requestedSize.height() : 1;
            image = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::transparent);
        } else if (requestedSize.width() > 0 && requestedSize.height() > 0) {
            image = image.scaled(requestedSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        }
    }
    if (monochromeOnly && tint.isValid() && !isMonochrome(image))
        tint = QColor();
    if (tint.isValid() && !image.isNull()) {
        image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        QPainter p(&image);
        p.setCompositionMode(QPainter::CompositionMode_SourceIn);
        p.fillRect(image.rect(), tint);
    }
    if (size)
        *size = image.size();
    return image;
}
