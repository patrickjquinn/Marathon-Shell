#pragma once

#include <QObject>
#include <QDateTime>
#include <QString>
#include <QVariantList>
#include <QTimer>
#include <qqml.h>

class PowerManagerCpp;
class NetworkManagerCpp;
class BluetoothManager;
class ModemManagerCpp;
class NotificationServiceCpp;
class SettingsManager;

class SystemStatusStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY isChargingChanged)
    Q_PROPERTY(bool isPluggedIn READ isPluggedIn NOTIFY isPluggedInChanged)
    Q_PROPERTY(QString chargingType READ chargingType NOTIFY chargingTypeChanged)

    Q_PROPERTY(bool isWifiOn READ isWifiOn NOTIFY isWifiOnChanged)
    Q_PROPERTY(int wifiStrength READ wifiStrength NOTIFY wifiStrengthChanged)
    Q_PROPERTY(QString wifiNetwork READ wifiNetwork NOTIFY wifiNetworkChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(bool ethernetConnected READ ethernetConnected NOTIFY ethernetConnectedChanged)

    Q_PROPERTY(bool isBluetoothOn READ isBluetoothOn NOTIFY isBluetoothOnChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothDevicesChanged)
    Q_PROPERTY(int bluetoothConnectedDevicesCount READ bluetoothConnectedDevicesCount NOTIFY
                   bluetoothConnectedDevicesCountChanged)
    Q_PROPERTY(
        bool isBluetoothConnected READ isBluetoothConnected NOTIFY isBluetoothConnectedChanged)

    Q_PROPERTY(bool isAirplaneMode READ isAirplaneMode NOTIFY isAirplaneModeChanged)
    Q_PROPERTY(bool isDndMode READ isDndMode NOTIFY isDndModeChanged)

    Q_PROPERTY(int cellularStrength READ cellularStrength NOTIFY cellularStrengthChanged)
    Q_PROPERTY(QString carrier READ carrier NOTIFY carrierChanged)
    Q_PROPERTY(QString dataType READ dataType NOTIFY dataTypeChanged)

    Q_PROPERTY(int cpuUsage READ cpuUsage NOTIFY cpuUsageChanged)
    Q_PROPERTY(int memoryUsage READ memoryUsage NOTIFY memoryUsageChanged)
    Q_PROPERTY(double storageUsed READ storageUsed NOTIFY storageUsedChanged)
    Q_PROPERTY(double storageTotal READ storageTotal NOTIFY storageTotalChanged)

    Q_PROPERTY(QDateTime currentTime READ currentTime NOTIFY currentTimeChanged)
    Q_PROPERTY(QString timeString READ timeString NOTIFY timeStringChanged)
    Q_PROPERTY(QString dateString READ dateString NOTIFY dateStringChanged)

    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int notificationCount READ notificationCount NOTIFY notificationCountChanged)

  public:
    explicit SystemStatusStore(PowerManagerCpp *powerManager, NetworkManagerCpp *networkManager,
                               BluetoothManager *bluetoothManager, ModemManagerCpp *modemManager,
                               NotificationServiceCpp *notificationService,
                               SettingsManager *settingsManager, QObject *parent = nullptr);

    int batteryLevel() const {
        return m_batteryLevel;
    }
    bool isCharging() const {
        return m_isCharging;
    }
    bool isPluggedIn() const {
        return m_isPluggedIn;
    }
    QString chargingType() const {
        return m_chargingType;
    }

    bool isWifiOn() const {
        return m_isWifiOn;
    }
    int wifiStrength() const {
        return m_wifiStrength;
    }
    QString wifiNetwork() const {
        return m_wifiNetwork;
    }
    bool wifiConnected() const {
        return m_wifiConnected;
    }
    bool ethernetConnected() const {
        return m_ethernetConnected;
    }

    bool isBluetoothOn() const {
        return m_isBluetoothOn;
    }
    QVariantList bluetoothDevices() const {
        return m_bluetoothDevices;
    }
    int bluetoothConnectedDevicesCount() const {
        return m_bluetoothConnectedDevicesCount;
    }
    bool isBluetoothConnected() const {
        return m_isBluetoothConnected;
    }

    bool isAirplaneMode() const {
        return m_isAirplaneMode;
    }
    bool isDndMode() const {
        return m_isDndMode;
    }

    int cellularStrength() const {
        return m_cellularStrength;
    }
    QString carrier() const {
        return m_carrier;
    }
    QString dataType() const {
        return m_dataType;
    }

    int cpuUsage() const {
        return m_cpuUsage;
    }
    int memoryUsage() const {
        return m_memoryUsage;
    }
    double storageUsed() const {
        return m_storageUsed;
    }
    double storageTotal() const {
        return m_storageTotal;
    }

    QDateTime currentTime() const {
        return m_currentTime;
    }
    QString timeString() const {
        return m_timeString;
    }
    QString dateString() const {
        return m_dateString;
    }

    QVariantList notifications() const {
        return m_notifications;
    }
    int notificationCount() const {
        return m_notificationCount;
    }

    Q_INVOKABLE void updateTime();
    Q_INVOKABLE void addNotification(const QString &title, const QString &message,
                                     const QString &app);
    Q_INVOKABLE void removeNotification(int notificationId);
    Q_INVOKABLE void clearAllNotifications();
    Q_INVOKABLE void updateSystemInfo();

  signals:
    void batteryLevelChanged();
    void isChargingChanged();
    void isPluggedInChanged();
    void chargingTypeChanged();

    void isWifiOnChanged();
    void wifiStrengthChanged();
    void wifiNetworkChanged();
    void wifiConnectedChanged();
    void ethernetConnectedChanged();

    void isBluetoothOnChanged();
    void bluetoothDevicesChanged();
    void bluetoothConnectedDevicesCountChanged();
    void isBluetoothConnectedChanged();

    void isAirplaneModeChanged();
    void isDndModeChanged();

    void cellularStrengthChanged();
    void carrierChanged();
    void dataTypeChanged();

    void cpuUsageChanged();
    void memoryUsageChanged();
    void storageUsedChanged();
    void storageTotalChanged();

    void currentTimeChanged();
    void timeStringChanged();
    void dateStringChanged();

    void notificationsChanged();
    void notificationCountChanged();

  private:
    void                    updateChargingType();
    void                    updateBluetoothDevices();
    void                    updateNotifications();

    void                    setBatteryLevel(int level);
    void                    setIsCharging(bool charging);
    void                    setIsPluggedIn(bool pluggedIn);
    void                    setChargingType(const QString &type);
    void                    setIsWifiOn(bool enabled);
    void                    setWifiStrength(int strength);
    void                    setWifiNetwork(const QString &network);
    void                    setWifiConnected(bool connected);
    void                    setEthernetConnected(bool connected);
    void                    setIsBluetoothOn(bool enabled);
    void                    setBluetoothDevices(const QVariantList &devices);
    void                    setBluetoothConnectedDevicesCount(int count);
    void                    setIsBluetoothConnected(bool connected);
    void                    setIsAirplaneMode(bool enabled);
    void                    setIsDndMode(bool enabled);
    void                    setCellularStrength(int strength);
    void                    setCarrier(const QString &carrier);
    void                    setDataType(const QString &dataType);
    void                    setCpuUsage(int usage);
    void                    setMemoryUsage(int usage);
    void                    setStorageUsed(double used);
    void                    setStorageTotal(double total);
    void                    setCurrentTime(const QDateTime &time);
    void                    setTimeString(const QString &timeString);
    void                    setDateString(const QString &dateString);
    void                    setNotifications(const QVariantList &notifications);
    void                    setNotificationCount(int count);

    PowerManagerCpp        *m_powerManager;
    NetworkManagerCpp      *m_networkManager;
    BluetoothManager       *m_bluetoothManager;
    ModemManagerCpp        *m_modemManager;
    NotificationServiceCpp *m_notificationService;
    SettingsManager        *m_settingsManager;

    int                     m_batteryLevel = 0;
    bool                    m_isCharging   = false;
    bool                    m_isPluggedIn  = false;
    QString                 m_chargingType = "none";

    bool                    m_isWifiOn     = true;
    int                     m_wifiStrength = 0;
    QString                 m_wifiNetwork;
    bool                    m_wifiConnected     = false;
    bool                    m_ethernetConnected = false;

    bool                    m_isBluetoothOn = false;
    QVariantList            m_bluetoothDevices;
    int                     m_bluetoothConnectedDevicesCount = 0;
    bool                    m_isBluetoothConnected           = false;

    bool                    m_isAirplaneMode = false;
    bool                    m_isDndMode      = false;

    int                     m_cellularStrength = 0;
    QString                 m_carrier;
    QString                 m_dataType;

    int                     m_cpuUsage     = 23;
    int                     m_memoryUsage  = 45;
    double                  m_storageUsed  = 45.2;
    double                  m_storageTotal = 128;

    QDateTime               m_currentTime = QDateTime::currentDateTime();
    QString                 m_timeString;
    QString                 m_dateString;

    QVariantList            m_notifications;
    int                     m_notificationCount = 0;

    QTimer                  m_timeTimer;
};
