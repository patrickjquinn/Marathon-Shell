#include "sessionstore.h"

#include <QDateTime>

SessionStore::SessionStore(QObject *parent)
    : QObject(parent) {
    m_lockTimer.setSingleShot(true);
    connect(&m_lockTimer, &QTimer::timeout, this, [this]() {
        setIsLocked(m_targetLocked);
        setIsAnimatingLock(false);
        setLockTransition(QString());
        emit lockStateChanged(m_isLocked);
    });
}

void SessionStore::setIsLocked(bool locked) {
    if (m_isLocked == locked)
        return;
    m_isLocked = locked;
    emit isLockedChanged();
}

void SessionStore::setIsOnLockScreen(bool onLockScreen) {
    if (m_isOnLockScreen == onLockScreen)
        return;
    m_isOnLockScreen = onLockScreen;
    emit isOnLockScreenChanged();
}

void SessionStore::setShowLockScreen(bool show) {
    if (m_showLockScreen == show)
        return;
    m_showLockScreen = show;
    emit showLockScreenChanged();
}

void SessionStore::setIsAnimatingLock(bool animating) {
    if (m_isAnimatingLock == animating)
        return;
    m_isAnimatingLock = animating;
    emit isAnimatingLockChanged();
}

void SessionStore::setLockTransition(const QString &transition) {
    if (m_lockTransition == transition)
        return;
    m_lockTransition = transition;
    emit lockTransitionChanged();
}

void SessionStore::lock() {
    if (m_isLocked)
        return;

    setShowLockScreen(true);
    setLockTransition("locking");
    setIsAnimatingLock(true);
    emit lockStateChanging(true);
    startLockTimer(true);
}

void SessionStore::unlock() {
    if (m_isAnimatingLock && m_lockTransition == "unlocking") {
        setShowLockScreen(false);
        setIsOnLockScreen(false);
        return;
    }

    if (!m_isLocked) {
        setShowLockScreen(false);
        setIsOnLockScreen(false);
        return;
    }

    setShowLockScreen(false);
    setLockTransition("unlocking");
    setIsAnimatingLock(true);
    emit lockStateChanging(false);
    m_sessionValidUntil = QDateTime::currentMSecsSinceEpoch() + 5 * 60 * 1000;
    startLockTimer(false);
}

bool SessionStore::checkSession() const {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    return m_sessionValidUntil > now;
}

void SessionStore::showLock() {
    setShowLockScreen(true);
}

void SessionStore::startLockTimer(bool targetLocked) {
    m_targetLocked = targetLocked;
    m_lockTimer.setInterval(300);
    m_lockTimer.start();
}
