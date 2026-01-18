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

class PowerManagerCpp : public QObject, protected QDBusContext {
    Q_OBJECT

    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)

    Q_PROPERTY(uint warningLevel READ warningLevel NOTIFY warningLevelChanged)

    Q_PROPERTY(uint batteryLevelCoarse READ batteryLevelCoarse NOTIFY batteryLevelCoarseChanged)
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
    Q_PROPERTY(bool systemSuspended READ isSystemSuspended NOTIFY systemSuspendedChanged)
    Q_PROPERTY(bool wakelockSupported READ wakelockSupported CONSTANT)
    Q_PROPERTY(bool rtcAlarmSupported READ rtcAlarmSupported CONSTANT)
    Q_PROPERTY(QStringList activeWakelocks READ activeWakelocks NOTIFY activeWakelocksChanged)
    Q_PROPERTY(int wakeLockCount READ wakeLockCount NOTIFY activeWakelocksChanged)

    Q_PROPERTY(QString criticalAction READ criticalAction NOTIFY criticalActionChanged)

  public:
    enum PowerProfile {
        Performance,
        Balanced,
        PowerSaver
    };
    Q_ENUM(PowerProfile)

    explicit PowerManagerCpp(QObject *parent = nullptr);
    ~PowerManagerCpp();

    int batteryLevel() const {
        return m_batteryLevel;
    }
    uint warningLevel() const {
        return m_warningLevel;
    }
    uint batteryLevelCoarse() const {
        return m_batteryLevelCoarse;
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
    bool isSystemSuspended() const {
        return m_systemSuspended;
    }
    bool wakelockSupported() const {
        return m_wakelockSupported;
    }
    bool rtcAlarmSupported() const {
        return m_rtcAlarmSupported;
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
    Q_INVOKABLE void refreshBatteryInfo();
    Q_INVOKABLE void setPowerProfile(const QString &profile);
    Q_INVOKABLE void setIdleTimeout(int seconds);
    Q_INVOKABLE void setAutoSuspendEnabled(bool enabled);

    Q_INVOKABLE bool acquireWakelock(const QString &name);
    Q_INVOKABLE bool releaseWakelock(const QString &name);
    Q_INVOKABLE bool hasWakelock(const QString &name) const;
    Q_INVOKABLE bool inhibitSuspend(const QString &who, const QString &why);
    Q_INVOKABLE void releaseInhibitor();

    Q_INVOKABLE bool setRtcAlarm(qint64 epochTime);
    Q_INVOKABLE bool clearRtcAlarm();

  signals:
    void batteryLevelChanged();
    void warningLevelChanged();
    void batteryLevelCoarseChanged();
    void isChargingChanged();
    void isPluggedInChanged();
    void isPowerSaveModeChanged();
    void estimatedBatteryTimeChanged();
    void powerProfileChanged();
    void criticalActionChanged();
    void idleTimeoutChanged();
    void autoSuspendEnabledChanged();
    void systemSuspendedChanged();
    void criticalBattery();
    void powerError(const QString &message);
    void aboutToSleep();
    void resumedFromSleep();
    void prepareForSuspend();
    void resumedFromSuspend();
    void idleStateChanged(bool idle);
    void activeWakelocksChanged();

  private slots:
    void updateAggregateState();
    void onPrepareForSleep(bool beforeSleep);
    void checkIdleState();

  private:
    void                    setupDBusConnections();
    void                    simulateBatteryUpdate();
    void                    applyCPUGovernor(PowerProfile profile);
    void                    checkCPUGovernorSupport();
    void                    checkWakelockSupport();
    void                    checkRtcAlarmSupport();
    void                    cleanupWakelocks();
    void                    setupDisplayDevice();
    bool                    writeToFile(const QString &path, const QString &content);
    bool                    writeToRtcWakeAlarm(const QString &value);

    QDBusInterface         *m_upowerInterface;
    QDBusInterface         *m_displayDeviceInterface;
    QDBusInterface         *m_logindInterface;
    QTimer                 *m_idleTimer;

    int                     m_batteryLevel;
    uint                    m_warningLevel;
    uint                    m_batteryLevelCoarse;
    bool                    m_isCharging;
    bool                    m_isPluggedIn;
    bool                    m_isPowerSaveMode;
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
    bool                    m_systemSuspended;
    bool                    m_wakelockSupported;
    QString                 m_fallbackMode;

    bool                    m_rtcAlarmSupported;
    QString                 m_criticalAction;
};

#endif
