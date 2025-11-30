#include "networkmanagercpp.h"
#include <QDebug>
#include <QDBusMessage>
#include <QDBusError>
#include <QDBusObjectPath>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QRandomGenerator>
#include <QUuid>

NetworkManagerCpp::NetworkManagerCpp(QObject *parent)
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
    , m_wifiDevicePath("")
    , m_scanTimer(nullptr)
    , m_hotspotActive(false) {
    qDebug() << "[NetworkManagerCpp] Initializing";

    // Try to connect to NetworkManager D-Bus
    m_nmInterface =
        new QDBusInterface("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                           "org.freedesktop.NetworkManager", QDBusConnection::systemBus(), this);

    if (m_nmInterface->isValid()) {
        m_hasNetworkManager = true;
        qInfo() << "[NetworkManagerCpp] ✓ Connected to NetworkManager D-Bus";

        // Detect hardware availability
        detectHardwareAvailability();

        setupDBusConnections();
        queryWifiState();
        queryConnectionState();

        qInfo() << "[NetworkManagerCpp] Initial state - WiFi:" << m_wifiConnected
                << "Ethernet:" << m_ethernetConnected;
    } else {
        qInfo() << "[NetworkManagerCpp]  NetworkManager D-Bus not available:"
                << m_nmInterface->lastError().message();
        qInfo() << "[NetworkManagerCpp] Using mock mode (no hardware available)";
        // Fallback to simulated mode - no hardware available
        m_wifiAvailable      = false;
        m_bluetoothAvailable = false;
        m_wifiEnabled        = false;
        m_wifiConnected      = false;
        m_wifiSsid           = "No WiFi";
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

    // Setup WiFi scan timer (auto-scan every 30 seconds when WiFi is enabled)
    m_scanTimer = new QTimer(this);
    m_scanTimer->setInterval(30000); // Scan every 30 seconds
    connect(m_scanTimer, &QTimer::timeout, this, &NetworkManagerCpp::scanAccessPoints);
    if (m_hasNetworkManager && m_wifiAvailable && m_wifiEnabled) {
        // Do initial scan
        QTimer::singleShot(1000, this, &NetworkManagerCpp::scanAccessPoints);
        m_scanTimer->start();
    }
}

NetworkManagerCpp::~NetworkManagerCpp() {
    if (m_nmInterface) {
        delete m_nmInterface;
    }
}

void NetworkManagerCpp::detectHardwareAvailability() {
    if (!m_hasNetworkManager) {
        m_wifiAvailable      = false;
        m_bluetoothAvailable = false;
        return;
    }

    // Get all devices from NetworkManager
    QDBusReply<QList<QDBusObjectPath>> devicesReply = m_nmInterface->call("GetDevices");
    if (!devicesReply.isValid()) {
        qDebug() << "[NetworkManagerCpp] Failed to get devices:" << devicesReply.error().message();
        m_wifiAvailable      = false;
        m_bluetoothAvailable = false;
        return;
    }

    QList<QDBusObjectPath> devices = devicesReply.value();

    for (const QDBusObjectPath &devicePath : devices) {
        QDBusInterface device("org.freedesktop.NetworkManager", devicePath.path(),
                              "org.freedesktop.NetworkManager.Device",
                              QDBusConnection::systemBus());

        if (!device.isValid())
            continue;

        // Device type: 2 = WiFi, 5 = Bluetooth
        uint deviceType = device.property("DeviceType").toUInt();

        if (deviceType == 2) { // NM_DEVICE_TYPE_WIFI
            m_wifiAvailable  = true;
            m_wifiDevicePath = devicePath.path(); // Store for scanning
            qInfo() << "[NetworkManagerCpp] WiFi hardware detected at" << m_wifiDevicePath;
        } else if (deviceType == 5) { // NM_DEVICE_TYPE_BT
            m_bluetoothAvailable = true;
            qInfo() << "[NetworkManagerCpp] Bluetooth hardware detected";
        }
    }

    if (!m_wifiAvailable) {
        qInfo() << "[NetworkManagerCpp] No WiFi hardware detected";
        // Disable WiFi state if no hardware
        m_wifiEnabled   = false;
        m_wifiConnected = false;
        emit wifiEnabledChanged();
        emit wifiConnectedChanged();
    }
    if (!m_bluetoothAvailable) {
        qInfo() << "[NetworkManagerCpp] No Bluetooth hardware detected";
    }

    qInfo() << "[NetworkManagerCpp] Hardware detection complete - WiFi:" << m_wifiAvailable
            << "BT:" << m_bluetoothAvailable;
}

void NetworkManagerCpp::setupDBusConnections() {
    if (!m_hasNetworkManager)
        return;

    // Connect to NetworkManager state changes
    bool connected = QDBusConnection::systemBus().connect(
        "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager", "StateChanged", this, SLOT(queryWifiState()));

    if (!connected) {
        qDebug() << "[NetworkManagerCpp] NetworkManager StateChanged signal connection failed "
                    "(expected - using polling instead)";
    } else {
        qInfo() << "[NetworkManagerCpp] Connected to NetworkManager StateChanged signal";
    }
}

void NetworkManagerCpp::queryWifiState() {
    if (!m_hasNetworkManager)
        return;

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

void NetworkManagerCpp::updateWifiSignalStrength() {
    if (m_wifiConnected) {
        if (!m_hasNetworkManager) {
            int variation        = (QRandomGenerator::global()->bounded(11)) - 5;
            m_wifiSignalStrength = qBound(20, m_wifiSignalStrength + variation, 100);
            emit wifiSignalStrengthChanged();
        } else {
            updateWifiDetails();
        }
    }
}

void NetworkManagerCpp::queryConnectionState() {
    if (!m_hasNetworkManager)
        return;

    // Get active connections
    QVariant               activeConnsVar = m_nmInterface->property("ActiveConnections");
    QList<QDBusObjectPath> activeConns    = qdbus_cast<QList<QDBusObjectPath>>(activeConnsVar);

    bool                   hasWifi     = false;
    bool                   hasEthernet = false;
    QString                wifiSsid;
    QString                wifiDevicePath;
    QString                ethernetName;

    for (const QDBusObjectPath &connPath : activeConns) {
        QDBusInterface conn("org.freedesktop.NetworkManager", connPath.path(),
                            "org.freedesktop.NetworkManager.Connection.Active",
                            QDBusConnection::systemBus());

        if (!conn.isValid())
            continue;

        QString type  = conn.property("Type").toString();
        uint    state = conn.property("State").toUInt();

        if (state == 2) { // NM_ACTIVE_CONNECTION_STATE_ACTIVATED
            if (type == "802-11-wireless") {
                hasWifi = true;

                // Get specific wireless device path for signal strength queries
                QVariant               devicesVar = conn.property("Devices");
                QList<QDBusObjectPath> devices    = qdbus_cast<QList<QDBusObjectPath>>(devicesVar);
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

void NetworkManagerCpp::updateWifiDetails() {
    if (!m_hasNetworkManager || m_activeWifiDevicePath.isEmpty())
        return;

    QDBusInterface wireless("org.freedesktop.NetworkManager", m_activeWifiDevicePath,
                            "org.freedesktop.NetworkManager.Device.Wireless",
                            QDBusConnection::systemBus());

    if (!wireless.isValid())
        return;

    QVariant        apPathVar = wireless.property("ActiveAccessPoint");
    QDBusObjectPath apPath    = qdbus_cast<QDBusObjectPath>(apPathVar);

    if (apPath.path() == "/" || apPath.path().isEmpty())
        return;

    // Cache the AP path to avoid repeated queries
    if (m_activeApPath == apPath.path()) {
        // If same AP, just query signal strength
        QDBusInterface ap("org.freedesktop.NetworkManager", apPath.path(),
                          "org.freedesktop.NetworkManager.AccessPoint",
                          QDBusConnection::systemBus());

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

        QDBusInterface ap("org.freedesktop.NetworkManager", apPath.path(),
                          "org.freedesktop.NetworkManager.AccessPoint",
                          QDBusConnection::systemBus());

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

void NetworkManagerCpp::enableWifi() {
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

void NetworkManagerCpp::disableWifi() {
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

void NetworkManagerCpp::toggleWifi() {
    if (m_wifiEnabled) {
        disableWifi();
    } else {
        enableWifi();
    }
}

void NetworkManagerCpp::scanWifi() {
    qDebug() << "[NetworkManagerCpp] User requested WiFi scan";
    if (m_hasNetworkManager && !m_wifiDevicePath.isEmpty()) {
        // Request scan on the WiFi device
        QDBusInterface wifiDevice("org.freedesktop.NetworkManager", m_wifiDevicePath,
                                  "org.freedesktop.NetworkManager.Device.Wireless",
                                  QDBusConnection::systemBus());

        if (wifiDevice.isValid()) {
            QDBusReply<void> reply = wifiDevice.call("RequestScan", QVariantMap());
            if (reply.isValid()) {
                qDebug() << "[NetworkManagerCpp] WiFi scan requested successfully";
                // Wait 2 seconds for scan to complete, then get access points
                QTimer::singleShot(2000, this, &NetworkManagerCpp::scanAccessPoints);
            } else {
                qDebug() << "[NetworkManagerCpp] Failed to request WiFi scan:"
                         << reply.error().message();
                emit networkError("Failed to scan for networks");
            }
        }
    } else {
        qDebug() << "[NetworkManagerCpp] Cannot scan: WiFi not available or no device path";
    }
}

void NetworkManagerCpp::scanAccessPoints() {
    if (!m_hasNetworkManager || m_wifiDevicePath.isEmpty()) {
        return;
    }

    qDebug() << "[NetworkManagerCpp] Scanning access points...";

    QDBusInterface wifiDevice("org.freedesktop.NetworkManager", m_wifiDevicePath,
                              "org.freedesktop.NetworkManager.Device.Wireless",
                              QDBusConnection::systemBus());

    if (!wifiDevice.isValid()) {
        qDebug() << "[NetworkManagerCpp] WiFi device interface invalid";
        return;
    }

    // Get list of access points
    QVariant               accessPointsVar = wifiDevice.property("AccessPoints");
    QList<QDBusObjectPath> accessPoints    = qdbus_cast<QList<QDBusObjectPath>>(accessPointsVar);

    qDebug() << "[NetworkManagerCpp] Found" << accessPoints.size() << "access points";

    m_availableNetworks.clear();

    for (const QDBusObjectPath &apPath : accessPoints) {
        processAccessPoint(apPath.path());
    }

    qDebug() << "[NetworkManagerCpp] Processed" << m_availableNetworks.size() << "networks";
    emit availableNetworksChanged();
}

void NetworkManagerCpp::processAccessPoint(const QString &apPath) {
    QDBusInterface accessPoint("org.freedesktop.NetworkManager", apPath,
                               "org.freedesktop.NetworkManager.AccessPoint",
                               QDBusConnection::systemBus());

    if (!accessPoint.isValid()) {
        return;
    }

    // Get SSID (comes as byte array)
    QVariant   ssidVar   = accessPoint.property("Ssid");
    QByteArray ssidBytes = ssidVar.toByteArray();
    QString    ssid      = QString::fromUtf8(ssidBytes);

    // Skip hidden networks or invalid SSIDs
    if (ssid.isEmpty()) {
        return;
    }

    // Get signal strength (0-100)
    uint strength = accessPoint.property("Strength").toUInt();

    // Get security flags
    uint    flags    = accessPoint.property("Flags").toUInt();
    uint    wpaFlags = accessPoint.property("WpaFlags").toUInt();
    uint    rsnFlags = accessPoint.property("RsnFlags").toUInt();

    bool    isSecured    = (wpaFlags != 0 || rsnFlags != 0);
    QString securityType = "Open";

    if (rsnFlags != 0) {
        securityType = "WPA2/WPA3";
    } else if (wpaFlags != 0) {
        securityType = "WPA";
    }

    // Get frequency/mode
    uint frequency = accessPoint.property("Frequency").toUInt();

    // Create network object
    QVariantMap network;
    network["ssid"]      = ssid;
    network["strength"]  = (int)strength;
    network["secured"]   = isSecured;
    network["security"]  = securityType;
    network["frequency"] = (int)frequency;
    network["path"]      = apPath;
    network["connected"] =
        (m_wifiConnected && m_wifiSsid == ssid); // Mark if this is the active connection

    // Check if we already have this SSID (keep strongest signal)
    bool found = false;
    for (int i = 0; i < m_availableNetworks.size(); ++i) {
        QVariantMap existing = m_availableNetworks[i].toMap();
        if (existing["ssid"].toString() == ssid) {
            // Keep the one with stronger signal
            if ((int)strength > existing["strength"].toInt()) {
                m_availableNetworks[i] = network;
            }
            found = true;
            break;
        }
    }

    if (!found) {
        m_availableNetworks.append(network);
    }
}

void NetworkManagerCpp::connectToNetwork(const QString &ssid, const QString &password) {
    qDebug() << "[NetworkManagerCpp] Attempting to connect to:" << ssid;

    if (!m_hasNetworkManager || m_wifiDevicePath.isEmpty()) {
        qWarning()
            << "[NetworkManagerCpp] Cannot connect: NetworkManager or WiFi device not available";
        emit connectionFailed("WiFi not available");
        return;
    }

    // Find the access point for this SSID
    QString apPath;
    bool    isSecured = false;

    for (const QVariant &netVar : m_availableNetworks) {
        QVariantMap net = netVar.toMap();
        if (net["ssid"].toString() == ssid) {
            apPath    = net["path"].toString();
            isSecured = net["secured"].toBool();
            break;
        }
    }

    if (apPath.isEmpty()) {
        qWarning() << "[NetworkManagerCpp] Access point not found for SSID:" << ssid;
        emit connectionFailed("Network not found");
        return;
    }

    qDebug() << "[NetworkManagerCpp] Found AP at:" << apPath << "Secured:" << isSecured;

    // Build connection settings
    QMap<QString, QMap<QString, QVariant>> connectionSettings;

    // Connection settings
    QMap<QString, QVariant> connection;
    connection["type"]               = "802-11-wireless";
    connection["uuid"]               = QUuid::createUuid().toString().remove('{').remove('}');
    connection["id"]                 = ssid;
    connection["autoconnect"]        = true; // Auto-reconnect on boot
    connectionSettings["connection"] = connection;

    // Wireless settings
    QMap<QString, QVariant> wireless;
    wireless["ssid"]                      = ssid.toUtf8(); // SSID as byte array
    wireless["mode"]                      = "infrastructure";
    connectionSettings["802-11-wireless"] = wireless;

    // Security settings (if network is secured)
    if (isSecured && !password.isEmpty()) {
        QMap<QString, QVariant> wirelessSecurity;
        wirelessSecurity["key-mgmt"]                   = "wpa-psk";
        wirelessSecurity["auth-alg"]                   = "open";
        wirelessSecurity["psk"]                        = password;
        connectionSettings["802-11-wireless-security"] = wirelessSecurity;
    }

    // IPv4 settings (DHCP)
    QMap<QString, QVariant> ipv4;
    ipv4["method"]             = "auto";
    connectionSettings["ipv4"] = ipv4;

    // IPv6 settings (auto)
    QMap<QString, QVariant> ipv6;
    ipv6["method"]             = "auto";
    connectionSettings["ipv6"] = ipv6;

    qDebug() << "[NetworkManagerCpp] Calling AddAndActivateConnection...";

    // Call AddAndActivateConnection
    QDBusMessage msg = QDBusMessage::createMethodCall(
        "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager", "AddAndActivateConnection");

    // Convert QMap to QVariantMap for D-Bus
    QVariantMap dbusSettings;
    for (auto it = connectionSettings.begin(); it != connectionSettings.end(); ++it) {
        dbusSettings[it.key()] = QVariant::fromValue(it.value());
    }

    msg << QVariant::fromValue(dbusSettings);
    msg << QVariant::fromValue(QDBusObjectPath(m_wifiDevicePath));
    msg << QVariant::fromValue(QDBusObjectPath(apPath));

    QDBusPendingCall         call    = QDBusConnection::systemBus().asyncCall(msg);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, ssid](QDBusPendingCallWatcher *watcher) {
                QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply = *watcher;

                if (reply.isError()) {
                    QString error = reply.error().message();
                    qWarning() << "[NetworkManagerCpp] Connection failed:" << error;

                    // Parse common errors
                    QString userError;
                    if (error.contains("secrets-required") || error.contains("no-secrets")) {
                        userError = "Incorrect password";
                    } else if (error.contains("timeout")) {
                        userError = "Connection timeout";
                    } else if (error.contains("not-found")) {
                        userError = "Network not found";
                    } else {
                        userError = "Connection failed";
                    }

                    emit connectionFailed(userError);
                } else {
                    qInfo() << "[NetworkManagerCpp] ✓ Successfully connected to:" << ssid;
                    m_wifiSsid      = ssid;
                    m_wifiConnected = true;
                    emit wifiSsidChanged();
                    emit wifiConnectedChanged();
                    emit connectionSuccess();

                    // Update connection state immediately
                    QTimer::singleShot(1000, this, &NetworkManagerCpp::queryConnectionState);
                }

                watcher->deleteLater();
            });
}

void NetworkManagerCpp::disconnectWifi() {
    qDebug() << "[NetworkManagerCpp] Disconnecting WiFi";
    m_wifiConnected = false;
    m_wifiSsid      = "Disconnected";
    emit wifiConnectedChanged();
    emit wifiSsidChanged();
}

void NetworkManagerCpp::enableBluetooth() {
    qDebug() << "[NetworkManagerCpp] Enabling Bluetooth";
    if (m_hasNetworkManager) {
        QDBusReply<void> reply =
            m_nmInterface->call("SetProperty", "BluetoothEnabled", QVariant(true));
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to enable Bluetooth:"
                     << reply.error().message();
            emit networkError("Failed to enable Bluetooth");
            return;
        }
    }
    m_bluetoothEnabled = true;
    emit bluetoothEnabledChanged();
}

void NetworkManagerCpp::disableBluetooth() {
    qDebug() << "[NetworkManagerCpp] Disabling Bluetooth";
    if (m_hasNetworkManager) {
        QDBusReply<void> reply =
            m_nmInterface->call("SetProperty", "BluetoothEnabled", QVariant(false));
        if (!reply.isValid()) {
            qDebug() << "[NetworkManagerCpp] Failed to disable Bluetooth:"
                     << reply.error().message();
            emit networkError("Failed to disable Bluetooth");
            return;
        }
    }
    m_bluetoothEnabled = false;
    emit bluetoothEnabledChanged();
}

void NetworkManagerCpp::toggleBluetooth() {
    if (m_bluetoothEnabled) {
        disableBluetooth();
    } else {
        enableBluetooth();
    }
}

void NetworkManagerCpp::setAirplaneMode(bool enabled) {
    qDebug() << "[NetworkManagerCpp] Setting Airplane Mode to:" << enabled;

    // Airplane mode is implemented by enabling/disabling all wireless devices
    // This is a simplified implementation for now
    if (m_hasNetworkManager) {
        // Disable WiFi
        if (!m_wifiDevicePath.isEmpty()) {
            QDBusInterface wifiDevice("org.freedesktop.NetworkManager", m_wifiDevicePath,
                                      "org.freedesktop.DBus.Properties",
                                      QDBusConnection::systemBus());
            wifiDevice.call("Set", "org.freedesktop.NetworkManager.Device", "Autoconnect",
                            QVariant::fromValue(QDBusVariant(!enabled)));
        }

        // Update WiFi state
        if (enabled) {
            disableWifi();
        }
    }

    m_airplaneModeEnabled = enabled;
    emit airplaneModeEnabledChanged();

    qInfo() << "[NetworkManagerCpp] Airplane Mode" << (enabled ? "enabled" : "disabled");
}

void NetworkManagerCpp::createHotspot(const QString &ssid, const QString &password) {
    qInfo() << "[NetworkManagerCpp] Creating WiFi hotspot:" << ssid;

    if (!m_hasNetworkManager || m_wifiDevicePath.isEmpty()) {
        qWarning() << "[NetworkManagerCpp] Cannot create hotspot: WiFi not available";
        emit connectionFailed("WiFi not available");
        return;
    }

    // Build hotspot connection settings
    QMap<QString, QMap<QString, QVariant>> connectionSettings;

    // Connection settings
    QMap<QString, QVariant> connection;
    connection["type"]               = "802-11-wireless";
    connection["uuid"]               = QUuid::createUuid().toString().remove('{').remove('}');
    connection["id"]                 = ssid + " Hotspot";
    connection["autoconnect"]        = false;
    connectionSettings["connection"] = connection;

    // Wireless settings - AP mode
    QMap<QString, QVariant> wireless;
    wireless["ssid"]                      = ssid.toUtf8();
    wireless["mode"]                      = "ap"; // Access Point mode
    wireless["band"]                      = "bg"; // 2.4GHz
    connectionSettings["802-11-wireless"] = wireless;

    // Security settings
    if (!password.isEmpty() && password.length() >= 8) {
        QMap<QString, QVariant> wirelessSecurity;
        wirelessSecurity["key-mgmt"]                   = "wpa-psk";
        wirelessSecurity["psk"]                        = password;
        connectionSettings["802-11-wireless-security"] = wirelessSecurity;
    }

    // IPv4 settings - shared mode (NAT)
    QMap<QString, QVariant> ipv4;
    ipv4["method"]             = "shared"; // Enables NAT/DHCP
    connectionSettings["ipv4"] = ipv4;

    // IPv6 settings
    QMap<QString, QVariant> ipv6;
    ipv6["method"]             = "ignore";
    connectionSettings["ipv6"] = ipv6;

    qDebug() << "[NetworkManagerCpp] Activating hotspot connection...";

    // Add and activate connection
    QDBusMessage msg = QDBusMessage::createMethodCall(
        "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager", "AddAndActivateConnection");

    QVariantMap dbusSettings;
    for (auto it = connectionSettings.begin(); it != connectionSettings.end(); ++it) {
        dbusSettings[it.key()] = QVariant::fromValue(it.value());
    }

    msg << QVariant::fromValue(dbusSettings);
    msg << QVariant::fromValue(QDBusObjectPath(m_wifiDevicePath));
    msg << QVariant::fromValue(QDBusObjectPath("/"));

    QDBusPendingCall         call    = QDBusConnection::systemBus().asyncCall(msg);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, ssid](QDBusPendingCallWatcher *watcher) {
                QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply = *watcher;

                if (reply.isError()) {
                    QString error = reply.error().message();
                    qWarning() << "[NetworkManagerCpp] Hotspot creation failed:" << error;
                    emit connectionFailed("Failed to create hotspot: " + error);
                } else {
                    m_hotspotConnectionPath = reply.value().path();
                    m_hotspotActive         = true;
                    qInfo() << "[NetworkManagerCpp] ✓ Hotspot active:" << ssid;
                    emit connectionSuccess();
                }

                watcher->deleteLater();
            });
}

void NetworkManagerCpp::stopHotspot() {
    qInfo() << "[NetworkManagerCpp] Stopping hotspot";

    if (!m_hasNetworkManager || m_hotspotConnectionPath.isEmpty()) {
        return;
    }

    QDBusInterface activeConn("org.freedesktop.NetworkManager", m_hotspotConnectionPath,
                              "org.freedesktop.NetworkManager.Connection.Active",
                              QDBusConnection::systemBus());

    if (activeConn.isValid()) {
        QDBusReply<void> reply = m_nmInterface->call(
            "DeactivateConnection", QVariant::fromValue(QDBusObjectPath(m_hotspotConnectionPath)));
        if (reply.isValid()) {
            qInfo() << "[NetworkManagerCpp] ✓ Hotspot stopped";
        }
    }

    m_hotspotConnectionPath.clear();
    m_hotspotActive = false;
}

bool NetworkManagerCpp::isHotspotActive() const {
    return m_hotspotActive;
}

QVariantList NetworkManagerCpp::getVpnConnections() {
    QVariantList vpnList;

    if (!m_hasNetworkManager) {
        return vpnList;
    }

    // Get all connections
    QDBusInterface settingsInterface(
        "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings", QDBusConnection::systemBus());

    if (!settingsInterface.isValid()) {
        return vpnList;
    }

    QDBusReply<QList<QDBusObjectPath>> connectionsReply = settingsInterface.call("ListConnections");
    if (!connectionsReply.isValid()) {
        return vpnList;
    }

    // Filter for VPN connections
    for (const QDBusObjectPath &path : connectionsReply.value()) {
        QDBusInterface          connectionInterface("org.freedesktop.NetworkManager", path.path(),
                                                    "org.freedesktop.NetworkManager.Settings.Connection",
                                                    QDBusConnection::systemBus());

        QDBusReply<QVariantMap> settingsReply = connectionInterface.call("GetSettings");
        if (settingsReply.isValid()) {
            QVariantMap settings   = settingsReply.value();
            QVariantMap connection = settings.value("connection").toMap();
            QString     type       = connection.value("type").toString();

            if (type == "vpn") {
                QVariantMap vpn;
                vpn["id"]   = connection.value("id").toString();
                vpn["uuid"] = connection.value("uuid").toString();
                vpn["path"] = path.path();
                vpnList.append(vpn);
            }
        }
    }

    qDebug() << "[NetworkManagerCpp] Found" << vpnList.size() << "VPN connections";
    return vpnList;
}

void NetworkManagerCpp::connectVpn(const QString &connectionId) {
    qInfo() << "[NetworkManagerCpp] Connecting VPN:" << connectionId;

    if (!m_hasNetworkManager) {
        return;
    }

    QDBusInterface nmInterface("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                               "org.freedesktop.NetworkManager", QDBusConnection::systemBus());

    QDBusReply<QDBusObjectPath> reply = nmInterface.call(
        "ActivateConnection", QVariant::fromValue(QDBusObjectPath(connectionId)),
        QVariant::fromValue(QDBusObjectPath("/")), QVariant::fromValue(QDBusObjectPath("/")));

    if (reply.isValid()) {
        qInfo() << "[NetworkManagerCpp] ✓ VPN activated";
    } else {
        qWarning() << "[NetworkManagerCpp] Failed to activate VPN:" << reply.error().message();
    }
}

void NetworkManagerCpp::disconnectVpn(const QString &connectionId) {
    qInfo() << "[NetworkManagerCpp] Disconnecting VPN:" << connectionId;

    if (!m_hasNetworkManager) {
        return;
    }

    // Find active connection
    QDBusInterface nmInterface("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                               "org.freedesktop.NetworkManager", QDBusConnection::systemBus());

    QDBusReply<QList<QDBusObjectPath>> activeConnsReply =
        nmInterface.call("Get", "org.freedesktop.NetworkManager", "ActiveConnections");

    if (!activeConnsReply.isValid()) {
        return;
    }

    for (const QDBusObjectPath &path : activeConnsReply.value()) {
        QDBusInterface activeConn("org.freedesktop.NetworkManager", path.path(),
                                  "org.freedesktop.NetworkManager.Connection.Active",
                                  QDBusConnection::systemBus());

        QString        connPath = activeConn.property("Connection").value<QDBusObjectPath>().path();
        if (connPath == connectionId) {
            QDBusReply<void> reply =
                nmInterface.call("DeactivateConnection", QVariant::fromValue(path));
            if (reply.isValid()) {
                qInfo() << "[NetworkManagerCpp] ✓ VPN disconnected";
            }
            return;
        }
    }
}

bool NetworkManagerCpp::isVpnConnected(const QString &connectionId) {
    if (!m_hasNetworkManager) {
        return false;
    }

    QDBusInterface nmInterface("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                               "org.freedesktop.NetworkManager", QDBusConnection::systemBus());

    QDBusReply<QList<QDBusObjectPath>> activeConnsReply =
        nmInterface.call("Get", "org.freedesktop.NetworkManager", "ActiveConnections");

    if (!activeConnsReply.isValid()) {
        return false;
    }

    for (const QDBusObjectPath &path : activeConnsReply.value()) {
        QDBusInterface activeConn("org.freedesktop.NetworkManager", path.path(),
                                  "org.freedesktop.NetworkManager.Connection.Active",
                                  QDBusConnection::systemBus());

        QString        connPath = activeConn.property("Connection").value<QDBusObjectPath>().path();
        if (connPath == connectionId) {
            return true;
        }
    }

    return false;
}
