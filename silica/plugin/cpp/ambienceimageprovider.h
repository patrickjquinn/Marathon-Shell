// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// "image://keelambience/<url>?w=<width>&h=<height>" provider: the ambience
// wallpaper at <url> (file path, file: or qrc: URL) cropped to the aspect
// ratio of a <width> x <height> window, centred and filling it, and blurred
// as Sailfish's compositor blurs the wallpaper behind application windows.
// The image comes back at an eighth of the window size; the window scales it
// up (smoothly: the blur hides the scaling).
//
// Keel's ApplicationWindow draws it when no compositor does (desktop,
// offscreen screenshots); on a phone Lipstick draws the ambience itself.
// Clean-room: the blur radius (7.5% of the window width) was fitted to
// published Sailfish OS 4 screenshots of the stock "water" ambience
// (keel/silica/tests/screenshots/reference/SOURCES.md).
#ifndef KEEL_AMBIENCEIMAGEPROVIDER_H
#define KEEL_AMBIENCEIMAGEPROVIDER_H

#include <QQuickImageProvider>

class KeelAmbienceImageProvider : public QQuickImageProvider
{
public:
    KeelAmbienceImageProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    // Exposed for tests: crops `source` to `window`'s aspect ratio and
    // returns it blurred at an eighth of `window`.
    static QImage process(const QImage &source, const QSize &window);
    // In-place blur with three box passes of `radius` (a Gaussian
    // approximation), horizontally and vertically.
    static void boxBlur(QImage &image, int radius);
};

#endif
