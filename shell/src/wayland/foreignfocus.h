#pragma once

#include "marathon-shell-native/src/foreign_focus.cxxqt.h"

#include <QWaylandSeat>
#include <QWaylandSurface>

namespace ForeignFocus {

    // Waydroid gives Android each touch at display coordinates, for Android's own
    // front task, which only wl_keyboard.enter moves: another app's window
    // mapped behind the front one re-enters the front one. True if it did.
    inline bool keepFront(QWaylandSeat *seat, const QWaylandSurface *mappedBehind) {
        QWaylandSurface *focus = seat ? seat->keyboardFocus() : nullptr;
        if (!focus || !mappedBehind)
            return false;
        if (!marathon::foreign_focus::should_reenter_front(
                focus == mappedBehind, focus->client() == mappedBehind->client(),
                focus->property("foreignClient").toBool(),
                focus->property("appId") == mappedBehind->property("appId")))
            return false;
        seat->setKeyboardFocus(nullptr);
        seat->setKeyboardFocus(focus);
        return true;
    }

} // namespace ForeignFocus
