#pragma once

#include <QObject>
#include <QVariantList>
#include <qqml.h>

class PowerManagerCpp;
class DisplayManagerCpp;
class AppLifecycleManager;

class PowerPolicyController : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(PowerPolicyControllerCpp)
    QML_SINGLETON
    Q_PROPERTY(int wakeLockCount READ wakeLockCount NOTIFY wakeLockCountChanged)
    Q_PROPERTY(bool hasActiveCalls READ hasActiveCalls WRITE setHasActiveCalls NOTIFY
                   hasActiveCallsChanged)
    Q_PROPERTY(bool hasActiveAlarm READ hasActiveAlarm WRITE setHasActiveAlarm NOTIFY
                   hasActiveAlarmChanged)
    Q_PROPERTY(bool canSleep READ canSleep NOTIFY canSleepChanged)
    Q_PROPERTY(QVariantList scheduledWakes READ scheduledWakes NOTIFY scheduledWakesChanged)
    Q_PROPERTY(QString wakeReason READ wakeReason NOTIFY wakeReasonChanged)
    // Doze is Marathon's iOS/Android-equivalent of "screen off, kernel
    // still running, apps frozen, network/modem live". It is NOT S3.
    // Wake from Doze is sub-100 ms (DRM resume + unfreeze foreground)
    // and the wifi/modem associations are never torn down — so push
    // notifications arrive while the device is "asleep". Deep S3
    // suspend remains reachable via deepSleep() for critical battery
    // and explicit user choice.
    Q_PROPERTY(bool dozing READ dozing NOTIFY dozingChanged)

  public:
    enum PowerButtonAction : quint8 {
        NoOp = 0,
        TurnScreenOn,
        LockAndTurnScreenOff,
        TurnScreenOff,
    };
    Q_ENUM(PowerButtonAction)

    enum SleepAction : quint8 {
        SleepNoLock = 0,
        LockThenSleep,
    };
    Q_ENUM(SleepAction)

    explicit PowerPolicyController(PowerManagerCpp *powerManager, DisplayManagerCpp *displayManager,
                                   AppLifecycleManager *lifecycle = nullptr,
                                   QObject             *parent    = nullptr);

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

    bool                dozing() const {
        return m_dozing;
    }

    // Marathon-Doze entry / exit. enterDoze() bundles the "screen off,
    // kernel running, apps frozen, wifi PSM on" policy that replaces
    // S3 for the daily power-key / idle-timer flow. exitDoze() is the
    // mirror — DRM resume, foreground unfreeze, wifi PSM off, full
    // brightness back. Both are idempotent and safe to call from any
    // state. Wake from doze is sub-100 ms (no kernel resume penalty)
    // and network/modem associations stay live the whole time so push
    // notifications arrive while "asleep".
    Q_INVOKABLE bool enterDoze();
    Q_INVOKABLE bool exitDoze();

    // Deep S3 suspend. Reachable only via explicit user choice
    // (PowerMenu → "Deep Sleep") or the critical-battery handler.
    // Tears down wifi/modem; the wake path is the slow S3 resume
    // already wired via PowerManagerCpp::resumedFromSuspend →
    // DisplayPolicyController::forceScreenOn (r293 backlight fix).
    Q_INVOKABLE bool              deepSleep();

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
    void dozingChanged();
    void dozeEntered();
    void dozeExited();

    void batteryWarning(const QString &title, const QString &body, const QString &iconName,
                        int hapticLevel);
    void emergencyShutdownArmed(int secondsUntilShutdown);
    void emergencyShutdownDisarmed();

  private:
    void                 emitCanSleepMaybeChanged();
    void                 handleBatteryPolicy();

    PowerManagerCpp     *m_powerManager   = nullptr;
    DisplayManagerCpp   *m_displayManager = nullptr;
    AppLifecycleManager *m_lifecycle      = nullptr;

    bool                 m_dozing                = false;
    int                  m_savedFreezeDebounceMs = -1;

    bool                 m_hasActiveCalls = false;
    bool                 m_hasActiveAlarm = false;
    bool                 m_lastCanSleep   = true;
    QVariantList         m_scheduledWakes;
    QString              m_wakeReason;

    int                  m_lastBatteryWarningLevel = 100;
    bool                 m_hasShownCriticalWarning = false;
    bool                 m_emergencyShutdownArmed  = false;
};
