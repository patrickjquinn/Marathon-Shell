// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Helpers for the windows keel-shell shows in Lipstick.
//
// Lipstick reads a surface's category once, when the surface is first
// mapped (lipstick src/compositor/lipstickcompositor.cpp, surfaceCategory()
// and createView()), from the qt_extended_surface generic property
// "CATEGORY". The Qt5 Wayland client sends generic properties through
// QPlatformNativeInterface::setWindowProperty() -> QWaylandWindow::
// sendProperty() -> wl-shell surface -> QWaylandExtendedSurface::
// updateGenericProperty(). The shell surface exists as soon as the platform
// window is created, so prepare() creates the window, sets the property and
// only then may the caller show() it (before the first buffer is committed).

#ifndef KEEL_LIPSTICKWINDOW_H
#define KEEL_LIPSTICKWINDOW_H

#include <QString>
#include <QVariant>

#include "surfaceinfo.h"

class QWindow;

namespace keel {

class LipstickWindow
{
public:
    static QString categoryFor(WindowRole role);   // "cover" or empty

    // Sets alpha format, title, the CATEGORY property for covers, creates the
    // platform window and forwards the property. Call before show().
    static void prepare(QWindow *window, WindowRole role, const QString &title);

    // QWindow dynamic property plus the platform (qt_extended_surface)
    // property. Returns false if the platform window does not exist yet.
    static bool setWindowProperty(QWindow *window, const QString &name, const QVariant &value);
};

} // namespace keel

#endif // KEEL_LIPSTICKWINDOW_H
