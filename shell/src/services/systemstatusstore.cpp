#include "systemstatusstore.h"
#include "marathon-shell-native/src/bluetooth.cxxqt.h"
#include "marathon-shell-native/src/modem.cxxqt.h"
#include "marathon-shell-native/src/network.cxxqt.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include "src/managers/settingsmanager.h"
#include "src/services/notificationservicecpp.h"
#include <QDateTime>
#include <QLocale>

SystemStatusStore::SystemStatusStore(Power        *powerManager,
                                     Network      *networkManager,
                                     Bluetooth              *bluetoothManager,
                                     Modem        *modemManager,
                                     NotificationServiceCpp *notificationService,
                                     SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_powerManager(powerManager)
    , m_networkManager(networkManager)
    , m_bluetoothManager(bluetoothManager)
    , m_modemManager(modemManager)
    , m_notificationService(notificationService)
    , m_settingsManager(settingsManager) {
    if (m_powerManager) {
        setBatteryLevel(m_powerManager->getBatteryLevel());
        setIsCharging(m_powerManager->getIsCharging());
        setIsPluggedIn(m_powerManager->getIsPluggedIn());
        connect(m_powerManager, &Power::batteryLevelChanged, this,
                [this]() { setBatteryLevel(m_powerManager->getBatteryLevel()); });
        connect(m_powerManager, &Power::isChargingChanged, this,
                [this]() { setIsCharging(m_powerManager->getIsCharging()); });
        connect(m_powerManager, &Power::isPluggedInChanged, this,
                [this]() { setIsPluggedIn(m_powerManager->getIsPluggedIn()); });
    }

    if (m_networkManager) {
        setIsWifiOn(m_networkManager->getWifiEnabled());
        setWifiStrength(m_networkManager->getWifiSignalStrength());
        setWifiNetwork(m_networkManager->getWifiSsid());
        setWifiConnected(m_networkManager->getWifiConnected());
        setEthernetConnected(m_networkManager->getEthernetConnected());
        setIsAirplaneMode(m_networkManager->getAirplaneModeEnabled());
        connect(m_networkManager, &Network::wifiEnabledChanged, this,
                [this]() { setIsWifiOn(m_networkManager->getWifiEnabled()); });
        connect(m_networkManager, &Network::wifiSignalStrengthChanged, this,
                [this]() { setWifiStrength(m_networkManager->getWifiSignalStrength()); });
        connect(m_networkManager, &Network::wifiSsidChanged, this,
                [this]() { setWifiNetwork(m_networkManager->getWifiSsid()); });
        connect(m_networkManager, &Network::wifiConnectedChanged, this,
                [this]() { setWifiConnected(m_networkManager->getWifiConnected()); });
        connect(m_networkManager, &Network::ethernetConnectedChanged, this,
                [this]() { setEthernetConnected(m_networkManager->getEthernetConnected()); });
        connect(m_networkManager, &Network::airplaneModeEnabledChanged, this,
                [this]() { setIsAirplaneMode(m_networkManager->getAirplaneModeEnabled()); });
    }

    if (m_bluetoothManager) {
        updateBluetoothDevices();
        connect(m_bluetoothManager, &Bluetooth::enabledChanged, this,
                &SystemStatusStore::isBluetoothOnChanged);
        connect(m_bluetoothManager, &Bluetooth::pairedDevicesChanged, this,
                [this]() { updateBluetoothDevices(); });
    }

    if (m_modemManager) {
        setCellularStrength(m_modemManager->getSignalStrength());
        setCarrier(m_modemManager->getOperatorName());
        setDataType(m_modemManager->getNetworkType());
        connect(m_modemManager, &Modem::signalStrengthChanged, this,
                [this]() { setCellularStrength(m_modemManager->getSignalStrength()); });
        connect(m_modemManager, &Modem::operatorNameChanged, this,
                [this]() { setCarrier(m_modemManager->getOperatorName()); });
        connect(m_modemManager, &Modem::networkTypeChanged, this,
                [this]() { setDataType(m_modemManager->getNetworkType()); });
    }

    if (m_notificationService) {
        updateNotifications();
        setIsDndMode(m_notificationService->isDndEnabled());
        connect(m_notificationService, &NotificationServiceCpp::notificationsChanged, this,
                [this]() { updateNotifications(); });
        connect(m_notificationService, &NotificationServiceCpp::isDndEnabledChanged, this,
                [this]() { setIsDndMode(m_notificationService->isDndEnabled()); });
    }

    if (m_settingsManager) {
        connect(m_settingsManager, &SettingsManager::timeFormatChanged, this,
                [this]() { updateTime(); });
        connect(m_settingsManager, &SettingsManager::timeZoneChanged, this,
                [this]() { updateTime(); });
    }

    // Clock display is "HH:mm" / "h:mm AP" -- second-granularity, so 59 of
    // every 60 wakeups from a 1Hz timer notified properties that nobody re-
    // rendered for. Snap the timer to the next minute boundary so we wake up
    // exactly when the displayed time changes, not 60x more often than that.
    updateTime();
    m_timeTimer.setSingleShot(true);
    connect(&m_timeTimer, &QTimer::timeout, this, [this]() {
        updateTime();
        scheduleNextMinute();
    });
    scheduleNextMinute();
}

void SystemStatusStore::scheduleNextMinute() {
    // Fire at the next :00 of the wall-clock minute. Add a few ms of slack so
    // the timer doesn't fire just before the minute rolls over due to drift.
    const QDateTime now      = QDateTime::currentDateTime();
    const int       msToNext = 60'000 - (now.time().second() * 1000 + now.time().msec()) + 5;
    m_timeTimer.start(msToNext);
}

void SystemStatusStore::updateTime() {
    setCurrentTime(QDateTime::currentDateTime());
    QString timeFormat = "24h";
    if (m_settingsManager) {
        timeFormat = m_settingsManager->timeFormat();
    }
    const QString timePattern = (timeFormat == "24h") ? "HH:mm" : "h:mm AP";
    setTimeString(QLocale::system().toString(m_currentTime.time(), timePattern));
    setDateString(QLocale::system().toString(m_currentTime.date(), "dddd, MMMM d"));
}

void SystemStatusStore::addNotification(const QString &title, const QString &message,
                                        const QString &app) {
    if (m_notificationService) {
        QVariantMap payload;
        payload["category"] = "message";
        payload["priority"] = "normal";
        m_notificationService->sendNotification(app, title, message, payload);
    }
}

void SystemStatusStore::updateBluetoothDevices() {
    bool connected = false;
    if (m_bluetoothManager) {
        for (const QVariant &device : m_bluetoothManager->getPairedDevices()) {
            if (device.toMap().value("connected").toBool()) {
                connected = true;
                break;
            }
        }
    }
    setIsBluetoothConnected(connected);
}

void SystemStatusStore::updateNotifications() {
    if (!m_notificationService) {
        return;
    }
    setNotifications(m_notificationService->notifications());
}

void SystemStatusStore::setBatteryLevel(int level) {
    if (m_batteryLevel == level) {
        return;
    }
    m_batteryLevel = level;
    emit batteryLevelChanged();
}

void SystemStatusStore::setIsCharging(bool charging) {
    if (m_isCharging == charging) {
        return;
    }
    m_isCharging = charging;
    emit isChargingChanged();
}

void SystemStatusStore::setIsPluggedIn(bool pluggedIn) {
    if (m_isPluggedIn == pluggedIn) {
        return;
    }
    m_isPluggedIn = pluggedIn;
    emit isPluggedInChanged();
}

void SystemStatusStore::setIsWifiOn(bool enabled) {
    if (m_isWifiOn == enabled) {
        return;
    }
    m_isWifiOn = enabled;
    emit isWifiOnChanged();
}

void SystemStatusStore::setWifiStrength(int strength) {
    if (m_wifiStrength == strength) {
        return;
    }
    m_wifiStrength = strength;
    emit wifiStrengthChanged();
}

void SystemStatusStore::setWifiNetwork(const QString &network) {
    if (m_wifiNetwork == network) {
        return;
    }
    m_wifiNetwork = network;
    emit wifiNetworkChanged();
}

void SystemStatusStore::setWifiConnected(bool connected) {
    if (m_wifiConnected == connected) {
        return;
    }
    m_wifiConnected = connected;
    emit wifiConnectedChanged();
}

void SystemStatusStore::setEthernetConnected(bool connected) {
    if (m_ethernetConnected == connected) {
        return;
    }
    m_ethernetConnected = connected;
    emit ethernetConnectedChanged();
}

bool SystemStatusStore::isBluetoothOn() const {
    return m_bluetoothManager ? m_bluetoothManager->getEnabled() : false;
}

void SystemStatusStore::setIsBluetoothConnected(bool connected) {
    if (m_isBluetoothConnected == connected) {
        return;
    }
    m_isBluetoothConnected = connected;
    emit isBluetoothConnectedChanged();
}

void SystemStatusStore::setIsAirplaneMode(bool enabled) {
    if (m_isAirplaneMode == enabled) {
        return;
    }
    m_isAirplaneMode = enabled;
    emit isAirplaneModeChanged();
}

void SystemStatusStore::setIsDndMode(bool enabled) {
    if (m_isDndMode == enabled) {
        return;
    }
    m_isDndMode = enabled;
    emit isDndModeChanged();
}

void SystemStatusStore::setCellularStrength(int strength) {
    if (m_cellularStrength == strength) {
        return;
    }
    m_cellularStrength = strength;
    emit cellularStrengthChanged();
}

void SystemStatusStore::setCarrier(const QString &carrier) {
    if (m_carrier == carrier) {
        return;
    }
    m_carrier = carrier;
    emit carrierChanged();
}

void SystemStatusStore::setDataType(const QString &dataType) {
    if (m_dataType == dataType) {
        return;
    }
    m_dataType = dataType;
    emit dataTypeChanged();
}

void SystemStatusStore::setCurrentTime(const QDateTime &time) {
    if (m_currentTime == time) {
        return;
    }
    m_currentTime = time;
    emit currentTimeChanged();
}

void SystemStatusStore::setTimeString(const QString &timeString) {
    if (m_timeString == timeString) {
        return;
    }
    m_timeString = timeString;
    emit timeStringChanged();
}

void SystemStatusStore::setDateString(const QString &dateString) {
    if (m_dateString == dateString) {
        return;
    }
    m_dateString = dateString;
    emit dateStringChanged();
}

void SystemStatusStore::setNotifications(const QVariantList &notifications) {
    if (m_notifications == notifications) {
        return;
    }
    m_notifications = notifications;
    emit notificationsChanged();
}
