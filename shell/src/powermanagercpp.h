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

class PowerManagerCpp : public QObject, protected QDBusContext
{
    Q_OBJECT
    // ... properties ...

// ...


    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY isChargingChanged)
    Q_PROPERTY(bool isPluggedIn READ isPluggedIn NOTIFY isPluggedInChanged)
    Q_PROPERTY(bool isPowerSaveMode READ isPowerSaveMode NOTIFY isPowerSaveModeChanged)
    Q_PROPERTY(int estimatedBatteryTime READ estimatedBatteryTime NOTIFY estimatedBatteryTimeChanged)
    Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY powerProfileChanged)
    Q_PROPERTY(bool powerProfilesSupported READ powerProfilesSupported CONSTANT)
    Q_PROPERTY(int idleTimeout READ idleTimeout WRITE setIdleTimeout NOTIFY idleTimeoutChanged)
    Q_PROPERTY(bool autoSuspendEnabled READ autoSuspendEnabled WRITE setAutoSuspendEnabled NOTIFY autoSuspendEnabledChanged)
    Q_PROPERTY(bool systemSuspended READ isSystemSuspended NOTIFY systemSuspendedChanged)
    Q_PROPERTY(bool wakelockSupported READ wakelockSupported CONSTANT)
    Q_PROPERTY(bool rtcAlarmSupported READ rtcAlarmSupported CONSTANT)

public:
    enum PowerProfile {
        Performance,
        Balanced,
        PowerSaver
    };
    Q_ENUM(PowerProfile)

    explicit PowerManagerCpp(QObject* parent = nullptr);
    ~PowerManagerCpp();

    int batteryLevel() const { return m_batteryLevel; }
    bool isCharging() const { return m_isCharging; }
    bool isPluggedIn() const { return m_isPluggedIn; }
    bool isPowerSaveMode() const { return m_isPowerSaveMode; }
    int estimatedBatteryTime() const { return m_estimatedBatteryTime; }
    QString powerProfile() const { return m_powerProfileString; }
    bool powerProfilesSupported() const { return m_powerProfilesSupported; }
    int idleTimeout() const { return m_idleTimeout; }
    bool autoSuspendEnabled() const { return m_autoSuspendEnabled; }
    bool isSystemSuspended() const { return m_systemSuspended; }
    bool wakelockSupported() const { return m_wakelockSupported; }
    bool rtcAlarmSupported() const { return m_rtcAlarmSupported; }

    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setPowerSaveMode(bool enabled);
    Q_INVOKABLE void refreshBatteryInfo();
    Q_INVOKABLE void setPowerProfile(const QString& profile);
    Q_INVOKABLE void setIdleTimeout(int seconds);
    Q_INVOKABLE void setAutoSuspendEnabled(bool enabled);
    
    // Wakelock management
    Q_INVOKABLE bool acquireWakelock(const QString &name);
    Q_INVOKABLE bool releaseWakelock(const QString &name);
    Q_INVOKABLE bool hasWakelock(const QString &name) const;
    Q_INVOKABLE bool inhibitSuspend(const QString &who, const QString &why);
    Q_INVOKABLE void releaseInhibitor();
    
    // RTC alarm support
    Q_INVOKABLE bool setRtcAlarm(qint64 epochTime);
    Q_INVOKABLE bool clearRtcAlarm();

signals:
    void batteryLevelChanged();
    void isChargingChanged();
    void isPluggedInChanged();
    void isPowerSaveModeChanged();
    void estimatedBatteryTimeChanged();
    void powerProfileChanged();
    void idleTimeoutChanged();
    void autoSuspendEnabledChanged();
    void systemSuspendedChanged();
    void criticalBattery();
    void powerError(const QString& message);
    void aboutToSleep();      // Emitted before system suspends
    void resumedFromSleep();  // Emitted after system resumes
    void prepareForSuspend(); // Emitted when system is about to suspend (from PrepareForSleep signal)
    void resumedFromSuspend(); // Emitted when system resumes from suspend
    void idleStateChanged(bool idle);  // Emitted when idle state changes

private slots:
    void updateAggregateState();
    void scanForDevices();
    void onPrepareForSleep(bool beforeSleep);
    void checkIdleState();
    
    // UPower signals
    void deviceAdded(const QDBusObjectPath &path);
    void deviceRemoved(const QDBusObjectPath &path);
    void devicePropertiesChanged(const QString &interface, const QVariantMap &changedProps, const QStringList &invalidatedProps);
    


private:
    void setupDBusConnections();
    void simulateBatteryUpdate();
    void applyCPUGovernor(PowerProfile profile);
    void checkCPUGovernorSupport();
    void checkWakelockSupport();
    void checkRtcAlarmSupport();
    void cleanupWakelocks();
    bool writeToFile(const QString &path, const QString &content);
    bool writeToRtcWakeAlarm(const QString &value);

    QDBusInterface* m_upowerInterface;
    QDBusInterface* m_logindInterface;
    QTimer* m_batteryMonitor;
    QTimer* m_idleTimer;
    
    int m_batteryLevel;
    bool m_isCharging;
    bool m_isPluggedIn;
    bool m_isPowerSaveMode;
    int m_estimatedBatteryTime;
    bool m_hasUPower;
    bool m_hasLogind;
    
    PowerProfile m_currentProfile;
    QString m_powerProfileString;
    bool m_powerProfilesSupported;
    int m_idleTimeout;
    bool m_autoSuspendEnabled;
    bool m_isIdle;
    qint64 m_lastActivityTime;
    
    // Wakelock support
    QMap<QString, bool> m_activeWakelocks;
    QDBusUnixFileDescriptor m_inhibitorFd;
    bool m_systemSuspended;
    bool m_wakelockSupported;
    QString m_fallbackMode;  // "wakelock", "inhibitor", or "none"
    
    struct PowerDevice {
        QString path;
        uint type;      // 1=Line Power, 2=Battery
        bool online;    // For Line Power
        bool isPresent; // For Battery
        int percentage;
        uint state;     // Charging/Discharging/etc
    };

    QMap<QString, PowerDevice> m_devices; // Cache of known devices
    
    // RTC alarm support
    bool m_rtcAlarmSupported;
};

#endif // POWERMANAGERCPP_H


