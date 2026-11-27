#pragma once

#include <QQuickImageProvider>

// image://wallpaper/<percent-encoded path or file URL>[?oled=1]: the wallpaper
// filling the requested size, drawn at 16 bits a channel and dithered once to
// 8, so dark gradients do not band. oled=1 takes the palette's #040404 floor
// to black, so an OLED's pixels there are off.
class WallpaperImageProvider : public QQuickImageProvider {
  public:
    WallpaperImageProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;

    // A 16-bit picture to 8 bits with an 8x8 ordered dither under one step:
    // values 8 bits can hold come out unchanged.
    static QImage dither(const QImage &wide, bool oled);
};
