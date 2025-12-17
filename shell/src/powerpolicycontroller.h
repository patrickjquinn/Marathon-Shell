#pragma once

#include <QObject>
#include <QVariantList>

class PowerManagerCpp;
class DisplayManagerCpp;

/**
 * PowerPolicyController
 *
 * Owns shell-level power orchestration/policy that should not live in QML:
 * - wake/sleep helpers
 * - scheduled wake bookkeeping (RTC alarm)
 * - battery warnings / emergency shutdown policy (UI presentation stays in QML)
 *
 * Low-level system integration remains in PowerManagerCpp / DisplayManagerCpp.
 */
class PowerPolicyController : public QObject {
    Q_OBJECT
    Q_PROPERTY(int wakeLockCount READ wakeLockCount NOTIFY wakeLockCountChanged)
    Q_PROPERTY(bool hasActiveCalls READ hasActiveCalls WRITE setHasActiveCalls NOTIFY
                   hasActiveCallsChanged)
    Q_PROPERTY(bool hasActiveAlarm READ hasActiveAlarm WRITE setHasActiveAlarm NOTIFY
                   hasActiveAlarmChanged)
    Q_PROPERTY(bool canSleep READ canSleep NOTIFY canSleepChanged)
    Q_PROPERTY(QVariantList scheduledWakes READ scheduledWakes NOTIFY scheduledWakesChanged)
    Q_PROPERTY(QString wakeReason READ wakeReason NOTIFY wakeReasonChanged)

  public:
    enum PowerButtonAction {
        NoOp = 0,
        TurnScreenOn,
        LockAndTurnScreenOff,
        TurnScreenOff,
    };
    Q_ENUM(PowerButtonAction)

    enum SleepAction {
        SleepNoLock = 0,
        LockThenSleep,
    };
    Q_ENUM(SleepAction)

    explicit PowerPolicyController(PowerManagerCpp *powerManager, DisplayManagerCpp *displayManager,
                                   QObject *parent = nullptr);

    int  wakeLockCount() const;

    bool hasActiveCalls() const {
        return m_hasActiveCalls;
    }
    void setHasActiveCalls(bool v);

    bool hasActiveAlarm() const {
        return m_hasActiveAlarm;
    }
    void         setHasActiveAlarm(bool v);

    bool         canSleep() const;

    QVariantList scheduledWakes() const {
        return m_scheduledWakes;
    }

    QString wakeReason() const {
        return m_wakeReason;
    }

    Q_INVOKABLE QString wake(const QString &reason);
    Q_INVOKABLE bool    sleep();

    // Power button press policy:
    // - If screen is off -> turn it on
    // - Else if session is unlocked -> lock and turn screen off
    // - Else (already locked) -> turn screen off
    Q_INVOKABLE PowerButtonAction powerButtonAction(bool screenOn, bool sessionLocked) const;

    // Power menu policy:
    // - If unlocked -> lock first, then sleep
    // - If already locked -> sleep immediately
    Q_INVOKABLE SleepAction sleepAction(bool sessionLocked) const;

    // Execute the system-configured UPower critical action (best-effort).
    Q_INVOKABLE void performCriticalPowerAction();

    // Epoch seconds (UTC) keeps QML↔C++ conversion simple
    Q_INVOKABLE QString scheduleWakeEpoch(qint64 epochSeconds, const QString &reason);
    Q_INVOKABLE bool    cancelScheduledWake(const QString &wakeId);

  signals:
    void wakeLockCountChanged();
    void hasActiveCallsChanged();
    void hasActiveAlarmChanged();
    void canSleepChanged();
    void scheduledWakesChanged();
    void wakeReasonChanged();
    void systemWaking(const QString &reason);
    void systemSleeping();

    // Battery policy signals (presentation belongs in QML).
    // hapticLevel: 1=light, 2=medium, 3=heavy
    void batteryWarning(const QString &title, const QString &body, const QString &iconName,
                        int hapticLevel);
    void emergencyShutdownArmed(int secondsUntilShutdown);
    void emergencyShutdownDisarmed();

  private:
    void               emitCanSleepMaybeChanged();
    void               handleBatteryPolicy();

    PowerManagerCpp   *m_powerManager   = nullptr;
    DisplayManagerCpp *m_displayManager = nullptr;

    bool               m_hasActiveCalls = false;
    bool               m_hasActiveAlarm = false;
    bool               m_lastCanSleep   = true;
    QVariantList       m_scheduledWakes;
    QString            m_wakeReason;

    // Battery policy state (prevents repeated warnings).
    int  m_lastBatteryWarningLevel = 100;
    bool m_hasShownCriticalWarning = false;
    bool m_emergencyShutdownArmed  = false;
};
