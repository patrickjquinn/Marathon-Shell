#include "powerpolicycontroller.h"

#include "powermanagercpp.h"
#include "displaymanagercpp.h"
#include "../services/applifecyclemanager.h"

#include <QDateTime>
#include <QProcess>
#include <QUuid>

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
    m_wakeReason = reason;
    emit wakeReasonChanged();

    if (m_displayManager)
        m_displayManager->setScreenState(true);

    emit systemWaking(reason);

    if (m_powerManager)
        m_powerManager->acquireWakelock(reason);

    return reason;
}

bool PowerPolicyController::sleep() {
    // Backwards-compatible alias for enterDoze(). The historic semantics
    // of sleep() (call logind.Suspend → full S3) are preserved as
    // deepSleep() below for the explicit "max battery" path. Routing
    // sleep() to Doze matches the iOS / Android user model: the
    // visible "sleep" state keeps push live; deep suspend is a power
    // user choice.
    return enterDoze();
}

bool PowerPolicyController::enterDoze() {
    if (m_dozing) {
        return true;
    }

    qInfo() << "[PowerPolicyController] Entering Doze";
    emit systemSleeping();

    // 1. Display + backlight off. Goes through DisplayManagerCpp's
    //    bl_power=4 path (re-writes brightness on the eventual unblank
    //    via the r293 fix). Does NOT trigger DPMS / KMS suspend — the
    //    Qt eglfs_kms backend's setPowerState path is known broken on
    //    i.MX 8M Quad + mxsfb-dsi. Backlight-off + compositor frame
    //    pause is enough to drop visible draw to ~0.
    if (m_displayManager)
        m_displayManager->setScreenState(false);

    // 2. Freeze background apps immediately (skip the per-app debounce).
    //    AppLifecycleManager.setIdleFreezeDebounceMs(0) makes every
    //    background app eligible for cgroup.freeze on next tick.
    //    Foreground app stays thawed — pressing power again must wake
    //    it instantly without re-launch.
    if (m_lifecycle) {
        m_savedFreezeDebounceMs = m_lifecycle->idleFreezeDebounceMs();
        m_lifecycle->setIdleFreezeDebounceMs(0);
    }

    // 3. Wifi PSM on. Chip-level low-power-idle (~0.82 mA on most
    //    cards) while the association stays alive, so push sockets
    //    don't get torn down. Shell out to `iw` — the QtBluetooth /
    //    NetworkManager APIs don't expose it. Best-effort: failures
    //    are logged and ignored (we'd rather have Doze without PSM
    //    than no Doze at all).
    // Absolute path because the shell's user-scope PATH may not include
    // /usr/sbin. The marathon-iw-setcap.service oneshot grants
    // cap_net_admin on /usr/sbin/iw at boot so this call works as
    // uid 1000 (the alternative — pkexec / nmcli reapply — needs
    // auth_admin which doesn't pass for the active session).
    QProcess::startDetached(QStringLiteral("/usr/sbin/iw"),
                            {QStringLiteral("dev"), QStringLiteral("wlan0"), QStringLiteral("set"),
                             QStringLiteral("power_save"), QStringLiteral("on")});

    m_dozing = true;
    emit dozingChanged();
    emit dozeEntered();
    return true;
}

bool PowerPolicyController::exitDoze() {
    if (!m_dozing) {
        return true;
    }

    qInfo() << "[PowerPolicyController] Exiting Doze";

    // 1. Restore freeze debounce + thaw foreground (background apps
    //    stay frozen until the user actually brings them up — saves
    //    power vs an unconditional thaw). The lifecycle manager's
    //    bringToForeground() path handles thaw transparently.
    if (m_lifecycle && m_savedFreezeDebounceMs >= 0) {
        m_lifecycle->setIdleFreezeDebounceMs(m_savedFreezeDebounceMs);
        m_savedFreezeDebounceMs = -1;
    }

    // 2. Wifi PSM off — slight latency win for foreground interaction.
    //    Optional; could leave on for ~ 5% additional standby but
    //    snappier first packets matter more on resume.
    QProcess::startDetached(QStringLiteral("/usr/sbin/iw"),
                            {QStringLiteral("dev"), QStringLiteral("wlan0"), QStringLiteral("set"),
                             QStringLiteral("power_save"), QStringLiteral("off")});

    // 3. Backlight + brightness restore. setScreenState(true) re-writes
    //    bl_power=0 AND brightness (r293) so the i.MX 8M PWM glitch
    //    doesn't leave us at 0% duty.
    if (m_displayManager)
        m_displayManager->setScreenState(true);

    m_dozing = false;
    emit dozingChanged();
    emit dozeExited();
    emit systemWaking(QStringLiteral("doze-exit"));
    return true;
}

bool PowerPolicyController::deepSleep() {
    if (!canSleep()) {
        return false;
    }

    qInfo() << "[PowerPolicyController] Entering DEEP SLEEP (S3) — tearing down wifi+modem";
    emit systemSleeping();

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

            if (m_scheduledWakes.isEmpty() && m_powerManager)
                m_powerManager->clearRtcAlarm();

            return true;
        }
    }
    return false;
}
