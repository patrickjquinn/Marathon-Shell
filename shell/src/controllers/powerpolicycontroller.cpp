#include "powerpolicycontroller.h"
#include "src/managers/deviceprofile.h"

#include "powermanagercpp.h"
#include "displaymanagercpp.h"
#include "../services/applifecyclemanager.h"

#include <QProcess>

PowerPolicyController::PowerPolicyController(PowerManagerCpp     *powerManager,
                                             DisplayManagerCpp   *displayManager,
                                             AppLifecycleManager *lifecycle, QObject *parent)
    : QObject(parent)
    , m_powerManager(powerManager)
    , m_displayManager(displayManager)
    , m_lifecycle(lifecycle) {

    if (m_powerManager) {
        connect(m_powerManager, &PowerManagerCpp::activeWakelocksChanged, this, [this]() {
            emit wakeLockCountChanged();
            emitCanSleepMaybeChanged();
        });

        connect(m_powerManager, &PowerManagerCpp::batteryLevelChanged, this,
                &PowerPolicyController::handleBatteryPolicy);
        connect(m_powerManager, &PowerManagerCpp::isChargingChanged, this,
                &PowerPolicyController::handleBatteryPolicy);
    }

    if (m_displayManager)
        connect(m_displayManager, &DisplayManagerCpp::screenOnChanged, this,
                &PowerPolicyController::onScreenOnChanged);

    m_lastCanSleep = canSleep();

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
            QStringLiteral("battery-warning"), 3);
        m_hasShownCriticalWarning = true;
        m_lastBatteryWarningLevel = qMin(level, 3);
        if (!m_emergencyShutdownArmed) {
            m_emergencyShutdownArmed = true;
            emit emergencyShutdownArmed(10);
        }
        return;
    }

    if (m_emergencyShutdownArmed && warning < 4) {
        m_emergencyShutdownArmed = false;
        emit emergencyShutdownDisarmed();
    }

    if (warning == 3 && m_lastBatteryWarningLevel > 20) {
        emit batteryWarning(QStringLiteral("Battery Low"),
                            QStringLiteral("%1% remaining").arg(level), QStringLiteral("battery"),
                            1);
        m_lastBatteryWarningLevel = 20;
        return;
    }

    if (warning <= 2 && level <= 5 && m_lastBatteryWarningLevel > 5) {
        emit batteryWarning(
            QStringLiteral("Very Low Battery"),
            QStringLiteral("%1% remaining. Connect charger immediately.").arg(level),
            QStringLiteral("battery-warning"), 3);
        m_lastBatteryWarningLevel = 5;
        return;
    }

    if (warning <= 2 && level <= 10 && m_lastBatteryWarningLevel > 10) {
        emit batteryWarning(QStringLiteral("Low Battery"),
                            QStringLiteral("%1% remaining. Connect charger soon.").arg(level),
                            QStringLiteral("battery"), 2);
        m_lastBatteryWarningLevel = 10;
        return;
    }

    if (warning <= 2 && level <= 20 && m_lastBatteryWarningLevel > 20) {
        emit batteryWarning(QStringLiteral("Battery Low"),
                            QStringLiteral("%1% remaining").arg(level), QStringLiteral("battery"),
                            1);
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
    } else if (action.compare("Suspend", Qt::CaseInsensitive) == 0) {
        m_powerManager->suspend();
    } else {
        // Default: PowerOff / Shutdown / anything unrecognized → safe shutdown.
        m_powerManager->shutdown();
    }
}

QString PowerPolicyController::wake(const QString &reason) {
    if (m_displayManager)
        m_displayManager->setScreenState(true);

    emit systemWaking(reason);
    return reason;
}

bool PowerPolicyController::sleep(const QString &reason) {
    // Backwards-compatible alias for enterDoze(). Routing sleep() to
    // Doze matches the iOS / Android user model: the visible "sleep"
    // state keeps push live.
    return enterDoze(reason);
}

bool PowerPolicyController::dozing() const {
    return m_displayManager && !m_displayManager->screenOn();
}

bool PowerPolicyController::enterDoze(const QString &reason) {
    if (m_displayManager && m_displayManager->screenOn())
        m_displayManager->setScreenState(false, QStringLiteral("%1 (doze)").arg(reason));
    return true;
}

bool PowerPolicyController::exitDoze() {
    if (dozing())
        m_displayManager->setScreenState(true);
    return true;
}

void PowerPolicyController::onScreenOnChanged(bool on) {
    if (!on) {
        qInfo() << "[PowerPolicyController] Entering Doze";
        emit systemSleeping();

        // Freeze background apps at once (skip the per-app debounce). The
        // foreground app stays thawed so the next wake is instant.
        if (m_lifecycle) {
            m_savedFreezeDebounceMs = m_lifecycle->idleFreezeDebounceMs();
            m_lifecycle->setIdleFreezeDebounceMs(0);
        }

        // Wifi PSM: chip-level low-power idle while the association stays up,
        // so push sockets survive. Absolute path: the session PATH may lack
        // /usr/sbin; marathon-iw-setcap.service grants iw cap_net_admin.
        if (DeviceProfile::instance().wifiPowerSave())
            QProcess::startDetached(QStringLiteral("/usr/sbin/iw"),
                                    {QStringLiteral("dev"), QStringLiteral("wlan0"),
                                     QStringLiteral("set"), QStringLiteral("power_save"),
                                     QStringLiteral("on")});

        emit dozingChanged();
        emit dozeEntered();
        return;
    }

    qInfo() << "[PowerPolicyController] Exiting Doze";
    if (m_lifecycle && m_savedFreezeDebounceMs >= 0) {
        m_lifecycle->setIdleFreezeDebounceMs(m_savedFreezeDebounceMs);
        m_savedFreezeDebounceMs = -1;
    }
    if (DeviceProfile::instance().wifiPowerSave())
        QProcess::startDetached(QStringLiteral("/usr/sbin/iw"),
                                {QStringLiteral("dev"), QStringLiteral("wlan0"),
                                 QStringLiteral("set"), QStringLiteral("power_save"),
                                 QStringLiteral("off")});

    emit dozingChanged();
    emit dozeExited();
    emit systemWaking(QStringLiteral("doze-exit"));
}
