#include "src/wayland/symcontrol.h"

#include "src/wayland/keyrouting.h"

#include <QCoreApplication>
#include <QKeyEvent>
#include <QScopedValueRollback>
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
        return false;
    }
    // The Ctrl form comes back through the window's filters.
    if (m_sending)
        return false;
    const int key = keyEvent->key();
    if (!(press && m_symHeld && KeyRouting::symIsControl(key)) && !(m_key != 0 && key == m_key))
        return false;

    QWaylandKeyboardPrivate *keyboard = QWaylandKeyboardPrivate::get(seat->keyboard());
    if (press && m_key == 0) {
        keyboard->updateModifierState(KeyRouting::ControlScanCode, WL_KEYBOARD_KEY_STATE_PRESSED);
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
        keyboard->updateModifierState(KeyRouting::ControlScanCode, WL_KEYBOARD_KEY_STATE_RELEASED);
        m_key = 0;
    }
    return true;
}
