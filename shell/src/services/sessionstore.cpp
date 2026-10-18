#include "sessionstore.h"
#include <QJSEngine>
#include <QQmlEngine>

SessionStore *SessionStore::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new SessionStore(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}
#include <QByteArray>
#include <QDateTime>

#include <ctime>

static qint64 bootClockMs() {
#ifdef CLOCK_BOOTTIME
    timespec ts{};
    if (clock_gettime(CLOCK_BOOTTIME, &ts) == 0)
        return qint64(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
#endif
    return QDateTime::currentMSecsSinceEpoch();
}

SessionStore::SessionStore(QObject *parent)
    : QObject(parent)
    , m_clock(bootClockMs) {
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
    m_sessionValidUntil = locked && m_lockDelay > 0 ? m_clock() + qint64{m_lockDelay} * 1000 : 0;
    emit isLockedChanged();
}

void SessionStore::setLockDelay(int seconds) {
    seconds = qMax(0, seconds);
    if (m_lockDelay == seconds)
        return;
    m_lockDelay = seconds;
    emit lockDelayChanged();
}

void SessionStore::setClock(std::function<qint64()> clock) {
    m_clock = std::move(clock);
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
    // Cancel any in-flight LOCK before doing anything else. A lock scheduled
    // moments ago (auto-lock, power-key) sits in m_lockTimer with
    // m_targetLocked == true and fires ~300 ms later. If unlock() short-
    // circuits below (already unlocking, or isLocked not yet asserted) without
    // stopping it, that stale timer flips isLocked back to true *after* we've
    // hidden the lock screen — leaving the home screen visible but the session
    // logically locked. That state silently gates off the Quick Settings shade
    // and system gestures (`visible: !SessionStore.isLocked && …`), and is the
    // root cause of the intermittent "home shows but QS won't open" bug: it
    // only triggers when unlock lands inside the lock-settling window.
    if (m_lockTimer.isActive() && m_targetLocked) {
        m_lockTimer.stop();
        setIsAnimatingLock(false);
        setLockTransition(QString());
    }

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
    startLockTimer(false);
}

bool SessionStore::checkSession() const {
    return m_sessionValidUntil > m_clock();
}

void SessionStore::showLock() {
    setShowLockScreen(true);
}

void SessionStore::reset() {
    m_lockTimer.stop();
    setIsAnimatingLock(false);
    setLockTransition(QString());

    // MARATHON_NO_INITIAL_LOCK skips the lock-screen-on-startup state. Useful
    // for headless / VM validation flows where there's no convenient way to
    // drive a swipe-to-unlock gesture, and harmless on real phones where the
    // env stays unset. Does not disable the lock screen at runtime -- it only
    // affects the initial state after construction / explicit reset.
    const bool skipInitialLock = !qEnvironmentVariableIsEmpty("MARATHON_NO_INITIAL_LOCK");

    setShowLockScreen(!skipInitialLock);
    setIsLocked(!skipInitialLock);
    m_sessionValidUntil = 0;
    setIsOnLockScreen(false);
}

void SessionStore::startLockTimer(bool targetLocked) {
    m_targetLocked = targetLocked;
    m_lockTimer.setInterval(300);
    m_lockTimer.start();
}
