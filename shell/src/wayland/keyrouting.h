#pragma once

#include <QString>

namespace KeyRouting {

    enum Action : quint8 {
        None,
        Back,
        Home,
        Call,
        End,
        Switcher,
        // Ends a call, else the switcher: the Q25's end key.
        Hangup
    };

    // xkbcommon scan codes are evdev's + 8. Qt has no keys for these, or
    // (KEY_MENU) shares its key with a PC keyboard's menu key.
    inline constexpr quint32 AppSelectScanCode = 580 + 8;
    inline constexpr quint32 MenuScanCode      = 139 + 8;
    inline constexpr quint32 PickupScanCode    = 445 + 8;
    inline constexpr quint32 HangupScanCode    = 446 + 8;
    // A trackpad's click (KEY_SELECT), which apps take as Return (KEY_ENTER).
    inline constexpr quint32 SelectScanCode = 353 + 8;
    inline constexpr quint32 EnterScanCode  = 28 + 8;
    inline constexpr quint32 ReturnKeysym   = 0xff0d;

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
        // The Q25's keys, as its bbqx0kbd driver sends them (pickup, hangup,
        // menu) and as its older driver did (appselect for end, homepage for
        // the menu key).
        if (key == Qt::Key_Call || key == Qt::Key_Send || scanCode == PickupScanCode)
            return Call;
        if (scanCode == HangupScanCode || scanCode == AppSelectScanCode)
            return Hangup;
        if (key == Qt::Key_HomePage || scanCode == MenuScanCode)
            return Home;
        if (key == Qt::Key_Hangup)
            return End;
        return None;
    }

} // namespace KeyRouting
