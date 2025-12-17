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

        // Battery policy lives here (QML should not encode threshold logic).
        connect(m_powerManager, &PowerManagerCpp::batteryLevelChanged, this,
                &PowerPolicyController::handleBatteryPolicy);
        connect(m_powerManager, &PowerManagerCpp::isChargingChanged, this,
                &PowerPolicyController::handleBatteryPolicy);
    }

    m_lastCanSleep = canSleep();

    // Evaluate battery policy once on startup (best-effort).
    handleBatteryPolicy();
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

void PowerPolicyController::handleBatteryPolicy() {
    if (!m_powerManager)
        return;

    const int  level      = m_powerManager->batteryLevel();
    const bool isCharging = m_powerManager->isCharging();
    const uint warning    = m_powerManager->warningLevel();

    if (isCharging) {
        m_lastBatteryWarningLevel = 100;
        m_hasShownCriticalWarning = false;
        if (m_emergencyShutdownArmed) {
            m_emergencyShutdownArmed = false;
            emit emergencyShutdownDisarmed();
        }
        return;
    }

    // Prefer UPower WarningLevel for policy:
    // 0 Unknown, 1 None, 2 Discharging (UPS only), 3 Low, 4 Critical, 5 Action
    if (warning >= 4 && !m_hasShownCriticalWarning) {
        QString action = QStringLiteral("shutdown");
        if (m_powerManager) {
            const QString configured = m_powerManager->criticalAction();
            if (!configured.isEmpty())
                action = configured;
        }
        emit batteryWarning(
            QStringLiteral("Critical Battery"),
            QStringLiteral("Device will %1 in 10 seconds to prevent data loss").arg(action),
            QStringLiteral("battery-warning"),
            /*hapticLevel*/ 3);
        m_hasShownCriticalWarning = true;
        m_lastBatteryWarningLevel = qMin(level, 3);
        if (!m_emergencyShutdownArmed) {
            m_emergencyShutdownArmed = true;
            emit emergencyShutdownArmed(10);
        }
        return;
    }

    // If we recovered to a non-critical warning level, disarm.
    if (m_emergencyShutdownArmed && warning < 4) {
        m_emergencyShutdownArmed = false;
        emit emergencyShutdownDisarmed();
    }

    // Low warning: show a single toast when UPower says Low.
    if (warning == 3 && m_lastBatteryWarningLevel > 20) {
        emit batteryWarning(QStringLiteral("Battery Low"),
                            QStringLiteral("%1% remaining").arg(level), QStringLiteral("battery"),
                            /*hapticLevel*/ 1);
        m_lastBatteryWarningLevel = 20;
        return;
    }

    // Fallback % warnings only when WarningLevel isn't available.
    if (warning <= 2 && level <= 5 && m_lastBatteryWarningLevel > 5) {
        emit batteryWarning(
            QStringLiteral("Very Low Battery"),
            QStringLiteral("%1% remaining. Connect charger immediately.").arg(level),
            QStringLiteral("battery-warning"),
            /*hapticLevel*/ 3);
        m_lastBatteryWarningLevel = 5;
        return;
    }

    if (warning <= 2 && level <= 10 && m_lastBatteryWarningLevel > 10) {
        emit batteryWarning(QStringLiteral("Low Battery"),
                            QStringLiteral("%1% remaining. Connect charger soon.").arg(level),
                            QStringLiteral("battery"),
                            /*hapticLevel*/ 2);
        m_lastBatteryWarningLevel = 10;
        return;
    }

    if (warning <= 2 && level <= 20 && m_lastBatteryWarningLevel > 20) {
        emit batteryWarning(QStringLiteral("Battery Low"),
                            QStringLiteral("%1% remaining").arg(level), QStringLiteral("battery"),
                            /*hapticLevel*/ 1);
        m_lastBatteryWarningLevel = 20;
        return;
    }
}

PowerPolicyController::PowerButtonAction
PowerPolicyController::powerButtonAction(bool screenOn, bool sessionLocked) const {
    if (!screenOn) {
        return TurnScreenOn;
    }
    if (!sessionLocked) {
        return LockAndTurnScreenOff;
    }
    return TurnScreenOff;
}

PowerPolicyController::SleepAction PowerPolicyController::sleepAction(bool sessionLocked) const {
    return sessionLocked ? SleepNoLock : LockThenSleep;
}

void PowerPolicyController::performCriticalPowerAction() {
    if (!m_powerManager)
        return;

    const QString action = m_powerManager->criticalAction();
    qInfo() << "[PowerPolicyController] Performing critical power action:" << action;

    if (action.compare("HybridSleep", Qt::CaseInsensitive) == 0) {
        m_powerManager->hybridSleep();
    } else if (action.compare("Hibernate", Qt::CaseInsensitive) == 0) {
        m_powerManager->hibernate();
    } else if (action.compare("PowerOff", Qt::CaseInsensitive) == 0 ||
               action.compare("Shutdown", Qt::CaseInsensitive) == 0) {
        m_powerManager->shutdown();
    } else if (action.compare("Suspend", Qt::CaseInsensitive) == 0) {
        m_powerManager->suspend();
    } else {
        // Conservative fallback.
        m_powerManager->shutdown();
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
