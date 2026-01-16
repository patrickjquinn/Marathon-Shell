#include "systemstatusstore.h"
#include "src/managers/bluetoothmanager.h"
#include "src/managers/modemmanagercpp.h"
#include "src/managers/networkmanagercpp.h"
#include "src/managers/powermanagercpp.h"
#include "src/managers/settingsmanager.h"
#include "src/services/notificationservicecpp.h"
#include <QDateTime>
#include <QLocale>
#include <QRandomGenerator>

SystemStatusStore::SystemStatusStore(PowerManagerCpp        *powerManager,
                                     NetworkManagerCpp      *networkManager,
                                     BluetoothManager       *bluetoothManager,
                                     ModemManagerCpp        *modemManager,
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
        setBatteryLevel(m_powerManager->batteryLevel());
        setIsCharging(m_powerManager->isCharging());
        setIsPluggedIn(m_powerManager->isPluggedIn());
        updateChargingType();
        connect(m_powerManager, &PowerManagerCpp::batteryLevelChanged, this,
                [this]() { setBatteryLevel(m_powerManager->batteryLevel()); });
        connect(m_powerManager, &PowerManagerCpp::isChargingChanged, this, [this]() {
            setIsCharging(m_powerManager->isCharging());
            updateChargingType();
        });
        connect(m_powerManager, &PowerManagerCpp::isPluggedInChanged, this,
                [this]() { setIsPluggedIn(m_powerManager->isPluggedIn()); });
    }

    if (m_networkManager) {
        setIsWifiOn(m_networkManager->wifiEnabled());
        setWifiStrength(m_networkManager->wifiSignalStrength());
        setWifiNetwork(m_networkManager->wifiSsid());
        setWifiConnected(m_networkManager->wifiConnected());
        setEthernetConnected(m_networkManager->ethernetConnected());
        setIsAirplaneMode(m_networkManager->airplaneModeEnabled());
        connect(m_networkManager, &NetworkManagerCpp::wifiEnabledChanged, this,
                [this]() { setIsWifiOn(m_networkManager->wifiEnabled()); });
        connect(m_networkManager, &NetworkManagerCpp::wifiSignalStrengthChanged, this,
                [this]() { setWifiStrength(m_networkManager->wifiSignalStrength()); });
        connect(m_networkManager, &NetworkManagerCpp::wifiSsidChanged, this,
                [this]() { setWifiNetwork(m_networkManager->wifiSsid()); });
        connect(m_networkManager, &NetworkManagerCpp::wifiConnectedChanged, this,
                [this]() { setWifiConnected(m_networkManager->wifiConnected()); });
        connect(m_networkManager, &NetworkManagerCpp::ethernetConnectedChanged, this,
                [this]() { setEthernetConnected(m_networkManager->ethernetConnected()); });
        connect(m_networkManager, &NetworkManagerCpp::airplaneModeEnabledChanged, this,
                [this]() { setIsAirplaneMode(m_networkManager->airplaneModeEnabled()); });
    }

    if (m_bluetoothManager) {
        setIsBluetoothOn(m_bluetoothManager->enabled());
        updateBluetoothDevices();
        connect(m_bluetoothManager, &BluetoothManager::enabledChanged, this,
                [this]() { setIsBluetoothOn(m_bluetoothManager->enabled()); });
        connect(m_bluetoothManager, &BluetoothManager::pairedDevicesChanged, this,
                [this]() { updateBluetoothDevices(); });
    }

    if (m_modemManager) {
        setCellularStrength(m_modemManager->signalStrength());
        setCarrier(m_modemManager->operatorName());
        setDataType(m_modemManager->networkType());
        connect(m_modemManager, &ModemManagerCpp::signalStrengthChanged, this,
                [this]() { setCellularStrength(m_modemManager->signalStrength()); });
        connect(m_modemManager, &ModemManagerCpp::operatorNameChanged, this,
                [this]() { setCarrier(m_modemManager->operatorName()); });
        connect(m_modemManager, &ModemManagerCpp::networkTypeChanged, this,
                [this]() { setDataType(m_modemManager->networkType()); });
    }

    if (m_notificationService) {
        updateNotifications();
        setNotificationCount(m_notificationService->unreadCount());
        setIsDndMode(m_notificationService->isDndEnabled());
        connect(m_notificationService, &NotificationServiceCpp::notificationsChanged, this,
                [this]() { updateNotifications(); });
        connect(m_notificationService, &NotificationServiceCpp::unreadCountChanged, this,
                [this]() { setNotificationCount(m_notificationService->unreadCount()); });
        connect(m_notificationService, &NotificationServiceCpp::isDndEnabledChanged, this,
                [this]() { setIsDndMode(m_notificationService->isDndEnabled()); });
    }

    if (m_settingsManager) {
        connect(m_settingsManager, &SettingsManager::timeFormatChanged, this,
                [this]() { updateTime(); });
    }

    updateTime();
    m_timeTimer.setInterval(1000);
    m_timeTimer.setSingleShot(false);
    connect(&m_timeTimer, &QTimer::timeout, this, &SystemStatusStore::updateTime);
    m_timeTimer.start();
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

void SystemStatusStore::removeNotification(int notificationId) {
    if (m_notificationService) {
        m_notificationService->dismissNotification(notificationId);
    }
}

void SystemStatusStore::clearAllNotifications() {
    if (m_notificationService) {
        m_notificationService->dismissAllNotifications();
    }
}

void SystemStatusStore::updateSystemInfo() {
    setCpuUsage(QRandomGenerator::global()->bounded(10, 41));
    setMemoryUsage(QRandomGenerator::global()->bounded(35, 56));
}

void SystemStatusStore::updateChargingType() {
    setChargingType(m_isCharging ? "usb" : "none");
}

void SystemStatusStore::updateBluetoothDevices() {
    QVariantList devices;
    int          connectedCount = 0;
    if (m_bluetoothManager) {
        const QList<QObject *> paired = m_bluetoothManager->pairedDevices();
        for (QObject *device : paired) {
            devices.append(QVariant::fromValue(device));
            if (device && device->property("connected").toBool()) {
                connectedCount++;
            }
        }
    }
    setBluetoothDevices(devices);
    setBluetoothConnectedDevicesCount(connectedCount);
    setIsBluetoothConnected(connectedCount > 0);
}

void SystemStatusStore::updateNotifications() {
    if (!m_notificationService) {
        return;
    }
    setNotifications(m_notificationService->notifications());
    setNotificationCount(m_notificationService->unreadCount());
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

void SystemStatusStore::setChargingType(const QString &type) {
    if (m_chargingType == type) {
        return;
    }
    m_chargingType = type;
    emit chargingTypeChanged();
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

void SystemStatusStore::setIsBluetoothOn(bool enabled) {
    if (m_isBluetoothOn == enabled) {
        return;
    }
    m_isBluetoothOn = enabled;
    emit isBluetoothOnChanged();
}

void SystemStatusStore::setBluetoothDevices(const QVariantList &devices) {
    if (m_bluetoothDevices == devices) {
        return;
    }
    m_bluetoothDevices = devices;
    emit bluetoothDevicesChanged();
}

void SystemStatusStore::setBluetoothConnectedDevicesCount(int count) {
    if (m_bluetoothConnectedDevicesCount == count) {
        return;
    }
    m_bluetoothConnectedDevicesCount = count;
    emit bluetoothConnectedDevicesCountChanged();
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

void SystemStatusStore::setCpuUsage(int usage) {
    if (m_cpuUsage == usage) {
        return;
    }
    m_cpuUsage = usage;
    emit cpuUsageChanged();
}

void SystemStatusStore::setMemoryUsage(int usage) {
    if (m_memoryUsage == usage) {
        return;
    }
    m_memoryUsage = usage;
    emit memoryUsageChanged();
}

void SystemStatusStore::setStorageUsed(double used) {
    if (qFuzzyCompare(m_storageUsed, used)) {
        return;
    }
    m_storageUsed = used;
    emit storageUsedChanged();
}

void SystemStatusStore::setStorageTotal(double total) {
    if (qFuzzyCompare(m_storageTotal, total)) {
        return;
    }
    m_storageTotal = total;
    emit storageTotalChanged();
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

void SystemStatusStore::setNotificationCount(int count) {
    if (m_notificationCount == count) {
        return;
    }
    m_notificationCount = count;
    emit notificationCountChanged();
}
