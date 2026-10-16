#include "waketouchfilter.h"

#include <QMouseEvent>

WakeTouchFilter::WakeTouchFilter(QObject *parent)
    : QObject(parent) {}

void WakeTouchFilter::setScreenOn(bool on) {
    m_waitForBegin = true;
    if (on)
        m_sinceWake.start();
    else
        m_sinceWake.invalidate();
}

bool WakeTouchFilter::eventFilter(QObject *watched, QEvent *event) {
    if (!m_waitForBegin || !watched->isWindowType() || !event->spontaneous())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
        case QEvent::TouchBegin:
        case QEvent::MouseButtonPress:
            if (m_sinceWake.isValid() && m_sinceWake.elapsed() >= BlockMs) {
                m_waitForBegin = false;
                return QObject::eventFilter(watched, event);
            }
            return true;
        case QEvent::MouseMove:
            // Hover passes; a drag belongs to the press it continues.
            if (static_cast<QMouseEvent *>(event)->buttons() == Qt::NoButton)
                return QObject::eventFilter(watched, event);
            return true;
        case QEvent::TouchUpdate:
        case QEvent::TouchEnd:
        case QEvent::MouseButtonRelease:
        case QEvent::MouseButtonDblClick: return true;
        default: return QObject::eventFilter(watched, event);
    }
}
