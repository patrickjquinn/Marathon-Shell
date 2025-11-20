#include "bluetoothmanager.h"
#include "bluetoothagent.h"
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QProcess>

// Define types for GetManagedObjects return value
typedef QMap<QString, QVariant> StringVariantMap;
typedef QMap<QDBusObjectPath, StringVariantMap> ManagedObjectMap;
Q_DECLARE_METATYPE(ManagedObjectMap)

// BluetoothDevice implementation
BluetoothDevice::BluetoothDevice(const QString &path, QObject *parent)
    : QObject(parent)
    , m_path(path)
{
    updateProperties();
}

void BluetoothDevice::updateProperties() {
    QDBusInterface device("org.bluez", m_path, "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());
    
    QDBusReply<QVariantMap> reply = device.call("GetAll", "org.bluez.Device1");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothDevice] Failed to get properties for" << m_path << ":" << reply.error().message();
        return;
    }
    
    QVariantMap props = reply.value();
    
    QString newAddress = props.value("Address").toString();
    if (newAddress != m_address) {
        m_address = newAddress;
    }
    
    QString newName = props.value("Name").toString();
    if (newName != m_name) {
        m_name = newName;
        emit nameChanged();
    }
    
    QString newAlias = props.value("Alias").toString();
    if (newAlias != m_alias) {
        m_alias = newAlias;
        emit aliasChanged();
    }
    
    bool newPaired = props.value("Paired").toBool();
    if (newPaired != m_paired) {
        m_paired = newPaired;
        emit pairedChanged();
    }
    
    bool newConnected = props.value("Connected").toBool();
    if (newConnected != m_connected) {
        m_connected = newConnected;
        emit connectedChanged();
    }
    
    bool newTrusted = props.value("Trusted").toBool();
    if (newTrusted != m_trusted) {
        m_trusted = newTrusted;
        emit trustedChanged();
    }
    
    int newRssi = props.value("RSSI").toInt();
    if (newRssi != m_rssi) {
        m_rssi = newRssi;
        emit rssiChanged();
    }
    
    QString newIcon = props.value("Icon").toString();
    if (newIcon != m_icon) {
        m_icon = newIcon;
        emit iconChanged();
    }
    
    qDebug() << "[BluetoothDevice] Updated:" << m_alias << "(" << m_address << ") paired=" << m_paired << "connected=" << m_connected;
}

// BluetoothManager implementation
BluetoothManager::BluetoothManager(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::systemBus())
{
    qDebug() << "[BluetoothManager] Initializing";
    
    // Register the complex type for DBus
    qRegisterMetaType<ManagedObjectMap>("ManagedObjectMap");
    qDBusRegisterMetaType<ManagedObjectMap>();
    
    if (!m_bus.isConnected()) {
        qWarning() << "[BluetoothManager] Failed to connect to system bus";
        return;
    }
    
    initializeAdapter();
    connectToBlueZ();
    
    m_scanTimer = new QTimer(this);
    m_scanTimer->setInterval(30000); // Stop scan after 30s
    m_scanTimer->setSingleShot(true);
    connect(m_scanTimer, &QTimer::timeout, this, &BluetoothManager::stopScan);
    
    // Create and register Bluetooth pairing agent
    m_agent = new BluetoothAgent(this);
    if (!m_agent->registerAgent()) {
        // This is expected on desktop/VM environments where BlueZ isn't running
        qDebug() << "[BluetoothManager] Pairing agent not registered (expected without BlueZ)";
    }
    
    // Forward pairing interaction signals from agent to UI
    connect(m_agent, &BluetoothAgent::pairingPinCodeRequested, this, [this](const QString &devicePath, const QString &deviceName) {
        QString address = devicePath.section('/', -1);
        emit pinRequested(address, deviceName);
    });
    
    connect(m_agent, &BluetoothAgent::pairingPasskeyRequested, this, [this](const QString &devicePath, const QString &deviceName) {
        QString address = devicePath.section('/', -1);
        emit passkeyRequested(address, deviceName);
    });
    
    connect(m_agent, &BluetoothAgent::pairingConfirmationRequested, this, [this](const QString &devicePath, const QString &deviceName, quint32 passkey) {
        QString address = devicePath.section('/', -1);
        emit passkeyConfirmation(address, deviceName, passkey);
    });
}

BluetoothManager::~BluetoothManager() {
    qDeleteAll(m_devices);
}

void BluetoothManager::initializeAdapter() {
    QDBusInterface manager("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", m_bus);
    QDBusPendingCall asyncCall = manager.asyncCall("GetManagedObjects");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(asyncCall, this);
    
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        QDBusPendingReply<QMap<QDBusObjectPath, QVariantMap>> reply = *call;
        
        if (reply.isError()) {
            // Log once only - bluez may not be running in VM or on systems without Bluetooth
            static bool hasLogged = false;
            if (!hasLogged) {
                qDebug() << "[BluetoothManager] Bluetooth not available (bluez service not running or no hardware)";
                hasLogged = true;
            }
            m_available = false;
            emit availableChanged();
            call->deleteLater();
            return;
        }
        
        auto objects = reply.value();
        bool adapterFound = false;
        
        // First pass: Find adapter
        for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
            if (it.value().contains("org.bluez.Adapter1")) {
                m_adapterPath = it.key().path();
                qDebug() << "[BluetoothManager] Found adapter:" << m_adapterPath;
                
                m_adapter = new QDBusInterface("org.bluez", m_adapterPath, "org.bluez.Adapter1", m_bus, this);
                m_available = true;
                emit availableChanged();
                
                updateAdapterProperties();
                adapterFound = true;
                break;
            }
        }
        
        if (!adapterFound) {
            qDebug() << "[BluetoothManager] No Bluetooth adapter found (no hardware detected)";
            m_available = false;
            emit availableChanged();
            call->deleteLater();
            return;
        }
        
        // Second pass: Find devices (using the same response, avoiding extra DBus call)
        for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
            if (it.value().contains("org.bluez.Device1")) {
                QString path = it.key().path();
                if (!findDeviceByPath(path)) {
                    addDevice(path);
                }
            }
        }
        
        call->deleteLater();
    });
}

void BluetoothManager::connectToBlueZ() {
    m_bus.connect("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                  this, SLOT(onDeviceAdded(QString)));
    
    m_bus.connect("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved",
                  this, SLOT(onDeviceRemoved(QString)));
    
    if (!m_adapterPath.isEmpty()) {
        m_bus.connect("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                      this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));
    }
}

void BluetoothManager::updateAdapterProperties() {
    if (!m_adapter) return;
    
    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    QDBusReply<QVariantMap> reply = props.call("GetAll", "org.bluez.Adapter1");
    
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to get adapter properties:" << reply.error().message();
        return;
    }
    
    QVariantMap properties = reply.value();
    
    bool newPowered = properties.value("Powered").toBool();
    if (newPowered != m_enabled) {
        m_enabled = newPowered;
        emit enabledChanged();
    }
    
    bool newDiscovering = properties.value("Discovering").toBool();
    if (newDiscovering != m_scanning) {
        m_scanning = newDiscovering;
        emit scanningChanged();
    }
    
    bool newDiscoverable = properties.value("Discoverable").toBool();
    if (newDiscoverable != m_discoverable) {
        m_discoverable = newDiscoverable;
        emit discoverableChanged();
    }
    
    QString newName = properties.value("Alias").toString();
    if (newName != m_adapterName) {
        m_adapterName = newName;
        emit adapterNameChanged();
    }
    
    qDebug() << "[BluetoothManager] Adapter state: powered=" << m_enabled << "scanning=" << m_scanning;
}

void BluetoothManager::refreshDevices() {
    QDBusInterface manager("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", m_bus);
    QDBusReply<QMap<QDBusObjectPath, QVariantMap>> reply = manager.call("GetManagedObjects");
    
    if (!reply.isValid()) {
        return;
    }
    
    auto objects = reply.value();
    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        if (it.value().contains("org.bluez.Device1")) {
            QString path = it.key().path();
            if (!findDeviceByPath(path)) {
                addDevice(path);
            }
        }
    }
}

void BluetoothManager::setEnabled(bool enabled) {
    if (!m_adapter || m_enabled == enabled) return;
    
    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Adapter1", "Powered", QVariant::fromValue(QDBusVariant(enabled)));
    
    qDebug() << "[BluetoothManager] Setting powered to" << enabled;
    
    if (enabled) {
        // Ensure RFKILL is unblocked
        QProcess::execute("rfkill", {"unblock", "bluetooth"});
    }
}

void BluetoothManager::setDiscoverable(bool discoverable) {
    if (!m_adapter || m_discoverable == discoverable) return;
    
    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Adapter1", "Discoverable", QVariant::fromValue(QDBusVariant(discoverable)));
    
    qDebug() << "[BluetoothManager] Setting discoverable to" << discoverable;
}

void BluetoothManager::startScan() {
    if (!m_adapter || !m_enabled) {
        qWarning() << "[BluetoothManager] Cannot scan: adapter not available or powered off";
        return;
    }
    
    if (m_scanning) {
        qDebug() << "[BluetoothManager] Already scanning";
        return;
    }
    
    QDBusReply<void> reply = m_adapter->call("StartDiscovery");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to start scan:" << reply.error().message();
        return;
    }
    
    qDebug() << "[BluetoothManager] Started scanning";
    m_scanTimer->start();
}

void BluetoothManager::stopScan() {
    if (!m_adapter || !m_scanning) return;
    
    QDBusReply<void> reply = m_adapter->call("StopDiscovery");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to stop scan:" << reply.error().message();
        return;
    }
    
    qDebug() << "[BluetoothManager] Stopped scanning";
    m_scanTimer->stop();
}

void BluetoothManager::pairDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device) {
        qWarning() << "[BluetoothManager] Device not found:" << address;
        return;
    }
    
    QDBusInterface deviceInterface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    QDBusPendingCall call = deviceInterface.asyncCall("Pair");
    
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, address](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<> reply = *w;
        if (reply.isError()) {
            qWarning() << "[BluetoothManager] Pairing failed:" << reply.error().message();
            emit pairingFailed(address, reply.error().message());
        } else {
            qDebug() << "[BluetoothManager] Pairing succeeded:" << address;
            emit pairingSucceeded(address);
            emit pairedDevicesChanged();
        }
        w->deleteLater();
    });
}

void BluetoothManager::unpairDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device) return;
    
    removeDevice(address);
}

void BluetoothManager::connectDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device) return;
    
    QDBusInterface deviceInterface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceInterface.asyncCall("Connect");
    
    qDebug() << "[BluetoothManager] Connecting to" << address;
}

void BluetoothManager::disconnectDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device) return;
    
    QDBusInterface deviceInterface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceInterface.asyncCall("Disconnect");
    
    qDebug() << "[BluetoothManager] Disconnecting from" << address;
}

void BluetoothManager::trustDevice(const QString &address, bool trusted) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device) return;
    
    QDBusInterface props("org.bluez", device->path(), "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Device1", "Trusted", QVariant::fromValue(QDBusVariant(trusted)));
    
    qDebug() << "[BluetoothManager] Setting trusted to" << trusted << "for" << address;
}

void BluetoothManager::removeDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device || !m_adapter) return;
    
    QDBusReply<void> reply = m_adapter->call("RemoveDevice", QVariant::fromValue(QDBusObjectPath(device->path())));
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to remove device:" << reply.error().message();
    }
}

QList<QObject*> BluetoothManager::pairedDevices() const {
    QList<QObject*> paired;
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice*>(obj);
        if (device && device->paired()) {
            paired.append(device);
        }
    }
    return paired;
}

void BluetoothManager::onDeviceAdded(const QString &path) {
    if (!path.startsWith("/org/bluez/") || !path.contains("/dev_")) {
        return;
    }
    
    qDebug() << "[BluetoothManager] Device added:" << path;
    addDevice(path);
}

void BluetoothManager::onDeviceRemoved(const QString &path) {
    qDebug() << "[BluetoothManager] Device removed:" << path;
    removeDeviceByPath(path);
}

void BluetoothManager::onPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated) {
    Q_UNUSED(invalidated)
    
    if (interface == "org.bluez.Adapter1") {
        if (changed.contains("Powered")) {
            bool powered = changed.value("Powered").toBool();
            if (powered != m_enabled) {
                m_enabled = powered;
                emit enabledChanged();
            }
        }
        if (changed.contains("Discovering")) {
            bool discovering = changed.value("Discovering").toBool();
            if (discovering != m_scanning) {
                m_scanning = discovering;
                emit scanningChanged();
            }
        }
        if (changed.contains("Discoverable")) {
            bool discoverable = changed.value("Discoverable").toBool();
            if (discoverable != m_discoverable) {
                m_discoverable = discoverable;
                emit discoverableChanged();
            }
        }
    }
}

BluetoothDevice* BluetoothManager::findDeviceByPath(const QString &path) {
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice*>(obj);
        if (device && device->path() == path) {
            return device;
        }
    }
    return nullptr;
}

BluetoothDevice* BluetoothManager::findDeviceByAddress(const QString &address) {
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice*>(obj);
        if (device && device->address() == address) {
            return device;
        }
    }
    return nullptr;
}

void BluetoothManager::addDevice(const QString &path) {
    if (findDeviceByPath(path)) {
        return; // Already exists
    }
    
    BluetoothDevice *device = new BluetoothDevice(path, this);
    m_devices.append(device);
    
    emit devicesChanged();
    
    if (device->paired()) {
        emit pairedDevicesChanged();
    }
}

void BluetoothManager::removeDeviceByPath(const QString &path) {
    BluetoothDevice *device = findDeviceByPath(path);
    if (!device) return;
    
    bool wasPaired = device->paired();
    
    m_devices.removeAll(device);
    device->deleteLater();
    
    emit devicesChanged();
    
    if (wasPaired) {
        emit pairedDevicesChanged();
    }
}

