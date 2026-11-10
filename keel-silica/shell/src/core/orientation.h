// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Orientation helpers. keel-shell's angle convention equals
// QScreen::angleBetween(primaryOrientation, orientation), computed here
// without a QScreen so it can be unit-tested and shared by both backends.

#ifndef KEEL_ORIENTATION_H
#define KEEL_ORIENTATION_H

#include <Qt>

namespace keel {

// Primary must be Portrait or Landscape (phones: Portrait).
int orientationToAngle(Qt::ScreenOrientation orientation, Qt::ScreenOrientation primary);
Qt::ScreenOrientation angleToOrientation(int degrees, Qt::ScreenOrientation primary);

// Angle that Maliit expects over the qt-runner "org.container" interface
// (same table as qt-runner's DBusContainerState::orientationAngle).
int maliitAngle(Qt::ScreenOrientation orientation, bool portraitPrimary);

} // namespace keel

#endif // KEEL_ORIENTATION_H
