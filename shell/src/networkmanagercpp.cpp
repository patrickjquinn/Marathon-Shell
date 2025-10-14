#include "networkmanagercpp.h"
#include <QDebug>
#include <QDBusMessage>
#include <QDBusError>
#include <QRandomGenerator>

NetworkManagerCpp::NetworkManagerCpp(QObject* parent)
    : QObject(parent)
    , m_nmInterface(nullptr)
    , m_wifiEnabled(true)
    , m_wifiConnected(false)
    , m_wifiSsid("Unknown")
    , m_wifiSignalStrength(0)
    , m_bluetoothEnabled(false)
    , m_airplaneModeEnabled(false)
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
        qDebug() << "[NetworkManagerCpp] Connected to NetworkManager D-Bus";
        setupDBusConnections();
        queryWifiState();
    } else {
        qDebug() << "[NetworkManagerCpp] NetworkManager D-Bus not available:" << m_nmInterface->lastError().message();
        qDebug() << "[NetworkManagerCpp] Using mock mode";
        // Fallback to simulated mode
        m_wifiConnected = true;
        m_wifiSsid = "Home Network";
        m_wifiSignalStrength = 85;
    }
    
    // Setup signal strength monitor
    m_signalMonitor = new QTimer(this);
    m_signalMonitor->setInterval(5000); // Update every 5 seconds
    connect(m_signalMonitor, &QTimer::timeout, this, &NetworkManagerCpp::updateWifiSignalStrength);
    m_signalMonitor->start();
}

NetworkManagerCpp::~NetworkManagerCpp()
{
    if (m_nmInterface) {
        delete m_nmInterface;
    }
}

void NetworkManagerCpp::setupDBusConnections()
{
    if (!m_hasNetworkManager) return;
    
    // Connect to NetworkManager state changes
    QDBusConnection::systemBus().connect(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        "StateChanged",
        this,
        SLOT(queryWifiState())
    );
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
    m_wifiConnected = false;
    emit wifiEnabledChanged();
    emit wifiConnectedChanged();
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
    qDebug() << "[NetworkManagerCpp] Scanning for WiFi networks";
    
    if (m_hasNetworkManager) {
        // Request scan via NetworkManager
        // This would require getting wireless device path and calling RequestScan
        qDebug() << "[NetworkManagerCpp] D-Bus WiFi scan not yet implemented";
    } else {
        qDebug() << "[NetworkManagerCpp] Mock scan - no real networks available";
    }
}

void NetworkManagerCpp::connectToNetwork(const QString& ssid, const QString& password)
{
    qDebug() << "[NetworkManagerCpp] Connecting to network:" << ssid;
    
    if (m_hasNetworkManager) {
        // Create connection profile and activate
        qDebug() << "[NetworkManagerCpp] D-Bus connection not yet implemented";
    } else {
        // Mock connection
        m_wifiConnected = true;
        m_wifiSsid = ssid;
        m_wifiSignalStrength = 85;
        emit wifiConnectedChanged();
        emit wifiSsidChanged();
        emit wifiSignalStrengthChanged();
    }
}

void NetworkManagerCpp::disconnectWifi()
{
    qDebug() << "[NetworkManagerCpp] Disconnecting WiFi";
    
    if (m_hasNetworkManager) {
        // Deactivate active connection
        qDebug() << "[NetworkManagerCpp] D-Bus disconnect not yet implemented";
    }
    
    m_wifiConnected = false;
    emit wifiConnectedChanged();
}

void NetworkManagerCpp::enableBluetooth()
{
    qDebug() << "[NetworkManagerCpp] Enabling Bluetooth";
    m_bluetoothEnabled = true;
    emit bluetoothEnabledChanged();
}

void NetworkManagerCpp::disableBluetooth()
{
    qDebug() << "[NetworkManagerCpp] Disabling Bluetooth";
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
    qDebug() << "[NetworkManagerCpp] Airplane mode:" << enabled;
    m_airplaneModeEnabled = enabled;
    emit airplaneModeEnabledChanged();
    
    if (enabled) {
        disableWifi();
        disableBluetooth();
    }
}

