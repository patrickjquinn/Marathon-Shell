#include "wakeonkeyfilter.h"

#include <QKeyEvent>

namespace {

    bool isPowerKey(int key) {
        switch (key) {
            case Qt::Key_PowerOff:
            case Qt::Key_PowerDown:
            case Qt::Key_Sleep:
            case Qt::Key_Suspend:
            case Qt::Key_WakeUp: return true;
            default: return false;
        }
    }

    quint32 keyId(const QKeyEvent *e) {
        return e->nativeScanCode() ? e->nativeScanCode() : static_cast<quint32>(e->key());
    }

} // namespace

WakeOnKeyFilter::WakeOnKeyFilter(std::function<bool()> screenOff, std::function<void()> wake,
                                 QObject *parent)
    : QObject(parent)
    , m_screenOff(std::move(screenOff))
    , m_wake(std::move(wake)) {}

bool WakeOnKeyFilter::eventFilter(QObject *watched, QEvent *event) {
    const auto type = event->type();
    if ((type != QEvent::KeyPress && type != QEvent::KeyRelease) || !watched->isWindowType() ||
        !event->spontaneous())
        return QObject::eventFilter(watched, event);

    const auto   *key = static_cast<QKeyEvent *>(event);
    const quint32 id  = keyId(key);

    if (type == QEvent::KeyRelease) {
        if (key->isAutoRepeat())
            return m_swallowed.contains(id);
        return m_swallowed.remove(id);
    }

    if (m_swallowed.contains(id)) {
        if (key->isAutoRepeat())
            return true;
        m_swallowed.remove(id); // release lost, e.g. keyboard unplugged mid-press
    }

    if (isPowerKey(key->key()) || !m_screenOff())
        return QObject::eventFilter(watched, event);

    m_swallowed.insert(id);
    m_wake();
    return true;
}
