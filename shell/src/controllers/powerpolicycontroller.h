#pragma once

#include <QObject>
#include <QVariantList>

class PowerManagerCpp;
class DisplayManagerCpp;

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

    Q_INVOKABLE QString           wake(const QString &reason);
    Q_INVOKABLE bool              sleep();

    Q_INVOKABLE PowerButtonAction powerButtonAction(bool screenOn, bool sessionLocked) const;

    Q_INVOKABLE SleepAction       sleepAction(bool sessionLocked) const;

    Q_INVOKABLE void              performCriticalPowerAction();

    Q_INVOKABLE QString           scheduleWakeEpoch(qint64 epochSeconds, const QString &reason);
    Q_INVOKABLE bool              cancelScheduledWake(const QString &wakeId);

  signals:
    void wakeLockCountChanged();
    void hasActiveCallsChanged();
    void hasActiveAlarmChanged();
    void canSleepChanged();
    void scheduledWakesChanged();
    void wakeReasonChanged();
    void systemWaking(const QString &reason);
    void systemSleeping();

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

    int                m_lastBatteryWarningLevel = 100;
    bool               m_hasShownCriticalWarning = false;
    bool               m_emergencyShutdownArmed  = false;
};
