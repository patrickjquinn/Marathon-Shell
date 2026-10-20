#pragma once

#include <QObject>
#include <QDateTime>
#include <QString>
#include <QVariantList>
#include <QTimer>
#include <qqml.h>

class Power;
class Network;
class BluetoothManager;
class Modem;
class NotificationServiceCpp;
class SettingsManager;

class SystemStatusStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryLevelChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY isChargingChanged)
    Q_PROPERTY(bool isPluggedIn READ isPluggedIn NOTIFY isPluggedInChanged)

    Q_PROPERTY(bool isWifiOn READ isWifiOn NOTIFY isWifiOnChanged)
    Q_PROPERTY(int wifiStrength READ wifiStrength NOTIFY wifiStrengthChanged)
    Q_PROPERTY(QString wifiNetwork READ wifiNetwork NOTIFY wifiNetworkChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(bool ethernetConnected READ ethernetConnected NOTIFY ethernetConnectedChanged)

    Q_PROPERTY(bool isBluetoothOn READ isBluetoothOn NOTIFY isBluetoothOnChanged)
    Q_PROPERTY(
        bool isBluetoothConnected READ isBluetoothConnected NOTIFY isBluetoothConnectedChanged)

    Q_PROPERTY(bool isAirplaneMode READ isAirplaneMode NOTIFY isAirplaneModeChanged)
    Q_PROPERTY(bool isDndMode READ isDndMode NOTIFY isDndModeChanged)

    Q_PROPERTY(int cellularStrength READ cellularStrength NOTIFY cellularStrengthChanged)
    Q_PROPERTY(QString carrier READ carrier NOTIFY carrierChanged)
    Q_PROPERTY(QString dataType READ dataType NOTIFY dataTypeChanged)

    Q_PROPERTY(QDateTime currentTime READ currentTime NOTIFY currentTimeChanged)
    Q_PROPERTY(QString timeString READ timeString NOTIFY timeStringChanged)
    Q_PROPERTY(QString dateString READ dateString NOTIFY dateStringChanged)

    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)

  public:
    explicit SystemStatusStore(Power *powerManager, Network *networkManager,
                               BluetoothManager *bluetoothManager, Modem *modemManager,
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

    bool isBluetoothOn() const;
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

    Q_INVOKABLE void updateTime();
    void             scheduleNextMinute();
    Q_INVOKABLE void addNotification(const QString &title, const QString &message,
                                     const QString &app);

  signals:
    void batteryLevelChanged();
    void isChargingChanged();
    void isPluggedInChanged();

    void isWifiOnChanged();
    void wifiStrengthChanged();
    void wifiNetworkChanged();
    void wifiConnectedChanged();
    void ethernetConnectedChanged();

    void isBluetoothOnChanged();
    void isBluetoothConnectedChanged();

    void isAirplaneModeChanged();
    void isDndModeChanged();

    void cellularStrengthChanged();
    void carrierChanged();
    void dataTypeChanged();

    void currentTimeChanged();
    void timeStringChanged();
    void dateStringChanged();

    void notificationsChanged();

  private:
    void                    updateBluetoothDevices();
    void                    updateNotifications();

    void                    setBatteryLevel(int level);
    void                    setIsCharging(bool charging);
    void                    setIsPluggedIn(bool pluggedIn);
    void                    setIsWifiOn(bool enabled);
    void                    setWifiStrength(int strength);
    void                    setWifiNetwork(const QString &network);
    void                    setWifiConnected(bool connected);
    void                    setEthernetConnected(bool connected);
    void                    setIsBluetoothConnected(bool connected);
    void                    setIsAirplaneMode(bool enabled);
    void                    setIsDndMode(bool enabled);
    void                    setCellularStrength(int strength);
    void                    setCarrier(const QString &carrier);
    void                    setDataType(const QString &dataType);
    void                    setCurrentTime(const QDateTime &time);
    void                    setTimeString(const QString &timeString);
    void                    setDateString(const QString &dateString);
    void                    setNotifications(const QVariantList &notifications);

    Power        *m_powerManager;
    Network      *m_networkManager;
    BluetoothManager       *m_bluetoothManager;
    Modem        *m_modemManager;
    NotificationServiceCpp *m_notificationService;
    SettingsManager        *m_settingsManager;

    int                     m_batteryLevel = 0;
    bool                    m_isCharging   = false;
    bool                    m_isPluggedIn  = false;

    bool                    m_isWifiOn     = true;
    int                     m_wifiStrength = 0;
    QString                 m_wifiNetwork;
    bool                    m_wifiConnected     = false;
    bool                    m_ethernetConnected = false;

    bool                    m_isBluetoothConnected = false;

    bool                    m_isAirplaneMode = false;
    bool                    m_isDndMode      = false;

    int                     m_cellularStrength = 0;
    QString                 m_carrier;
    QString                 m_dataType;

    QDateTime               m_currentTime = QDateTime::currentDateTime();
    QString                 m_timeString;
    QString                 m_dateString;

    QVariantList            m_notifications;

    QTimer                  m_timeTimer;
};
