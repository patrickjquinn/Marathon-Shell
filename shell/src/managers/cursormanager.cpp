#include "cursormanager.h"
#include <QCursor>
#include <QDebug>
#include <QGuiApplication>
#include <QInputDevice>
#include <QMouseEvent>

// The shell draws the cursor (MarathonShell.qml), so Qt's eglfs cursor stays
// blank. Only pointer motion shows it, never a key, a click or a touch; it
// goes after hideDelayMs or a touch.
CursorManager::CursorManager(QObject *parent)
    : QObject(parent)
    , m_cursorVisible(false)
    , m_hideDelayMs(2000)
    , m_hideTimer(new QTimer(this)) {

    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &CursorManager::hideCursor);
    QGuiApplication::setOverrideCursor(Qt::BlankCursor);
    qApp->installEventFilter(this);

    qDebug() << "[CursorManager] Initialized with" << m_hideDelayMs << "ms hide delay";
}

CursorManager::~CursorManager() {
    QGuiApplication::restoreOverrideCursor();
}

bool CursorManager::eventFilter(QObject *watched, QEvent *event) {
    switch (event->type()) {
        case QEvent::MouseMove: {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            if (!watched->isWindowType() || mouse->source() != Qt::MouseEventNotSynthesized ||
                mouse->device()->type() != QInputDevice::DeviceType::Mouse)
                break;
            if (m_position != mouse->scenePosition()) {
                m_position = mouse->scenePosition();
                emit positionChanged();
            }
            onMouseActivity();
            break;
        }
        case QEvent::TouchBegin:
            if (watched->isWindowType())
                hideCursor();
            break;
        default: break;
    }
    return QObject::eventFilter(watched, event);
}

void CursorManager::setCursorVisible(bool visible) {
    if (m_cursorVisible == visible)
        return;

    m_cursorVisible = visible;
    emit cursorVisibleChanged();
}

void CursorManager::setHideDelayMs(int ms) {
    if (m_hideDelayMs == ms)
        return;

    m_hideDelayMs = ms;
    emit hideDelayMsChanged();
}

void CursorManager::onMouseActivity() {
    setCursorVisible(true);
    m_hideTimer->start(m_hideDelayMs);
}

void CursorManager::hideCursor() {
    m_hideTimer->stop();
    setCursorVisible(false);
}
