#include "bluetoothmanager.h"
#include "bluetoothagent.h"
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QProcess>

// BluetoothDevice implementation
BluetoothDevice::BluetoothDevice(const QString &path, QObject *parent)
    : QObject(parent)
    , m_path(path) {
    updateProperties();
}

void BluetoothDevice::updateProperties() {
    QDBusInterface          device("org.bluez", m_path, "org.freedesktop.DBus.Properties",
                                   QDBusConnection::systemBus());

    QDBusReply<QVariantMap> reply = device.call("GetAll", "org.bluez.Device1");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothDevice] Failed to get properties for" << m_path << ":"
                   << reply.error().message();
        return;
    }

    QVariantMap props = reply.value();

    QString     newAddress = props.value("Address").toString();
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

    QString rawIcon = props.value("Icon").toString();
    QString newIcon = "bluetooth"; // Default

    // Map Freedesktop icon names to available Lucide icons
    if (rawIcon.contains("audio-card") || rawIcon.contains("speaker")) {
        newIcon = "volume-2";
    } else if (rawIcon.contains("headphone") || rawIcon.contains("headset")) {
        newIcon = "music"; // We don't have headphones icon yet
    } else if (rawIcon.contains("computer") || rawIcon.contains("laptop") ||
               rawIcon.contains("monitor")) {
        newIcon = "monitor";
    } else if (rawIcon.contains("phone") || rawIcon.contains("smartphone")) {
        newIcon = "smartphone";
    } else if (rawIcon.contains("keyboard")) {
        newIcon = "keyboard";
    } else if (rawIcon.contains("watch")) {
        newIcon = "clock";
    } else if (!rawIcon.isEmpty()) {
        // Try to use the raw name if we have it, otherwise default
        // This is a bit risky without checking existence, but "bluetooth" is a safe fallback in QML if load fails?
        // Actually QML warns if load fails. Let's stick to mapped icons or default.
        // newIcon = rawIcon;
    }

    if (newIcon != m_icon) {
        m_icon = newIcon;
        emit iconChanged();
    }

    qDebug() << "[BluetoothDevice] Updated:" << m_alias << "(" << m_address
             << ") paired=" << m_paired << "connected=" << m_connected;
}

// BluetoothManager implementation
BluetoothManager::BluetoothManager(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::systemBus()) {
    qDebug() << "[BluetoothManager] Initializing";

    // Register the complex type for DBus
    qRegisterMetaType<ManagedObjectMap>("ManagedObjectMap");
    qDBusRegisterMetaType<ManagedObjectMap>();
    qRegisterMetaType<PropertyMap>("PropertyMap");
    qDBusRegisterMetaType<PropertyMap>();
    qRegisterMetaType<InterfaceMap>("InterfaceMap");
    qDBusRegisterMetaType<InterfaceMap>();

    if (!m_bus.isConnected()) {
        qWarning() << "[BluetoothManager] Failed to connect to system bus";
        return;
    }

    m_bus.connect("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", this,
                  SLOT(onDeviceAdded(QDBusObjectPath, InterfaceMap)));

    m_bus.connect("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved", this,
                  SLOT(onDeviceRemoved(QDBusObjectPath, QStringList)));

    initializeAdapter();
}

BluetoothManager::~BluetoothManager() {
    qDeleteAll(m_devices);
}

void BluetoothManager::initializeAdapter() {
    qDebug() << "[BluetoothManager] initializeAdapter called";
    QDBusInterface           manager("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", m_bus);
    QDBusPendingCall         asyncCall = manager.asyncCall("GetManagedObjects");
    QDBusPendingCallWatcher *watcher   = new QDBusPendingCallWatcher(asyncCall, this);

    connect(
        watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            QDBusPendingReply<ManagedObjectMap> reply = *call;

            if (reply.isError()) {
                // Log once only - bluez may not be running in VM or on systems without Bluetooth
                static bool hasLogged = false;
                if (!hasLogged) {
                    qDebug() << "[BluetoothManager] Bluetooth not available (bluez service not "
                                "running or no hardware)";
                    hasLogged = true;
                }
                m_available = false;
                emit availableChanged();
                call->deleteLater();
                return;
            }

            auto objects      = reply.value();
            bool adapterFound = false;

            qDebug() << "[BluetoothManager] Scanning" << objects.count() << "managed objects...";

            // First pass: Find adapter
            for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
                if (it.value().contains("org.bluez.Adapter1")) {
                    m_adapterPath = it.key().path();
                    qDebug() << "[BluetoothManager] Found adapter:" << m_adapterPath;

                    m_adapter = new QDBusInterface("org.bluez", m_adapterPath, "org.bluez.Adapter1",
                                                   m_bus, this);
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

            // Second pass: Find devices
            int deviceCount = 0;
            for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
                if (it.value().contains("org.bluez.Device1")) {
                    QString path = it.key().path();
                    // Only add devices belonging to our adapter
                    if (path.startsWith(m_adapterPath)) {
                        addDevice(path);
                        deviceCount++;
                    } else {
                        qDebug() << "[BluetoothManager] Device skipped (path mismatch):" << path
                                 << "vs" << m_adapterPath;
                    }
                }
            }
            qDebug() << "[BluetoothManager] Added" << deviceCount << "devices";

            if (!m_adapterPath.isEmpty()) {
                m_bus.connect("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties",
                              "PropertiesChanged", this,
                              SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
            }

            // Create and register Bluetooth pairing agent
            m_agent = new BluetoothAgent(this);
            if (!m_agent->registerAgent()) {
                // This is expected on desktop/VM environments where BlueZ isn't running
                qDebug()
                    << "[BluetoothManager] Pairing agent not registered (expected without BlueZ)";
            }

            // Forward pairing interaction signals from agent to UI
            connect(m_agent, &BluetoothAgent::pairingPinCodeRequested, this,
                    [this](const QString &devicePath, const QString &deviceName) {
                        QString address = devicePath.section('/', -1);
                        emit    pinRequested(address, deviceName);
                    });

            connect(m_agent, &BluetoothAgent::pairingPasskeyRequested, this,
                    [this](const QString &devicePath, const QString &deviceName) {
                        QString address = devicePath.section('/', -1);
                        emit    passkeyRequested(address, deviceName);
                    });

            connect(m_agent, &BluetoothAgent::pairingConfirmationRequested, this,
                    [this](const QString &devicePath, const QString &deviceName, quint32 passkey) {
                        QString address = devicePath.section('/', -1);
                        emit    passkeyConfirmation(address, deviceName, passkey);
                    });

            // Initialize scan timer after adapter is found
            m_scanTimer = new QTimer(this);
            m_scanTimer->setInterval(30000); // Stop scan after 30s
            m_scanTimer->setSingleShot(true);
            connect(m_scanTimer, &QTimer::timeout, this, &BluetoothManager::stopScan);

            call->deleteLater();
        });
}

void BluetoothManager::connectToBlueZ() {
    // This method is now empty as its content has been moved to initializeAdapter
    // to ensure signal connections are made after the adapter is found.
}

void BluetoothManager::updateAdapterProperties() {
    if (!m_adapter)
        return;

    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    QDBusReply<QVariantMap> reply = props.call("GetAll", "org.bluez.Adapter1");

    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to get adapter properties:"
                   << reply.error().message();
        return;
    }

    QVariantMap properties = reply.value();

    bool        newPowered = properties.value("Powered").toBool();
    qDebug() << "[BluetoothManager] Property update - Powered:" << (newPowered ? "YES" : "NO");
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

    qDebug() << "[BluetoothManager] Adapter state: powered=" << m_enabled
             << "scanning=" << m_scanning;
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
    if (!m_adapter || m_enabled == enabled)
        return;

    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Adapter1", "Powered", QVariant::fromValue(QDBusVariant(enabled)));

    qDebug() << "[BluetoothManager] Setting powered to" << enabled;

    if (enabled) {
        // Ensure RFKILL is unblocked
        QProcess::execute("rfkill", {"unblock", "bluetooth"});
    }
}

void BluetoothManager::setDiscoverable(bool discoverable) {
    if (!m_adapter || m_discoverable == discoverable)
        return;

    QDBusInterface props("org.bluez", m_adapterPath, "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Adapter1", "Discoverable",
               QVariant::fromValue(QDBusVariant(discoverable)));

    qDebug() << "[BluetoothManager] Setting discoverable to" << discoverable;
}

void BluetoothManager::startScan() {
    if (!m_adapter)
        return;

    qDebug() << "[BluetoothManager] Starting scan...";
    m_adapter->call("StartDiscovery");

    if (m_scanTimer) {
        m_scanTimer->start();
    }
}

void BluetoothManager::stopScan() {
    if (!m_adapter)
        return;

    qDebug() << "[BluetoothManager] Stopping scan...";
    m_adapter->call("StopDiscovery");

    if (m_scanTimer) {
        m_scanTimer->stop();
    }
}

void BluetoothManager::pairDevice(const QString &address, const QString &pin) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    qDebug() << "[BluetoothManager] Pairing with" << address;

    // If PIN provided, we might need to handle it via agent, but usually Pair() handles it
    QDBusInterface deviceIface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceIface.asyncCall("Pair");
}

void BluetoothManager::confirmPairing(const QString &address, bool confirmed) {
    if (m_agent) {
        m_agent->confirmPairing(confirmed);
    }
}

void BluetoothManager::cancelPairing(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    QDBusInterface deviceIface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceIface.call("CancelPairing");
}

void BluetoothManager::unpairDevice(const QString &address) {
    removeDevice(address);
}

void BluetoothManager::connectDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    qDebug() << "[BluetoothManager] Connecting to" << address;
    QDBusInterface deviceIface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceIface.asyncCall("Connect");
}

void BluetoothManager::disconnectDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    qDebug() << "[BluetoothManager] Disconnecting from" << address;
    QDBusInterface deviceIface("org.bluez", device->path(), "org.bluez.Device1", m_bus);
    deviceIface.asyncCall("Disconnect");
}

void BluetoothManager::trustDevice(const QString &address, bool trusted) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    QDBusInterface props("org.bluez", device->path(), "org.freedesktop.DBus.Properties", m_bus);
    props.call("Set", "org.bluez.Device1", "Trusted", QVariant::fromValue(QDBusVariant(trusted)));

    qDebug() << "[BluetoothManager] Setting trusted to" << trusted << "for" << address;
}

void BluetoothManager::removeDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device || !m_adapter)
        return;

    QDBusReply<void> reply =
        m_adapter->call("RemoveDevice", QVariant::fromValue(QDBusObjectPath(device->path())));
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to remove device:" << reply.error().message();
    }
}

QList<QObject *> BluetoothManager::pairedDevices() const {
    QList<QObject *> paired;
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice *>(obj);
        if (device && device->paired()) {
            paired.append(device);
        }
    }
    return paired;
}

void BluetoothManager::onDeviceAdded(const QDBusObjectPath &objectPath,
                                     const InterfaceMap    &interfaces) {
    QString path = objectPath.path();

    // Check if it's a device interface
    if (interfaces.contains("org.bluez.Device1")) {
        qDebug() << "[BluetoothManager] Device added signal:" << path;
        addDevice(path);
    }
}

void BluetoothManager::onDeviceRemoved(const QDBusObjectPath &objectPath,
                                       const QStringList     &interfaces) {
    QString path = objectPath.path();

    if (interfaces.contains("org.bluez.Device1")) {
        qDebug() << "[BluetoothManager] Device removed signal:" << path;
        removeDeviceByPath(path);
    }
}

void BluetoothManager::onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                           const QStringList &invalidated) {
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

BluetoothDevice *BluetoothManager::findDeviceByPath(const QString &path) {
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice *>(obj);
        if (device && device->path() == path) {
            return device;
        }
    }
    return nullptr;
}

BluetoothDevice *BluetoothManager::findDeviceByAddress(const QString &address) {
    for (QObject *obj : m_devices) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice *>(obj);
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
    if (!device)
        return;

    bool wasPaired = device->paired();

    m_devices.removeAll(device);
    device->deleteLater();

    emit devicesChanged();

    if (wasPaired) {
        emit pairedDevicesChanged();
    }
}
