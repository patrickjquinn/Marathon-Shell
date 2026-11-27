#include "src/wayland/symcontrol.h"

#include "src/wayland/keyrouting.h"

#include <QCoreApplication>
#include <QKeyEvent>
#include <QQuickWindow>
#include <QScopedValueRollback>
#include <QWaylandKeyboard>
#include <QWaylandQuickItem>
#include <QWaylandSeat>
#include <QtWaylandCompositor/private/qwaylandkeyboard_p.h>
#include <wayland-server-protocol.h>

bool SymControl::filter(QObject *watched, QEvent *event, QWaylandSeat *seat) {
    const QEvent::Type type = event->type();
    if (type != QEvent::KeyPress && type != QEvent::KeyRelease)
        return false;
    const auto *keyEvent = static_cast<QKeyEvent *>(event);
    const bool  press    = type == QEvent::KeyPress;
    if (keyEvent->nativeVirtualKey() == KeyRouting::Level5ShiftKeysym) {
        m_symHeld = press;
        m_symCode = keyEvent->nativeScanCode();
        return false;
    }
    // The Ctrl form comes back through the window's filters.
    if (m_sending)
        return false;
    const int key = keyEvent->key();
    if (key == Qt::Key_V &&
        (m_history || (press && m_symHeld && keyEvent->modifiers() & Qt::ShiftModifier))) {
        if (press && !m_history && historyRequested)
            historyRequested();
        m_history = press;
        return true;
    }
    if (!(press && m_symHeld && KeyRouting::symIsControl(key)) && !(m_key != 0 && key == m_key))
        return false;

    QWaylandKeyboard        *keyboard = seat->keyboard();
    QWaylandKeyboardPrivate *state    = QWaylandKeyboardPrivate::get(keyboard);
    if (press && m_key == 0) {
        // Android reads modifiers from the keys themselves, and takes Ctrl+C
        // as copy only without Alt: an app's window gets Sym up and Ctrl down.
        const auto *window = qobject_cast<QQuickWindow *>(watched);
        m_app              = window && qobject_cast<QWaylandQuickItem *>(window->activeFocusItem());
        if (m_app) {
            keyboard->sendKeyReleaseEvent(m_symCode);
            keyboard->sendKeyPressEvent(KeyRouting::ControlScanCode);
        }
        state->updateModifierState(KeyRouting::ControlScanCode, WL_KEYBOARD_KEY_STATE_PRESSED);
        m_key = key;
    }
    QKeyEvent control(type, key, keyEvent->modifiers() | Qt::ControlModifier,
                      keyEvent->nativeScanCode(), keyEvent->nativeVirtualKey(),
                      keyEvent->nativeModifiers(), keyEvent->text(), keyEvent->isAutoRepeat(),
                      keyEvent->count(), keyEvent->device());
    {
        const QScopedValueRollback sending(m_sending, true);
        QCoreApplication::sendEvent(watched, &control);
    }
    if (!press && !keyEvent->isAutoRepeat() && key == m_key) {
        state->updateModifierState(KeyRouting::ControlScanCode, WL_KEYBOARD_KEY_STATE_RELEASED);
        if (m_app) {
            keyboard->sendKeyReleaseEvent(KeyRouting::ControlScanCode);
            if (m_symHeld)
                keyboard->sendKeyPressEvent(m_symCode);
        }
        m_key = 0;
    }
    return true;
}
