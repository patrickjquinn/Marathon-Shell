// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Compositor-API-neutral description of a nested client surface. Both
// backends (Qt 5.6 QtCompositor on Sailfish, Qt 5.15 QtWaylandCompositor on
// the host) translate their surface objects into this struct so that the
// mapping and cover logic in core/ is shared and unit-tested.

#ifndef KEEL_SURFACEINFO_H
#define KEEL_SURFACEINFO_H

#include <QString>
#include <QtGlobal>

namespace keel {

// Opaque surface identity. Backends use the address of their surface object.
using SurfaceKey = quintptr;

enum class SurfaceKind {
    Unknown,     // no shell role yet
    Toplevel,    // wl_shell_surface.set_toplevel / xdg_toplevel
    Transient,   // wl_shell_surface.set_transient / xdg_toplevel with parent
    Popup,       // wl_shell_surface.set_popup / xdg_popup
    SubSurface   // wl_subsurface
};

struct SurfaceInfo {
    QString title;           // wl_shell_surface.set_title / xdg_toplevel.set_title
    QString appId;           // wl_shell_surface.set_class / xdg_toplevel.set_app_id
    SurfaceKind kind = SurfaceKind::Toplevel;
    SurfaceKey parent = 0;   // transient parent, popup parent or subsurface parent

    bool isChild() const
    {
        return kind == SurfaceKind::Transient || kind == SurfaceKind::Popup
                || kind == SurfaceKind::SubSurface;
    }
};

enum class WindowRole {
    Main,       // the app window Lipstick shows full screen
    Cover,      // second Lipstick window, CATEGORY=cover
    Secondary   // any further toplevel (newcompositor-style multi-window)
};

QString windowRoleName(WindowRole role);

} // namespace keel

#endif // KEEL_SURFACEINFO_H
