#pragma once

#include <QString>

namespace KeyRouting {

enum Action { None, Back, Home };

// The system action a hardware key triggers before the focused app sees it.
// Keel apps get Escape: their menus, dialogs and remorse timers use it, and
// an Escape nothing uses becomes back inside the app.
inline Action systemAction(int key, const QString &focusedToolkit) {
    if (key == Qt::Key_Super_L || key == Qt::Key_Meta)
        return Home;
    if (key == Qt::Key_Escape)
        return focusedToolkit.isEmpty() || focusedToolkit == QLatin1String("marathonui") ? Back : None;
    return None;
}

} // namespace KeyRouting
