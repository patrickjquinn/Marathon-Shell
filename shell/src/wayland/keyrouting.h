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

    inline constexpr quint32 ControlScanCode   = 29 + 8;
    inline constexpr quint32 Level5ShiftKeysym = 0xfe11;

    // The Q25 has no Ctrl key. Its Sym key (ISO_Level5_Shift) is Ctrl for
    // the letters with no Sym legend that edit text: select all, copy, paste,
    // cut and undo.
    inline bool symIsControl(int key) {
        return key == Qt::Key_A || key == Qt::Key_C || key == Qt::Key_V || key == Qt::Key_X ||
            key == Qt::Key_Z;
    }

    // A key a touchscreen reports beside its touch (the MP01's under the
    // panel), as the Qt key libinput would give; -1 for buttons (BTN_*).
    inline int touchscreenKey(quint16 code) {
        if (code == 158)
            return Qt::Key_Back;
        if (code == 172)
            return Qt::Key_HomePage;
        const bool button =
            (code >= 0x100 && code < 0x160) || (code >= 0x220 && code < 0x224) || code >= 0x2c0;
        return button ? -1 : 0;
    }

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
        // menu) and as its older driver did (homepage for the menu key).
        if (key == Qt::Key_Call || key == Qt::Key_Send || scanCode == PickupScanCode)
            return Call;
        if (scanCode == HangupScanCode)
            return Hangup;
        // Recents, as the MP01's keys under the screen send it.
        if (scanCode == AppSelectScanCode)
            return Switcher;
        if (key == Qt::Key_HomePage || scanCode == MenuScanCode)
            return Home;
        if (key == Qt::Key_Hangup)
            return End;
        return None;
    }

    // A shortcut held with Super, from an external keyboard; empty if none.
    inline QString superShortcut(int key) {
        switch (key) {
            case Qt::Key_Space: return QStringLiteral("search");
            case Qt::Key_Tab: return QStringLiteral("switcher");
            case Qt::Key_L: return QStringLiteral("lock");
            case Qt::Key_A: return QStringLiteral("quicksettings");
            case Qt::Key_Q: return QStringLiteral("close");
            case Qt::Key_K: return QStringLiteral("keyboard");
            default: return {};
        }
    }

} // namespace KeyRouting
