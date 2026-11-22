#pragma once

#include <QGuiApplication>
#include <QInputMethod>

namespace TextInputFocus {

    // Qt 6.11's Wayland input context turns a window's text input off only when
    // the focus window changes or on QInputMethod::update(), so focus leaving a
    // field for another item in the window left it on, and the shell kept
    // taking the app as typing. Drop once Qt has QTBUG-146211's fix.
    inline void follow(QGuiApplication *app) {
        QObject::connect(app, &QGuiApplication::focusObjectChanged, app,
                         [] { QGuiApplication::inputMethod()->update(Qt::ImEnabled); });
    }

} // namespace TextInputFocus
