// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Surface-to-Lipstick-window mapping. Pure logic, no compositor types.
//
// Rules (see README.md, "Window mapping"):
//  * Window MainWindowId always exists (keel-shell shows it at start-up so the
//    app appears in Lipstick immediately). The first non-cover toplevel is
//    its primary surface.
//  * A toplevel that satisfies CoverPolicy goes into the cover window, which
//    is created on demand and destroyed when its surface goes away. A newer
//    cover surface replaces an older one; the older one is parked.
//  * Every further toplevel gets its own Secondary window (newcompositor
//    behaviour), destroyed when its primary surface goes away.
//  * Transients, popups and subsurfaces go into their parent's window, or
//    into the main window if the parent is unknown.
//  * When a surface's title/app_id/role changes such that its role changes
//    (e.g. the title becomes "keel:cover" after mapping), it and its
//    descendants are moved.
//  * Parked surfaces are placed again whenever a window is freed.

#ifndef KEEL_WINDOWMAPPER_H
#define KEEL_WINDOWMAPPER_H

#include <QHash>
#include <QList>
#include <QMap>
#include <QObject>

#include "coverpolicy.h"
#include "surfaceinfo.h"

namespace keel {

class WindowMapper : public QObject
{
    Q_OBJECT
public:
    enum { MainWindowId = 1 };

    explicit WindowMapper(QObject *parent = nullptr);

    void setCoverPolicy(const CoverPolicy &policy) { m_policy = policy; }
    const CoverPolicy &coverPolicy() const { return m_policy; }

    // When disabled, cover-marked surfaces are treated as secondary toplevels.
    void setCoverEnabled(bool enabled) { m_coverEnabled = enabled; }
    bool coverEnabled() const { return m_coverEnabled; }

    // Returns the window the surface was placed in (0 if parked).
    int mapSurface(SurfaceKey surface, const SurfaceInfo &info);
    // Re-evaluates placement after title/app_id/role/parent changes.
    // No-op for surfaces that are not mapped.
    void updateSurface(SurfaceKey surface, const SurfaceInfo &info);
    void unmapSurface(SurfaceKey surface);

    bool isMapped(SurfaceKey surface) const { return m_surfaces.contains(surface); }
    int windowForSurface(SurfaceKey surface) const;
    SurfaceInfo surfaceInfo(SurfaceKey surface) const;

    QList<int> windows() const { return m_windows.keys(); }
    bool hasWindow(int windowId) const { return m_windows.contains(windowId); }
    WindowRole roleOf(int windowId) const;
    SurfaceKey primarySurface(int windowId) const;
    QList<SurfaceKey> surfacesInWindow(int windowId) const;
    int coverWindow() const;
    QList<SurfaceKey> parkedSurfaces() const;

signals:
    void windowCreated(int windowId, keel::WindowRole role);
    void windowDestroyed(int windowId);
    void surfaceAssigned(keel::SurfaceKey surface, int windowId);
    void surfaceRemoved(keel::SurfaceKey surface, int windowId);

private:
    struct Entry {
        SurfaceInfo info;
        int window = 0;
    };
    struct Window {
        WindowRole role = WindowRole::Secondary;
        SurfaceKey primary = 0;
    };

    void place(SurfaceKey surface, bool fromParked = false);
    void assign(SurfaceKey surface, int windowId);
    void detach(SurfaceKey surface);
    void destroyWindow(int windowId);
    void placeParked();
    QList<SurfaceKey> descendants(SurfaceKey surface) const;
    int createWindow(WindowRole role);

    CoverPolicy m_policy;
    bool m_coverEnabled = true;
    QHash<SurfaceKey, Entry> m_surfaces;
    QList<SurfaceKey> m_order;   // mapping order, for deterministic results
    QMap<int, Window> m_windows;
    int m_nextWindowId = MainWindowId + 1;
};

} // namespace keel

Q_DECLARE_METATYPE(keel::WindowRole)

#endif // KEEL_WINDOWMAPPER_H
