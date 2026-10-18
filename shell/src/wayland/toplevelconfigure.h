#pragma once

#include <QList>
#include <QSize>
#include <QWaylandXdgToplevel>

// Configures a toplevel only when that changes what it was last sent. Some
// clients redo their whole display on every sized configure (Waydroid
// hot-plugs Android's display), so a repeat is not free.
namespace ToplevelConfigure {
    bool send(QWaylandXdgToplevel *toplevel, const QSize &size,
              const QList<QWaylandXdgToplevel::State> &states);
    // A new size; the states the toplevel was last sent stay, maximized added.
    bool resize(QWaylandXdgToplevel *toplevel, const QSize &size);
    // Adds or removes "activated", the size kept.
    bool setActivated(QWaylandXdgToplevel *toplevel, bool activated);
    // Sends the last configure again, as a request to redraw; false before any.
    bool repeat(QWaylandXdgToplevel *toplevel);
    // The size last sent, or empty before any.
    QSize lastSize(QWaylandXdgToplevel *toplevel);
    // The client has acked every configure it was sent.
    bool settled(QWaylandXdgToplevel *toplevel);
} // namespace ToplevelConfigure
