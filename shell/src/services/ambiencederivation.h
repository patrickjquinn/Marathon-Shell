#pragma once

#include <QColor>
#include <QImage>

struct AmbienceSeed {
    QColor base;
    bool   light = false;
};

// The colour an ambience is built from, as Sailfish derives one from a
// wallpaper: the most saturated well-populated hue, else the mean colour.
AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper);
