#pragma once

#include <QString>

namespace KeyRouting {

    enum Action : quint8 {
        None,
        Back,
        Home,
        Call,
        End,
        Switcher
    };

    // Qt has no key for evdev KEY_APPSELECT; xkbcommon scan codes are evdev's + 8.
    inline constexpr quint32 AppSelectScanCode = 580 + 8;

    // The system action a hardware key triggers before the focused app sees it.
    // Keel apps get Escape: their menus, dialogs and remorse timers use it, and
    // an Escape nothing uses becomes back inside the app. A phone keyboard's
    // call, menu, back and end keys are the system's.
    inline Action systemAction(int key, const QString &focusedToolkit, quint32 scanCode = 0) {
        if (key == Qt::Key_Super_L || key == Qt::Key_Meta)
            return Home;
        if (key == Qt::Key_Escape)
            return focusedToolkit.isEmpty() ? Back : None;
        if (key == Qt::Key_Back)
            return Back;
        if (key == Qt::Key_Call || key == Qt::Key_Send)
            return Call;
        if (key == Qt::Key_Hangup || key == Qt::Key_HomePage)
            return End;
        if (scanCode == AppSelectScanCode)
            return Switcher;
        return None;
    }

} // namespace KeyRouting
