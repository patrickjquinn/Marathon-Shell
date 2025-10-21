#include "networkmanagercpp.h"
#include <QDebug>
#include <QDBusMessage>
#include <QDBusError>
#include <QDBusObjectPath>
#include <QDBusMetaType>
#include <QRandomGenerator>

NetworkManagerCpp::NetworkManagerCpp(QObject* parent)
    : QObject(parent)
    , m_nmInterface(nullptr)
    , m_wifiEnabled(true)
    , m_wifiConnected(false)
    , m_wifiSsid("Unknown")
    , m_wifiSignalStrength(0)
    , m_ethernetConnected(false)
    , m_ethernetConnectionName("")
    , m_bluetoothEnabled(false)
    , m_airplaneModeEnabled(false)
    , m_wifiAvailable(false)
    , m_bluetoothAvailable(false)
    , m_hasNetworkManager(false)
{
    qDebug() << "[NetworkManagerCpp] Initializing";
    
    // Try to connect to NetworkManager D-Bus
    m_nmInterface = new QDBusInterface(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        QDBusConnection::systemBus(),
        this
    );
    
    if (m_nmInterface->isValid()) {
        m_hasNetworkManager = true;
        qInfo() << "[NetworkManagerCpp] ✓ Connected to NetworkManager D-Bus";
        
        // Detect hardware availability
        detectHardwareAvailability();
        
        setupDBusConnections();
        queryWifiState();
        queryConnectionState();
        
        qInfo() << "[NetworkManagerCpp] Initial state - WiFi:" << m_wifiConnected << "Ethernet:" << m_ethernetConnected;
    } else {
        qInfo() << "[NetworkManagerCpp] ❌ NetworkManager D-Bus not available:" << m_nmInterface->lastError().message();
        qInfo() << "[NetworkManagerCpp] Using mock mode (no hardware available)";
        // Fallback to simulated mode - no hardware available
        m_wifiAvailable = false;
        m_bluetoothAvailable = false;
        m_wifiEnabled = false;
        m_wifiConnected = false;
        m_wifiSsid = "No WiFi";
        m_wifiSignalStrength = 0;
    }
    
    // Setup signal strength monitor
    m_signalMonitor = new QTimer(this);
    m_signalMonitor->setInterval(5000); // Update every 5 seconds
    connect(m_signalMonitor, &QTimer::timeout, this, &NetworkManagerCpp::updateWifiSignalStrength);
    m_signalMonitor->start();
    
    // Setup connection state monitor
    m_connectionMonitor = new QTimer(this);
    m_connectionMonitor->setInterval(3000); // Check every 3 seconds
    connect(m_connectionMonitor, &QTimer::timeout, this, &NetworkManagerCpp::queryConnectionState);
    if (m_hasNetworkManager) {
        m_connectionMonitor->start();
    }
}

NetworkManagerCpp::~NetworkManagerCpp()
{
    if (m_nmInterface) {
        delete m_nmInterface;
    }
}

void NetworkManagerCpp::detectHardwareAvailability()
{
    if (!m_hasNetworkManager) {
        m_wifiAvailable = false;
        m_bluetoothAvailable = false;
        return;
    }
    
    // Get all devices from NetworkManager
    QDBusReply<QList<QDBusObjectPath>> devicesReply = m_nmInterface->call("GetDevices");
    if (!devicesReply.isValid()) {
        qDebug() << "[NetworkManagerCpp] Failed to get devices:" << devicesReply.error().message();
        m_wifiAvailable = false;
        m_bluetoothAvailable = false;
        return;
    }
    
    QList<QDBusObjectPath> devices = devicesReply.value();
    
    for (const QDBusObjectPath &devicePath : devices) {
        QDBusInterface device(
            "org.freedesktop.NetworkManager",
            devicePath.path(),
            "org.freedesktop.NetworkManager.Device",
            QDBusConnection::systemBus()
        );
        
        if (!device.isValid()) continue;
        
        // Device type: 2 = WiFi, 5 = Bluetooth
        uint deviceType = device.property("DeviceType").toUInt();
        
        if (deviceType == 2) { // NM_DEVICE_TYPE_WIFI
            m_wifiAvailable = true;
            qInfo() << "[NetworkManagerCpp] WiFi hardware detected";
        } else if (deviceType == 5) { // NM_DEVICE_TYPE_BT
            m_bluetoothAvailable = true;
            qInfo() << "[NetworkManagerCpp] Bluetooth hardware detected";
        }
    }
    
    if (!m_wifiAvailable) {
        qInfo() << "[NetworkManagerCpp] No WiFi hardware detected";
        // Disable WiFi state if no hardware
        m_wifiEnabled = false;
        m_wifiConnected = false;
        emit wifiEnabledChanged();
        emit wifiConnectedChanged();
    }
    if (!m_bluetoothAvailable) {
        qInfo() << "[NetworkManagerCpp] No Bluetooth hardware detected";
    }
    
    qInfo() << "[NetworkManagerCpp] Hardware detection complete - WiFi:" << m_wifiAvailable << "BT:" << m_bluetoothAvailable;
}

void NetworkManagerCpp::setupDBusConnections()
{
    if (!m_hasNetworkManager) return;
    
    // Connect to NetworkManager state changes
    bool connected = QDBusConnection::systemBus().connect(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        "StateChanged",
        this,
        SLOT(queryWifiState())
    );
    
    if (!connected) {
        qDebug() << "[NetworkManagerCpp] NetworkManager StateChanged signal connection failed (expected - using polling instead)";
    } else {
        qInfo() << "[NetworkManagerCpp] Connected to NetworkManager StateChanged signal";
    }
}

void NetworkManagerCpp::queryWifiState()
{
    if (!m_hasNetworkManager) return;
    
    // Query WiFi hardware state
    QDBusReply<uint> wifiState = m_nmInterface->call("GetWifiEnabled");
    if (wifiState.isValid()) {
        bool enabled = wifiState.value() != 0;
        if (m_wifiEnabled != enabled) {
            m_wifiEnabled = enabled;
            emit wifiEnabledChanged();
            qDebug() << "[NetworkManagerCpp] WiFi enabled:" << m_wifiEnabled;
        }
    }
}

void NetworkManagerCpp::updateWifiSignalStrength()
{
    if (m_wifiConnected) {
        if (!m_hasNetworkManager) {
            int variation = (QRandomGenerator::global()->bounded(11)) - 5;
            m_wifiSignalStrength = qBound(20, m_wifiSignalStrength + variation, 100);
            emit wifiSignalStrengthChanged();
        } else {
            updateWifiDetails();
        }
    }
}

void NetworkManagerCpp::queryConnectionState()
{
    if (!m_hasNetworkManager) return;
    
    // Get active connections
    QVariant activeConnsVar = m_nmInterface->property("ActiveConnections");
    QList<QDBusObjectPath> activeConns = qdbus_cast<QList<QDBusObjectPath>>(activeConnsVar);
    
    bool hasWifi = false;
    bool hasEthernet = false;
    QString wifiSsid;
    QString wifiDevicePath;
    QString ethernetName;
    
    for (const QDBusObjectPath &connPath : activeConns) {
        QDBusInterface conn(
            "org.freedesktop.NetworkManager",
            connPath.path(),
            "org.freedesktop.NetworkManager.Connection.Active",
            QDBusConnection::systemBus()
        );
        
        if (!conn.isValid()) continue;
        
        QString type = conn.property("Type").toString();
        uint state = conn.property("State").toUInt();
        
        if (state == 2) { // NM_ACTIVE_CONNECTION_STATE_ACTIVATED
            if (type == "802-11-wireless") {
                hasWifi = true;
                
                // Get specific wireless device path for signal strength queries
                QVariant devicesVar = conn.property("Devices");
                QList<QDBusObjectPath> devices = qdbus_cast<QList<QDBusObjectPath>>(devicesVar);
                if (!devices.isEmpty()) {
                    wifiDevicePath = devices.first().path();
                }
                
                // Get connection ID (SSID)
                QString connId = conn.property("Id").toString();
                if (!connId.isEmpty()) {
                    wifiSsid = connId;
                }
                
            } else if (type == "802-3-ethernet") {
                hasEthernet = true;
                
                // Get connection ID (Ethernet connection name)
                QString connId = conn.property("Id").toString();
                if (!connId.isEmpty()) {
                    ethernetName = connId;
                }
            }
        }
    }
    
    // Update WiFi state
    if (m_wifiConnected != hasWifi) {
        m_wifiConnected = hasWifi;
        emit wifiConnectedChanged();
        qInfo() << "[NetworkManagerCpp] WiFi connected:" << hasWifi;
    }
    
    if (hasWifi && !wifiSsid.isEmpty() && m_wifiSsid != wifiSsid) {
        m_wifiSsid = wifiSsid;
        emit wifiSsidChanged();
        qInfo() << "[NetworkManagerCpp] WiFi SSID:" << wifiSsid;
    }
    
    if (!wifiDevicePath.isEmpty()) {
        m_activeWifiDevicePath = wifiDevicePath;
        // Query signal strength for this connection
        updateWifiDetails();
    }
    
    // Update Ethernet state
    if (m_ethernetConnected != hasEthernet) {
        m_ethernetConnected = hasEthernet;
        emit ethernetConnectedChanged();
        qInfo() << "[NetworkManagerCpp] Ethernet connected:" << hasEthernet;
    }
    
    if (hasEthernet && !ethernetName.isEmpty() && m_ethernetConnectionName != ethernetName) {
        m_ethernetConnectionName = ethernetName;
        emit ethernetConnectionNameChanged();
        qInfo() << "[NetworkManagerCpp] Ethernet connection:" << ethernetName;
    }
}

void NetworkManagerCpp::updateWifiDetails()
{
    if (!m_hasNetworkManager || m_activeWifiDevicePath.isEmpty()) return;
    
    QDBusInterface wireless(
        "org.freedesktop.NetworkManager",
        m_activeWifiDevicePath,
        "org.freedesktop.NetworkManager.Device.Wireless",
        QDBusConnection::systemBus()
    );
    
    if (!wireless.isValid()) return;
    
    QVariant apPathVar = wireless.property("ActiveAccessPoint");
    QDBusObjectPath apPath = qdbus_cast<QDBusObjectPath>(apPathVar);
    
    if (apPath.path() == "/" || apPath.path().isEmpty()) return;
    
    // Cache the AP path to avoid repeated queries
    if (m_activeApPath == apPath.path()) {
        // If same AP, just query signal strength
        QDBusInterface ap(
            "org.freedesktop.NetworkManager",
            apPath.path(),
            "org.freedesktop.NetworkManager.AccessPoint",
            QDBusConnection::systemBus()
        );
        
        if (ap.isValid()) {
            uint strength = ap.property("Strength").toUInt(); // 0-100
            if (m_wifiSignalStrength != static_cast<int>(strength)) {
                m_wifiSignalStrength = strength;
                emit wifiSignalStrengthChanged();
            }
        }
    } else {
        // New AP, query everything
        m_activeApPath = apPath.path();
        
        QDBusInterface ap(
            "org.freedesktop.NetworkManager",
            apPath.path(),
            "org.freedesktop.NetworkManager.AccessPoint",
            QDBusConnection::systemBus()
        );
        
        if (ap.isValid()) {
            uint strength = ap.property("Strength").toUInt();
            if (m_wifiSignalStrength != static_cast<int>(strength)) {
                m_wifiSignalStrength = strength;
                emit wifiSignalStrengthChanged();
                qDebug() << "[NetworkManagerCpp] WiFi signal strength:" << strength << "%";
            }
        }
    }
}

void NetworkManagerCpp::enableWifi()
{
    qDebug() << "[NetworkManagerCpp] Enabling WiFi";
    
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("Enable", true);
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to enable WiFi:" << reply.error().message();
            emit networkError("Failed to enable WiFi");
            return;
        }
    }
    
    m_wifiEnabled = true;
    emit wifiEnabledChanged();
}

void NetworkManagerCpp::disableWifi()
{
    qDebug() << "[NetworkManagerCpp] Disabling WiFi";
    
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("Enable", false);
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to disable WiFi:" << reply.error().message();
            emit networkError("Failed to disable WiFi");
            return;
        }
    }
    m_wifiEnabled = false;
    emit wifiEnabledChanged();
}

void NetworkManagerCpp::toggleWifi()
{
    if (m_wifiEnabled) {
        disableWifi();
    } else {
        enableWifi();
    }
}

void NetworkManagerCpp::scanWifi()
{
    qDebug() << "[NetworkManagerCpp] Scanning for WiFi networks...";
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("RequestScan", QVariantMap());
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to request WiFi scan:" << reply.error().message();
            emit networkError("Failed to request WiFi scan");
        }
    }
}

void NetworkManagerCpp::connectToNetwork(const QString& ssid, const QString& password)
{
    qDebug() << "[NetworkManagerCpp] Connecting to network:" << ssid;
    // This is a simplified example. Real implementation would involve
    // creating/activating a connection profile.
    // For now, we'll just simulate connection.
    m_wifiSsid = ssid;
    m_wifiConnected = true;
    emit wifiSsidChanged();
    emit wifiConnectedChanged();
}

void NetworkManagerCpp::disconnectWifi()
{
    qDebug() << "[NetworkManagerCpp] Disconnecting WiFi";
    m_wifiConnected = false;
    m_wifiSsid = "Disconnected";
    emit wifiConnectedChanged();
    emit wifiSsidChanged();
}

void NetworkManagerCpp::enableBluetooth()
{
    qDebug() << "[NetworkManagerCpp] Enabling Bluetooth";
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("SetProperty", "BluetoothEnabled", QVariant(true));
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to enable Bluetooth:" << reply.error().message();
            emit networkError("Failed to enable Bluetooth");
            return;
        }
    }
    m_bluetoothEnabled = true;
    emit bluetoothEnabledChanged();
}

void NetworkManagerCpp::disableBluetooth()
{
    qDebug() << "[NetworkManagerCpp] Disabling Bluetooth";
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("SetProperty", "BluetoothEnabled", QVariant(false));
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to disable Bluetooth:" << reply.error().message();
            emit networkError("Failed to disable Bluetooth");
            return;
        }
    }
    m_bluetoothEnabled = false;
    emit bluetoothEnabledChanged();
}

void NetworkManagerCpp::toggleBluetooth()
{
    if (m_bluetoothEnabled) {
        disableBluetooth();
    } else {
        enableBluetooth();
    }
}

void NetworkManagerCpp::setAirplaneMode(bool enabled)
{
    qDebug() << "[NetworkManagerCpp] Setting Airplane Mode to:" << enabled;
    if (m_hasNetworkManager) {
        QDBusReply<void> reply = m_nmInterface->call("SetProperty", "AirplaneMode", QVariant(enabled));
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to set Airplane Mode:" << reply.error().message();
            emit networkError("Failed to set Airplane Mode");
            return;
        }
    }
    m_airplaneModeEnabled = enabled;
    emit airplaneModeEnabledChanged();
}
