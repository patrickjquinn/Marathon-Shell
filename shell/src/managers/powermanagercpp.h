#ifndef POWERMANAGERCPP_H
#define POWERMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusUnixFileDescriptor>
#include <QTimer>
#include <QMap>
#include <QSet>

#include <QDBusContext>
#include <qqml.h>

class WakeTimers;

class PowerManagerCpp : public QObject, protected QDBusContext {
    Q_OBJECT
    QML_NAMED_ELEMENT(PowerManagerService)
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static PowerManagerCpp *create(QQmlEngine *, QJSEngine *);

    // Whether a resume at nowSecs is the wake-up marathon-background armed
    // (its time is in markerPath), not one for the alarm due at alarmSecs or
    // one the person caused.
    static bool isBackgroundWake(const QString &markerPath, qint64 alarmSecs, qint64 nowSecs);

    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)

    Q_PROPERTY(uint warningLevel READ warningLevel NOTIFY warningLevelChanged)

    Q_PROPERTY(bool isCharging READ isCharging NOTIFY isChargingChanged)
    Q_PROPERTY(bool isPluggedIn READ isPluggedIn NOTIFY isPluggedInChanged)
    Q_PROPERTY(bool isPowerSaveMode READ isPowerSaveMode NOTIFY isPowerSaveModeChanged)
    Q_PROPERTY(
        int estimatedBatteryTime READ estimatedBatteryTime NOTIFY estimatedBatteryTimeChanged)
    Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY powerProfileChanged)
    Q_PROPERTY(bool powerProfilesSupported READ powerProfilesSupported CONSTANT)
    Q_PROPERTY(int idleTimeout READ idleTimeout WRITE setIdleTimeout NOTIFY idleTimeoutChanged)
    Q_PROPERTY(bool autoSuspendEnabled READ autoSuspendEnabled WRITE setAutoSuspendEnabled NOTIFY
                   autoSuspendEnabledChanged)
    Q_PROPERTY(QStringList activeWakelocks READ activeWakelocks NOTIFY activeWakelocksChanged)
    Q_PROPERTY(int wakeLockCount READ wakeLockCount NOTIFY activeWakelocksChanged)

    Q_PROPERTY(QString criticalAction READ criticalAction NOTIFY criticalActionChanged)

  public:
    enum PowerProfile : quint8 {
        Performance,
        Balanced,
        PowerSaver
    };
    Q_ENUM(PowerProfile)

    explicit PowerManagerCpp(QObject *parent = nullptr);
    ~PowerManagerCpp() override;

    int batteryLevel() const {
        return m_batteryLevel;
    }
    uint warningLevel() const {
        return m_warningLevel;
    }
    bool isCharging() const {
        return m_isCharging;
    }
    bool isPluggedIn() const {
        return m_isPluggedIn;
    }
    bool isPowerSaveMode() const {
        return m_isPowerSaveMode;
    }
    int estimatedBatteryTime() const {
        return m_estimatedBatteryTime;
    }
    QString powerProfile() const {
        return m_powerProfileString;
    }
    QString criticalAction() const {
        return m_criticalAction;
    }
    bool powerProfilesSupported() const {
        return m_powerProfilesSupported;
    }
    int idleTimeout() const {
        return m_idleTimeout;
    }
    bool autoSuspendEnabled() const {
        return m_autoSuspendEnabled;
    }

    QStringList activeWakelocks() const;
    int         wakeLockCount() const {
        return activeWakelocks().size();
    }

    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void hybridSleep();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setPowerSaveMode(bool enabled);
    Q_INVOKABLE void setPowerProfile(const QString &profile);
    Q_INVOKABLE void setIdleTimeout(int seconds);
    Q_INVOKABLE void setAutoSuspendEnabled(bool enabled);

    Q_INVOKABLE bool acquireWakelock(const QString &name);
    Q_INVOKABLE bool releaseWakelock(const QString &name);
    Q_INVOKABLE bool inhibitSuspend(const QString &who, const QString &why);
    Q_INVOKABLE void releaseInhibitor();

    // The next alarm, which wakes a suspended device with the screen on;
    // 0 for none.
    void             setAlarmWake(qint64 epochSecs);

    Q_INVOKABLE void updateActivity();

  signals:
    void batteryLevelChanged();
    void warningLevelChanged();
    void isChargingChanged();
    void isPluggedInChanged();
    void isPowerSaveModeChanged();
    void estimatedBatteryTimeChanged();
    void powerProfileChanged();
    void criticalActionChanged();
    void idleTimeoutChanged();
    void autoSuspendEnabledChanged();
    void criticalBattery();
    void powerError(const QString &message);
    void resumedFromSuspend(bool backgroundWake);
    void idleStateChanged(bool idle);
    void activeWakelocksChanged();

  private slots:
    void updateAggregateState();
    void onPrepareForSleep(bool beforeSleep);
    void checkIdleState();

  private:
    void                    setupDBusConnections();
    void                    applyCPUGovernor(PowerProfile profile) const;
    void                    checkCPUGovernorSupport();
    void                    checkWakelockSupport();
    void                    cleanupWakelocks();
    void                    setupDisplayDevice();
    bool                    writeToFile(const QString &path, const QString &content);

    QDBusInterface         *m_upowerInterface;
    QDBusInterface         *m_displayDeviceInterface;
    QDBusInterface         *m_logindInterface;
    QTimer                 *m_idleTimer;

    int                     m_batteryLevel;
    uint                    m_warningLevel;
    bool                    m_isCharging;
    bool                    m_isPluggedIn;
    bool                    m_isPowerSaveMode;
    // Pre-saver settings captured on entry so exit restores them exactly.
    int                     m_preSaverIdleTimeout = 0;
    QString                 m_preSaverProfile;
    int                     m_estimatedBatteryTime;
    bool                    m_hasUPower;
    bool                    m_hasLogind;

    PowerProfile            m_currentProfile;
    QString                 m_powerProfileString;
    bool                    m_powerProfilesSupported;
    int                     m_idleTimeout;
    bool                    m_autoSuspendEnabled;
    bool                    m_isIdle;
    qint64                  m_lastActivityTime;

    QMap<QString, bool>     m_activeWakelocks;
    QDBusUnixFileDescriptor m_inhibitorFd;
    bool                    m_wakelockSupported;
    QString                 m_fallbackMode;

    WakeTimers             *m_wakeTimers;
    qint64                  m_alarmWake = 0;
    QString                 m_criticalAction;
};

#endif
