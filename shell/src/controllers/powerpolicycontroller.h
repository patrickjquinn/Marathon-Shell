#pragma once

#include <QObject>
#include <qqml.h>

class Power;
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
    // Doze is Marathon's iOS/Android-equivalent of "screen off, kernel
    // still running, apps frozen, network/modem live". It is NOT S3.
    // Wake from Doze is sub-100 ms (DRM resume + unfreeze foreground)
    // and the wifi/modem associations are never torn down — so push
    // notifications arrive while the device is "asleep".
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

    explicit PowerPolicyController(Power *powerManager, DisplayManagerCpp *displayManager,
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

    Q_INVOKABLE QString wake(const QString &reason);
    Q_INVOKABLE bool    sleep(const QString &reason = QStringLiteral("other"));

    // Doze is the screen being off: whatever turns the screen off (power
    // key, idle timer, Display1.SetScreenState) enters it, and whatever
    // turns it on leaves it.
    bool dozing() const;

    // Marathon-Doze entry / exit: screen off, kernel running, apps frozen,
    // wifi PSM on; and the mirror. Both are idempotent. Wake from doze is
    // sub-100 ms (no kernel resume penalty) and network/modem associations
    // stay live the whole time so push notifications arrive while "asleep".
    Q_INVOKABLE bool enterDoze(const QString &reason = QStringLiteral("other"));
    Q_INVOKABLE bool exitDoze();

    Q_INVOKABLE PowerPolicyController::PowerButtonAction powerButtonAction(bool screenOn, bool sessionLocked) const;

    Q_INVOKABLE PowerPolicyController::SleepAction       sleepAction(bool sessionLocked) const;

    Q_INVOKABLE void              performCriticalPowerAction();

  signals:
    void wakeLockCountChanged();
    void hasActiveCallsChanged();
    void hasActiveAlarmChanged();
    void canSleepChanged();
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
    void                 onScreenOnChanged(bool on);
    void                 handleBatteryPolicy();

    Power     *m_powerManager   = nullptr;
    DisplayManagerCpp   *m_displayManager = nullptr;
    AppLifecycleManager *m_lifecycle      = nullptr;

    int                  m_savedFreezeDebounceMs = -1;

    bool                 m_hasActiveCalls = false;
    bool                 m_hasActiveAlarm = false;
    bool                 m_lastCanSleep   = true;

    int                  m_lastBatteryWarningLevel = 100;
    bool                 m_hasShownCriticalWarning = false;
    bool                 m_emergencyShutdownArmed  = false;
};
