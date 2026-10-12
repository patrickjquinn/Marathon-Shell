#pragma once

#include <QColor>
#include <QImage>
#include <QString>

struct AmbienceSeed {
    QColor base;
    bool   light = false;
};

// The colour an ambience is built from, as Sailfish derives one from a
// wallpaper: the most saturated well-populated hue, else the mean colour.
AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper);

// The highlight chosen for one of Marathon's own wallpapers, by file name;
// invalid for any other wallpaper.
QColor bundledHighlight(const QString &wallpaperPath);
