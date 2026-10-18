#include "toplevelconfigure.h"

#include <QSet>

#ifdef HAVE_WAYLAND_PRIVATE
#include <QtWaylandCompositor/private/qwaylandxdgshell_p.h>
#endif

namespace ToplevelConfigure {
#ifdef HAVE_WAYLAND_PRIVATE
    bool send(QWaylandXdgToplevel *toplevel, const QSize &size,
              const QList<QWaylandXdgToplevel::State> &states) {
        const auto last = QWaylandXdgToplevelPrivate::get(toplevel)->lastSentConfigure();
        if (last.serial != 0 && last.size == size &&
            QSet<QWaylandXdgToplevel::State>(last.states.cbegin(), last.states.cend()) ==
                QSet<QWaylandXdgToplevel::State>(states.cbegin(), states.cend()))
            return false;
        toplevel->sendConfigure(size, states);
        return true;
    }

    bool resize(QWaylandXdgToplevel *toplevel, const QSize &size) {
        QList<QWaylandXdgToplevel::State> states =
            QWaylandXdgToplevelPrivate::get(toplevel)->lastSentConfigure().states;
        if (!states.contains(QWaylandXdgToplevel::MaximizedState))
            states << QWaylandXdgToplevel::MaximizedState;
        return send(toplevel, size, states);
    }

    bool setActivated(QWaylandXdgToplevel *toplevel, bool activated) {
        const auto last   = QWaylandXdgToplevelPrivate::get(toplevel)->lastSentConfigure();
        auto       states = last.states;
        states.removeAll(QWaylandXdgToplevel::ActivatedState);
        if (activated)
            states << QWaylandXdgToplevel::ActivatedState;
        return send(toplevel, last.size, states);
    }

    bool repeat(QWaylandXdgToplevel *toplevel) {
        const auto last = QWaylandXdgToplevelPrivate::get(toplevel)->lastSentConfigure();
        if (last.size.isEmpty())
            return false;
        toplevel->sendConfigure(last.size, last.states);
        return true;
    }

    QSize lastSize(QWaylandXdgToplevel *toplevel) {
        return QWaylandXdgToplevelPrivate::get(toplevel)->lastSentConfigure().size;
    }

    bool settled(QWaylandXdgToplevel *toplevel) {
        return QWaylandXdgToplevelPrivate::get(toplevel)->m_pendingConfigures.isEmpty();
    }
#else
    bool send(QWaylandXdgToplevel *toplevel, const QSize &size,
              const QList<QWaylandXdgToplevel::State> &states) {
        toplevel->sendConfigure(size, states);
        return true;
    }

    bool resize(QWaylandXdgToplevel *toplevel, const QSize &size) {
        QList<QWaylandXdgToplevel::State> states{QWaylandXdgToplevel::MaximizedState};
        if (toplevel->activated())
            states << QWaylandXdgToplevel::ActivatedState;
        return send(toplevel, size, states);
    }

    bool setActivated(QWaylandXdgToplevel *, bool) {
        return false;
    }

    bool repeat(QWaylandXdgToplevel *) {
        return false;
    }

    QSize lastSize(QWaylandXdgToplevel *) {
        return {};
    }

    bool settled(QWaylandXdgToplevel *) {
        return true;
    }
#endif
} // namespace ToplevelConfigure
