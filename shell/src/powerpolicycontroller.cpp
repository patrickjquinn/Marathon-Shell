#include "powerpolicycontroller.h"

#include "powermanagercpp.h"
#include "displaymanagercpp.h"

#include <QDateTime>
#include <QUuid>

PowerPolicyController::PowerPolicyController(PowerManagerCpp   *powerManager,
                                             DisplayManagerCpp *displayManager, QObject *parent)
    : QObject(parent)
    , m_powerManager(powerManager)
    , m_displayManager(displayManager) {

    // Keep canSleep reactive when wakelocks change
    if (m_powerManager) {
        connect(m_powerManager, &PowerManagerCpp::activeWakelocksChanged, this, [this]() {
            emit wakeLockCountChanged();
            emitCanSleepMaybeChanged();
        });
    }

    m_lastCanSleep = canSleep();
}

int PowerPolicyController::wakeLockCount() const {
    if (!m_powerManager)
        return 0;
    return m_powerManager->wakeLockCount();
}

bool PowerPolicyController::canSleep() const {
    return wakeLockCount() == 0 && !m_hasActiveCalls && !m_hasActiveAlarm;
}

void PowerPolicyController::setHasActiveCalls(bool v) {
    if (m_hasActiveCalls == v)
        return;
    m_hasActiveCalls = v;
    emit hasActiveCallsChanged();
    emitCanSleepMaybeChanged();
}

void PowerPolicyController::setHasActiveAlarm(bool v) {
    if (m_hasActiveAlarm == v)
        return;
    m_hasActiveAlarm = v;
    emit hasActiveAlarmChanged();
    emitCanSleepMaybeChanged();
}

void PowerPolicyController::emitCanSleepMaybeChanged() {
    const bool now = canSleep();
    if (now != m_lastCanSleep) {
        m_lastCanSleep = now;
        emit canSleepChanged();
    }
}

QString PowerPolicyController::wake(const QString &reason) {
    m_wakeReason = reason;
    emit wakeReasonChanged();

    // Best-effort: wake screen
    if (m_displayManager)
        m_displayManager->setScreenState(true);

    emit systemWaking(reason);

    // Acquire a temporary wakelock (use reason as identifier)
    if (m_powerManager)
        m_powerManager->acquireWakelock(reason);

    return reason;
}

bool PowerPolicyController::sleep() {
    if (!canSleep()) {
        return false;
    }

    emit systemSleeping();

    // Best-effort: blank screen before suspend
    if (m_displayManager)
        m_displayManager->setScreenState(false);

    if (m_powerManager) {
        m_powerManager->suspend();
        return true;
    }
    return false;
}

QString PowerPolicyController::scheduleWakeEpoch(qint64 epochSeconds, const QString &reason) {
    const QString wakeId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QVariantMap   wake;
    wake.insert("id", wakeId);
    wake.insert("epochSeconds", epochSeconds);
    wake.insert("reason", reason);
    wake.insert("timestamp", QDateTime::currentSecsSinceEpoch());
    m_scheduledWakes.push_back(wake);
    emit scheduledWakesChanged();

    if (m_powerManager)
        m_powerManager->setRtcAlarm(epochSeconds);

    return wakeId;
}

bool PowerPolicyController::cancelScheduledWake(const QString &wakeId) {
    for (qsizetype i = 0; i < m_scheduledWakes.size(); i++) {
        const auto wake = m_scheduledWakes.at(i).toMap();
        if (wake.value("id").toString() == wakeId) {
            m_scheduledWakes.removeAt(i);
            emit scheduledWakesChanged();
            return true;
        }
    }
    return false;
}
