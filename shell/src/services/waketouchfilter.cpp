#include "waketouchfilter.h"

#include <QMouseEvent>

WakeTouchFilter::WakeTouchFilter(QObject *parent)
    : QObject(parent) {}

void WakeTouchFilter::setScreenOn(bool on) {
    m_screenOn = on;
    if (on)
        m_sinceWake.start();
    else
        m_sinceWake.invalidate();
}

bool WakeTouchFilter::blocksPress() const {
    return !m_screenOn || (m_sinceWake.isValid() && m_sinceWake.elapsed() < BlockMs);
}

bool WakeTouchFilter::eventFilter(QObject *watched, QEvent *event) {
    if (!watched->isWindowType() || !event->spontaneous())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
        case QEvent::TouchBegin:
        case QEvent::MouseButtonPress: m_dropping = blocksPress(); return m_dropping;
        case QEvent::MouseMove:
            // Hover passes; a drag belongs to the press it continues.
            if (static_cast<QMouseEvent *>(event)->buttons() == Qt::NoButton)
                return QObject::eventFilter(watched, event);
            return m_dropping;
        case QEvent::TouchUpdate:
        case QEvent::MouseButtonDblClick: return m_dropping;
        case QEvent::TouchEnd:
        case QEvent::TouchCancel: {
            const bool dropped = m_dropping;
            m_dropping         = false;
            return dropped;
        }
        case QEvent::MouseButtonRelease: {
            const bool dropped = m_dropping;
            if (static_cast<QMouseEvent *>(event)->buttons() == Qt::NoButton)
                m_dropping = false;
            return dropped;
        }
        default: return QObject::eventFilter(watched, event);
    }
}
