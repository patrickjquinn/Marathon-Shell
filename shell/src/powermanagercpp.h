#ifndef POWERMANAGERCPP_H
#define POWERMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QTimer>

class PowerManagerCpp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY isChargingChanged)
    Q_PROPERTY(bool isPowerSaveMode READ isPowerSaveMode NOTIFY isPowerSaveModeChanged)
    Q_PROPERTY(int estimatedBatteryTime READ estimatedBatteryTime NOTIFY estimatedBatteryTimeChanged)
    Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY powerProfileChanged)
    Q_PROPERTY(bool powerProfilesSupported READ powerProfilesSupported CONSTANT)
    Q_PROPERTY(int idleTimeout READ idleTimeout WRITE setIdleTimeout NOTIFY idleTimeoutChanged)
    Q_PROPERTY(bool autoSuspendEnabled READ autoSuspendEnabled WRITE setAutoSuspendEnabled NOTIFY autoSuspendEnabledChanged)

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
    bool isPowerSaveMode() const { return m_isPowerSaveMode; }
    int estimatedBatteryTime() const { return m_estimatedBatteryTime; }
    QString powerProfile() const { return m_powerProfileString; }
    bool powerProfilesSupported() const { return m_powerProfilesSupported; }
    int idleTimeout() const { return m_idleTimeout; }
    bool autoSuspendEnabled() const { return m_autoSuspendEnabled; }

    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setPowerSaveMode(bool enabled);
    Q_INVOKABLE void refreshBatteryInfo();
    Q_INVOKABLE void setPowerProfile(const QString& profile);
    Q_INVOKABLE void setIdleTimeout(int seconds);
    Q_INVOKABLE void setAutoSuspendEnabled(bool enabled);

signals:
    void batteryLevelChanged();
    void isChargingChanged();
    void isPowerSaveModeChanged();
    void estimatedBatteryTimeChanged();
    void powerProfileChanged();
    void idleTimeoutChanged();
    void autoSuspendEnabledChanged();
    void criticalBattery();
    void powerError(const QString& message);
    void aboutToSleep();      // Emitted before system suspends
    void resumedFromSleep();  // Emitted after system resumes
    void idleStateChanged(bool idle);  // Emitted when idle state changes

private slots:
    void queryBatteryState();
    void onPrepareForSleep(bool beforeSleep);
    void checkIdleState();

private:
    void setupDBusConnections();
    void simulateBatteryUpdate();
    void applyCPUGovernor(PowerProfile profile);
    void checkCPUGovernorSupport();

    QDBusInterface* m_upowerInterface;
    QDBusInterface* m_logindInterface;
    QTimer* m_batteryMonitor;
    QTimer* m_idleTimer;
    
    int m_batteryLevel;
    bool m_isCharging;
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
};

#endif // POWERMANAGERCPP_H

