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

public:
    explicit PowerManagerCpp(QObject* parent = nullptr);
    ~PowerManagerCpp();

    int batteryLevel() const { return m_batteryLevel; }
    bool isCharging() const { return m_isCharging; }
    bool isPowerSaveMode() const { return m_isPowerSaveMode; }
    int estimatedBatteryTime() const { return m_estimatedBatteryTime; }

    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setPowerSaveMode(bool enabled);
    Q_INVOKABLE void refreshBatteryInfo();

signals:
    void batteryLevelChanged();
    void isChargingChanged();
    void isPowerSaveModeChanged();
    void estimatedBatteryTimeChanged();
    void criticalBattery();
    void powerError(const QString& message);
    void aboutToSleep();      // Emitted before system suspends
    void resumedFromSleep();  // Emitted after system resumes

private slots:
    void queryBatteryState();
    void onPrepareForSleep(bool beforeSleep);

private:
    void setupDBusConnections();
    void simulateBatteryUpdate();

    QDBusInterface* m_upowerInterface;
    QDBusInterface* m_logindInterface;
    QTimer* m_batteryMonitor;
    
    int m_batteryLevel;
    bool m_isCharging;
    bool m_isPowerSaveMode;
    int m_estimatedBatteryTime;
    bool m_hasUPower;
    bool m_hasLogind;
};

#endif // POWERMANAGERCPP_H

