#pragma once

#include <QByteArray>
#include <QRegion>
#include <QSize>

// System back for a native Wayland app, which cannot answer it. See
// docs/NATIVE_APP_LIFECYCLE.md for where each toolkit handles back.
namespace NativeBack {

    enum Toolkit : quint8 {
        Unknown,
        Gtk3,
        Gtk4,
        Adwaita,
        QtApp
    };

    // The toolkit linked into a client, from its /proc/<pid>/maps. Qt before
    // GTK 3: Qt's gtk3 platform theme loads libgtk-3 into Qt apps.
    inline Toolkit toolkitFromMaps(const QByteArray &maps) {
        if (maps.contains("/libadwaita-1.so"))
            return Adwaita;
        if (maps.contains("/libgtk-4.so"))
            return Gtk4;
        if (maps.contains("/libQt6Core.so") || maps.contains("/libQt5Core.so"))
            return QtApp;
        if (maps.contains("/libgtk-3.so"))
            return Gtk3;
        return Unknown;
    }

    // XF86Back is the native navigation key across libadwaita, Kirigami and
    // browsers. Keel uses Escape for its in-process page stack.
    inline int backKey(Toolkit toolkit, bool keelHosted) {
        if (keelHosted)
            return Qt::Key_Escape;
        return Qt::Key_Back;
    }

    // Some GTK apps only wire Escape for an in-window dialog/search and some
    // Qt/browser stacks only wire Alt+Left. Retry one standard shortcut when
    // XF86Back produces no visible change.
    inline int fallbackBackKey(Toolkit toolkit) {
        return toolkit == Gtk4 || toolkit == Adwaita ? Qt::Key_Escape : Qt::Key_Left;
    }

    inline Qt::KeyboardModifiers fallbackBackModifiers(Toolkit toolkit) {
        return toolkit == Gtk4 || toolkit == Adwaita ? Qt::NoModifier : Qt::AltModifier;
    }

    // How long a back has to show its effect before it counts as unhandled.
    constexpr int kWatchMs = 350;

    // A page, dialog or search bar going away repaints a tenth of the window
    // or more; a spinner, a blinking cursor or a level meter does not.
    inline bool visibleChange(const QRegion &damage, const QSize &surfaceSize) {
        if (surfaceSize.isEmpty())
            return false;
        const qreal area    = qreal(surfaceSize.width()) * surfaceSize.height();
        qreal       damaged = 0;
        for (const QRect &r : damage)
            damaged += qreal(r.width()) * r.height();
        return damaged >= area / 10;
    }

} // namespace NativeBack
