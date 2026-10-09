// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-FileCopyrightText: 2020 Rinigus https://github.com/rinigus
// SPDX-License-Identifier: MIT AND BSD-3-Clause
// maliitAngle() reproduces a table from qt-runner (BSD-3-Clause), see PROVENANCE.md.

#include "orientation.h"

#include "shellstate.h"

namespace keel {

static int orientationIndex(Qt::ScreenOrientation o)
{
    switch (o) {
    case Qt::PortraitOrientation: return 0;
    case Qt::LandscapeOrientation: return 1;
    case Qt::InvertedPortraitOrientation: return 2;
    case Qt::InvertedLandscapeOrientation: return 3;
    default: return -1;
    }
}

int orientationToAngle(Qt::ScreenOrientation orientation, Qt::ScreenOrientation primary)
{
    if (orientation == Qt::PrimaryOrientation)
        return 0;
    const int ia = orientationIndex(primary);
    const int ib = orientationIndex(orientation);
    if (ia < 0 || ib < 0)
        return 0;
    // Mirrors QPlatformScreen::angleBetween().
    int delta = ia - ib;
    if (delta < 0)
        delta += 4;
    return delta * 90;
}

Qt::ScreenOrientation angleToOrientation(int degrees, Qt::ScreenOrientation primary)
{
    const int a = ShellState::normalizeAngle(degrees);
    const Qt::ScreenOrientation all[] = { Qt::PortraitOrientation, Qt::LandscapeOrientation,
                                          Qt::InvertedPortraitOrientation,
                                          Qt::InvertedLandscapeOrientation };
    for (Qt::ScreenOrientation o : all) {
        if (orientationToAngle(o, primary) == a)
            return o;
    }
    return primary;
}

int maliitAngle(Qt::ScreenOrientation orientation, bool portraitPrimary)
{
    // Table from qt-runner src/dbuscontainerstate.cpp (BSD-3-Clause,
    // Copyright 2020 Rinigus), itself from Maliit's minputcontext.cpp.
    switch (orientation) {
    case Qt::PrimaryOrientation:
    case Qt::PortraitOrientation:
        return portraitPrimary ? 0 : 270;
    case Qt::LandscapeOrientation:
        return portraitPrimary ? 90 : 0;
    case Qt::InvertedPortraitOrientation:
        return portraitPrimary ? 180 : 90;
    case Qt::InvertedLandscapeOrientation:
        return portraitPrimary ? 270 : 180;
    }
    return 0;
}

} // namespace keel
