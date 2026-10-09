// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// OpenGL availability for the Lipstick-facing windows.
//
// The Sailfish backend draws its Lipstick windows with Qt Quick. Qt Quick
// 5.6 has only the OpenGL scene graph (no software renderer), and when it
// cannot create an OpenGL context for a window it calls qFatal() unless
// something handles QQuickWindow::sceneGraphError. Under qemu with
// QT_QPA_PLATFORM=minimal, which has no OpenGL, that abort was the
// "crash when the window is shown". keel-shell now checks first and reports
// a clear error instead (see README.md, "Needs device verification").

#ifndef KEEL_GRAPHICS_H
#define KEEL_GRAPHICS_H

#include <QString>

#include "surfaceinfo.h"

namespace keel {

// Empty when the Qt platform plugin can create OpenGL contexts; otherwise a
// one-line explanation naming the plugin. Needs a QGuiApplication.
QString openGLUnavailableReason();

// Error text for QQuickWindow::sceneGraphError on outer window windowId.
QString sceneGraphFailureMessage(int windowId, WindowRole role, const QString &qtMessage);

} // namespace keel

#endif // KEEL_GRAPHICS_H
