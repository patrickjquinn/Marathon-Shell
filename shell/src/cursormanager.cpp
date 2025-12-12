#include "cursormanager.h"
#include <QGuiApplication>
#include <QCursor>
#include <QDebug>

CursorManager::CursorManager(QObject *parent)
    : QObject(parent)
    , m_cursorVisible(true)
    , m_hideDelayMs(2000) // 2 seconds default
    , m_hideTimer(new QTimer(this))
    , m_overrideActive(false) {

    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &CursorManager::hideCursor);

    qDebug() << "[CursorManager] Initialized with" << m_hideDelayMs << "ms hide delay";
}

CursorManager::~CursorManager() {
    // Restore cursor if we hid it
    if (m_overrideActive) {
        QGuiApplication::restoreOverrideCursor();
    }
}

void CursorManager::setCursorVisible(bool visible) {
    if (m_cursorVisible == visible)
        return;

    m_cursorVisible = visible;

    if (visible) {
        // Show cursor - restore the override if active
        if (m_overrideActive) {
            QGuiApplication::restoreOverrideCursor();
            m_overrideActive = false;
        }
    } else {
        // Hide cursor - push blank cursor override
        if (!m_overrideActive) {
            QGuiApplication::setOverrideCursor(Qt::BlankCursor);
            m_overrideActive = true;
        }
    }

    emit cursorVisibleChanged();
}

void CursorManager::setHideDelayMs(int ms) {
    if (m_hideDelayMs == ms)
        return;

    m_hideDelayMs = ms;
    emit hideDelayMsChanged();
}

void CursorManager::onMouseActivity() {
    // Show cursor
    if (!m_cursorVisible) {
        setCursorVisible(true);
    }

    // Restart hide timer
    m_hideTimer->start(m_hideDelayMs);
}

void CursorManager::hideCursor() {
    setCursorVisible(false);
}
