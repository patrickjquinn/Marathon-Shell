// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "windowmapper.h"

namespace keel {

WindowMapper::WindowMapper(QObject *parent)
    : QObject(parent)
{
    qRegisterMetaType<keel::WindowRole>("keel::WindowRole");
    qRegisterMetaType<keel::SurfaceKey>("keel::SurfaceKey");
    Window main;
    main.role = WindowRole::Main;
    m_windows.insert(MainWindowId, main);
}

int WindowMapper::windowForSurface(SurfaceKey surface) const
{
    return m_surfaces.value(surface).window;
}

SurfaceInfo WindowMapper::surfaceInfo(SurfaceKey surface) const
{
    return m_surfaces.value(surface).info;
}

WindowRole WindowMapper::roleOf(int windowId) const
{
    return m_windows.value(windowId).role;
}

SurfaceKey WindowMapper::primarySurface(int windowId) const
{
    return m_windows.value(windowId).primary;
}

QList<SurfaceKey> WindowMapper::surfacesInWindow(int windowId) const
{
    QList<SurfaceKey> result;
    for (SurfaceKey key : m_order) {
        if (m_surfaces.value(key).window == windowId)
            result.append(key);
    }
    return result;
}

int WindowMapper::coverWindow() const
{
    for (auto it = m_windows.constBegin(); it != m_windows.constEnd(); ++it) {
        if (it.value().role == WindowRole::Cover)
            return it.key();
    }
    return 0;
}

QList<SurfaceKey> WindowMapper::parkedSurfaces() const
{
    return surfacesInWindow(0);
}

int WindowMapper::createWindow(WindowRole role)
{
    const int id = m_nextWindowId++;
    Window w;
    w.role = role;
    m_windows.insert(id, w);
    emit windowCreated(id, role);
    return id;
}

void WindowMapper::assign(SurfaceKey surface, int windowId)
{
    m_surfaces[surface].window = windowId;
    emit surfaceAssigned(surface, windowId);
}

int WindowMapper::mapSurface(SurfaceKey surface, const SurfaceInfo &info)
{
    if (!surface)
        return 0;
    if (m_surfaces.contains(surface)) {
        updateSurface(surface, info);
        return windowForSurface(surface);
    }
    Entry e;
    e.info = info;
    m_surfaces.insert(surface, e);
    m_order.append(surface);
    place(surface);
    // Children that were mapped before this parent (and parked or put in the
    // main window) now follow it.
    const int w = windowForSurface(surface);
    for (SurfaceKey k : descendants(surface)) {
        const int cw = m_surfaces.value(k).window;
        if (cw == w)
            continue;
        if (cw) {
            m_surfaces[k].window = 0;
            emit surfaceRemoved(k, cw);
        }
        place(k);
    }
    return w;
}

void WindowMapper::place(SurfaceKey surface, bool fromParked)
{
    const SurfaceInfo info = m_surfaces.value(surface).info;

    if (info.isChild()) {
        int target = MainWindowId;
        if (info.parent && info.parent != surface && m_surfaces.contains(info.parent)) {
            const int parentWindow = m_surfaces.value(info.parent).window;
            if (parentWindow)
                target = parentWindow;
            else
                target = 0;   // parent is parked: park the child with it
        }
        if (target)
            assign(surface, target);
        return;
    }

    if (m_coverEnabled && m_policy.isCover(info)) {
        int cover = coverWindow();
        if (cover) {
            const SurfaceKey old = m_windows.value(cover).primary;
            if (fromParked && old && old != surface)
                return;   // an active cover exists; stay parked
            if (old && old != surface) {
                // Newest cover wins; park the old one and its children.
                const QList<SurfaceKey> oldTree = QList<SurfaceKey>() << old << descendants(old);
                for (SurfaceKey k : oldTree) {
                    if (m_surfaces.value(k).window == cover) {
                        m_surfaces[k].window = 0;
                        emit surfaceRemoved(k, cover);
                    }
                }
            }
        } else {
            cover = createWindow(WindowRole::Cover);
        }
        m_windows[cover].primary = surface;
        assign(surface, cover);
        return;
    }

    if (!m_windows.value(MainWindowId).primary) {
        m_windows[MainWindowId].primary = surface;
        assign(surface, MainWindowId);
        return;
    }

    const int id = createWindow(WindowRole::Secondary);
    m_windows[id].primary = surface;
    assign(surface, id);
}

QList<SurfaceKey> WindowMapper::descendants(SurfaceKey surface) const
{
    QList<SurfaceKey> result;
    QList<SurfaceKey> frontier;
    frontier << surface;
    while (!frontier.isEmpty()) {
        const SurfaceKey current = frontier.takeFirst();
        for (SurfaceKey key : m_order) {
            const Entry &e = m_surfaces[key];
            if (key != surface && e.info.isChild() && e.info.parent == current
                    && !result.contains(key)) {
                result.append(key);
                frontier.append(key);
            }
        }
    }
    return result;
}

void WindowMapper::detach(SurfaceKey surface)
{
    const int windowId = m_surfaces.value(surface).window;
    if (!windowId)
        return;
    m_surfaces[surface].window = 0;
    emit surfaceRemoved(surface, windowId);

    Window &w = m_windows[windowId];
    if (w.primary == surface) {
        w.primary = 0;
        if (w.role != WindowRole::Main)
            destroyWindow(windowId);
    }
}

void WindowMapper::destroyWindow(int windowId)
{
    if (windowId == MainWindowId || !m_windows.contains(windowId))
        return;
    for (SurfaceKey key : m_order) {
        if (m_surfaces.value(key).window == windowId) {
            m_surfaces[key].window = 0;
            emit surfaceRemoved(key, windowId);
        }
    }
    m_windows.remove(windowId);
    emit windowDestroyed(windowId);
}

void WindowMapper::placeParked()
{
    // Toplevels first (in mapping order), then children so that they can
    // follow a parent that was just placed.
    bool progress = true;
    while (progress) {
        progress = false;
        for (SurfaceKey key : m_order) {
            const Entry &e = m_surfaces[key];
            if (e.window || e.info.isChild())
                continue;
            place(key, true);
            if (m_surfaces.value(key).window)
                progress = true;
        }
        for (SurfaceKey key : m_order) {
            const Entry &e = m_surfaces[key];
            if (e.window || !e.info.isChild())
                continue;
            if (e.info.parent && (!m_surfaces.contains(e.info.parent)
                                  || !m_surfaces.value(e.info.parent).window))
                continue;   // parent gone or still parked: stay parked
            place(key, true);
            if (m_surfaces.value(key).window)
                progress = true;
        }
    }
}

void WindowMapper::updateSurface(SurfaceKey surface, const SurfaceInfo &info)
{
    if (!m_surfaces.contains(surface))
        return;

    const Entry old = m_surfaces.value(surface);
    const bool wasCover = old.window && roleOf(old.window) == WindowRole::Cover
            && primarySurface(old.window) == surface;
    const bool nowCover = m_coverEnabled && m_policy.isCover(info);
    const bool structural = old.info.kind != info.kind || old.info.parent != info.parent
            || old.info.isChild() != info.isChild();

    m_surfaces[surface].info = info;

    if (!structural && wasCover == nowCover && old.window)
        return;

    // Move the surface and everything hanging off it.
    const QList<SurfaceKey> tree = descendants(surface);
    for (SurfaceKey k : tree) {
        const int w = m_surfaces.value(k).window;
        if (w) {
            m_surfaces[k].window = 0;
            emit surfaceRemoved(k, w);
        }
    }
    detach(surface);
    place(surface);
    for (SurfaceKey k : tree) {
        if (!m_surfaces.value(k).window)
            place(k);
    }
    placeParked();
}

void WindowMapper::unmapSurface(SurfaceKey surface)
{
    if (!m_surfaces.contains(surface))
        return;
    detach(surface);
    m_surfaces.remove(surface);
    m_order.removeAll(surface);
    placeParked();
}

} // namespace keel
