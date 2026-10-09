// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// "image://theme/<name>[?<color>]" provider, as documented for Silica
// (Theme docs, "Icon usage"): platform icons by name, optionally recoloured
// by appending "?<color>" for monochrome icons. "?mono=<color>" recolours
// only monochrome icons (all grey) and leaves colour ones as they are: what
// Keel's HighlightImage/Icon ask for in a light ambience, where Sailfish's
// white monochrome icons are drawn in the ambience's primary colour.
//
// Clean-room. Lookup order for <name>.png / <name>.svg:
//   1. every directory in KEEL_THEME_ICON_DIRS (colon-separated)
//   2. /usr/share/themes/sailfish-default/silica/z<ratio>/icons, then
//      .../icons-monochrome (Sailfish OS 4/5 keep most icon-* there)
//   3. /usr/share/themes/sailfish-default/meegotouch/z<ratio>/icons
//   4. the freedesktop hicolor theme under /usr/share/icons
// where <ratio> is Theme.pixelRatio formatted like "1.0", "1.5", "2.0". If
// nothing is found Keel draws a stand-in, so apps keep working without the
// Sailfish icon theme (and log one message per missing name): a transparent
// image as large as the icon's size class (icon-xs/s/splus/m/l, launcher),
// a busy-indicator ring for graphic-busyindicator-*, otherwise a transparent
// image of the requested size. Sizes are Keel's Theme base sizes times
// setPixelRatio().
#ifndef KEEL_THEMEIMAGEPROVIDER_H
#define KEEL_THEMEIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QSet>
#include <QStringList>
#include <QMutex>

#include <atomic>

class KeelThemeImageProvider : public QQuickImageProvider
{
public:
    KeelThemeImageProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    // Exposed for tests.
    QStringList searchDirectories() const;
    QString findIcon(const QString &name) const;
    // The theme's pixel ratio: stand-in sizes and the z<ratio> directories.
    // The plugin follows Keel.Ambience's (dconf's theme_pixel_ratio on a
    // phone); KEEL_THEME_PIXEL_RATIO until then.
    void setPixelRatio(qreal ratio) { m_ratio.store(ratio > 0 ? ratio : 1.0); }
    qreal pixelRatio() const { return m_ratio.load(); }
    // The ambience's colour scheme (Keel.Ambience.colorScheme), followed by
    // the plugin; requests come from image loader threads.
    void setLightScheme(bool light) { m_lightScheme.store(light); }
    // <name>; else its colour scheme variant (<name>-dark in a dark
    // ambience, <name>-light in a light one); else the icon Keel substitutes
    // when the theme lacks <name> (icon-l-video -> icon-m-video, ...).
    QString resolveAlias(const QString &name) const;
    // Whether every visible pixel of the image is grey (a monochrome icon).
    static bool isMonochrome(const QImage &image);
    // The stand-in for a missing <name> (null: none, use the requested size).
    QImage standIn(const QString &name) const;

private:
    QMutex m_mutex;
    QSet<QString> m_warned;
    std::atomic<double> m_ratio { 1.0 };
    std::atomic<bool> m_lightScheme { false };
};

#endif // KEEL_THEMEIMAGEPROVIDER_H
