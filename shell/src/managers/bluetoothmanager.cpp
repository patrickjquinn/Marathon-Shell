#include "bluetoothmanager.h"
#include "bluetoothagent.h"
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingReply>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <utility>   // std::as_const

// Soft-unblock a kernel rfkill switch by type. Direct sysfs write rather
// than shelling out to /usr/sbin/rfkill — Alpine's util-linux rfkill has
// a libsmartcols regression that SIGABRTs in xstrdup on `rfkill list` and
// occasionally on `rfkill unblock` under empty-row conditions. The kernel
// /sys/class/rfkill/* API is stable since 2.6.35 and write-permitted to
// root only (we already are root via marathon-shell's session). Returns
// the number of switches unblocked.
static int unblockRfkillByType(const QString &type) {
    QDir dir(QStringLiteral("/sys/class/rfkill"));
    if (!dir.exists())
        return 0;
    int               touched = 0;
    const QStringList entries = dir.entryList(QStringList{QStringLiteral("rfkill*")}, QDir::Dirs);
    for (const QString &entry : entries) {
        const QString base = dir.absoluteFilePath(entry);
        QFile         typeFile(base + QStringLiteral("/type"));
        if (!typeFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const QString readType = QString::fromUtf8(typeFile.readAll()).trimmed();
        typeFile.close();
        if (readType != type)
            continue;
        QFile softFile(base + QStringLiteral("/soft"));
        if (!softFile.open(QIODevice::WriteOnly | QIODevice::Text))
            continue;
        if (softFile.write("0\n") > 0)
            ++touched;
        softFile.close();
    }
    return touched;
}

BluetoothDevice::BluetoothDevice(const QString &path, const QVariantMap &props, QObject *parent)
    : QObject(parent)
    , m_path(path)
    , m_props(props) {
    QDBusConnection::systemBus().connect(
        "org.bluez", m_path, "org.freedesktop.DBus.Properties", "PropertiesChanged", this,
        SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    if (m_props.isEmpty())
        updateProperties();
    else
        applyProperties();
}

void BluetoothDevice::updateProperties() {
    QDBusMessage get = QDBusMessage::createMethodCall("org.bluez", m_path,
                                                      "org.freedesktop.DBus.Properties", "GetAll");
    get << QStringLiteral("org.bluez.Device1");
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isError()) {
            qWarning() << "[BluetoothDevice] Failed to get properties for" << m_path << ":"
                       << reply.error().message();
            return;
        }
        m_props = reply.value();
        applyProperties();
    });
}

void BluetoothDevice::onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                          const QStringList &invalidated) {
    if (interface != QLatin1String("org.bluez.Device1"))
        return;
    for (auto it = changed.cbegin(); it != changed.cend(); ++it)
        m_props.insert(it.key(), it.value());
    for (const QString &key : invalidated)
        m_props.remove(key);
    applyProperties();
}

void BluetoothDevice::applyProperties() {
    const QVariantMap &props = m_props;

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
    QString newIcon = "bluetooth";

    if (rawIcon.contains("audio-card") || rawIcon.contains("speaker")) {
        newIcon = "volume-2";
    } else if (rawIcon.contains("headphone") || rawIcon.contains("headset")) {
        newIcon = "music";
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
    }

    if (newIcon != m_icon) {
        m_icon = newIcon;
        emit iconChanged();
    }

    qDebug() << "[BluetoothDevice] Updated:" << m_alias << "(" << m_address
             << ") paired=" << m_paired << "connected=" << m_connected;
}

BluetoothManager::BluetoothManager(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::systemBus()) {
    qDebug() << "[BluetoothManager] Initializing";

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

    connect(watcher, &QDBusPendingCallWatcher::finished, watcher, &QObject::deleteLater);

    connect(
        watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            QDBusPendingReply<ManagedObjectMap> reply = *call;

            if (reply.isError()) {

                static bool hasLogged = false;
                if (!hasLogged) {
                    qDebug() << "[BluetoothManager] Bluetooth not available (bluez service not "
                                "running or no hardware)";
                    hasLogged = true;
                }
                m_available = false;
                emit availableChanged();
                return;
            }

            auto objects      = reply.value();
            bool adapterFound = false;

            qDebug() << "[BluetoothManager] Scanning" << objects.count() << "managed objects...";

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
                return;
            }

            int deviceCount = 0;
            for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
                if (it.value().contains("org.bluez.Device1")) {
                    QString path = it.key().path();

                    if (path.startsWith(m_adapterPath)) {
                        addDevice(path, it.value().value("org.bluez.Device1"));
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

            m_agent = new BluetoothAgent(this);
            if (!m_agent->registerAgent()) {

                qDebug()
                    << "[BluetoothManager] Pairing agent not registered (expected without BlueZ)";
            }

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

            m_scanTimer = new QTimer(this);
            m_scanTimer->setInterval(30000);
            m_scanTimer->setSingleShot(true);
            connect(m_scanTimer, &QTimer::timeout, this, &BluetoothManager::stopScan);
        });
}

void BluetoothManager::updateAdapterProperties() {
    if (!m_adapter)
        return;

    QDBusMessage get = QDBusMessage::createMethodCall("org.bluez", m_adapterPath,
                                                      "org.freedesktop.DBus.Properties", "GetAll");
    get << QStringLiteral("org.bluez.Adapter1");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isError()) {
            qWarning() << "[BluetoothManager] Failed to get adapter properties:"
                       << reply.error().message();
            return;
        }
        applyAdapterProperties(reply.value());
    });
}

void BluetoothManager::applyAdapterProperties(const QVariantMap &properties) {
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

void BluetoothManager::setEnabled(bool enabled) {
    if (!m_adapter || m_enabled == enabled)
        return;

    setAdapterProperty(QStringLiteral("Powered"), enabled);

    qDebug() << "[BluetoothManager] Setting powered to" << enabled;

    if (enabled) {
        const int unblocked = unblockRfkillByType(QStringLiteral("bluetooth"));
        if (unblocked == 0)
            qDebug() << "[BluetoothManager] no rfkill bluetooth entries found to unblock";
    }
}

void BluetoothManager::setDiscoverable(bool discoverable) {
    if (!m_adapter || m_discoverable == discoverable)
        return;

    setAdapterProperty(QStringLiteral("Discoverable"), discoverable);

    qDebug() << "[BluetoothManager] Setting discoverable to" << discoverable;
}

void BluetoothManager::setAdapterAlias(const QString &alias) {
    if (!m_adapter || alias.isEmpty() || alias == m_adapterName)
        return;
    setAdapterProperty(QStringLiteral("Alias"), alias);
}

void BluetoothManager::setAdapterProperty(const QString &name, const QVariant &value) {
    QDBusMessage set = QDBusMessage::createMethodCall("org.bluez", m_adapterPath,
                                                      "org.freedesktop.DBus.Properties", "Set");
    set << QStringLiteral("org.bluez.Adapter1") << name << QVariant::fromValue(QDBusVariant(value));
    callAsync(set);
}

void BluetoothManager::callAsync(const QDBusMessage &message) {
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [member = message.member()](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (w->isError())
                    qWarning() << "[BluetoothManager]" << member << "failed:" << w->error().name()
                               << w->error().message();
            });
}

void BluetoothManager::startScan() {
    if (!m_adapter)
        return;

    qDebug() << "[BluetoothManager] Starting scan...";
    callAsync(QDBusMessage::createMethodCall("org.bluez", m_adapterPath, "org.bluez.Adapter1",
                                             "StartDiscovery"));

    if (m_scanTimer) {
        m_scanTimer->start();
    }
}

void BluetoothManager::stopScan() {
    if (!m_adapter)
        return;

    qDebug() << "[BluetoothManager] Stopping scan...";
    callAsync(QDBusMessage::createMethodCall("org.bluez", m_adapterPath, "org.bluez.Adapter1",
                                             "StopDiscovery"));

    if (m_scanTimer) {
        m_scanTimer->stop();
    }
}

void BluetoothManager::pairDevice(const QString &address, const QString &pin) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device)
        return;

    qDebug() << "[BluetoothManager] Pairing with" << address;

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

    callAsync(QDBusMessage::createMethodCall("org.bluez", device->path(), "org.bluez.Device1",
                                             "CancelPairing"));
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

void BluetoothManager::removeDevice(const QString &address) {
    BluetoothDevice *device = findDeviceByAddress(address);
    if (!device || !m_adapter)
        return;

    QDBusMessage remove = QDBusMessage::createMethodCall("org.bluez", m_adapterPath,
                                                         "org.bluez.Adapter1", "RemoveDevice");
    remove << QVariant::fromValue(QDBusObjectPath(device->path()));
    callAsync(remove);
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

    if (interfaces.contains("org.bluez.Device1")) {
        qDebug() << "[BluetoothManager] Device added signal:" << path;
        addDevice(path, interfaces.value("org.bluez.Device1"));
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
    for (QObject *obj : std::as_const(m_devices)) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice *>(obj);
        if (device && device->path() == path) {
            return device;
        }
    }
    return nullptr;
}

BluetoothDevice *BluetoothManager::findDeviceByAddress(const QString &address) {
    for (QObject *obj : std::as_const(m_devices)) {
        BluetoothDevice *device = qobject_cast<BluetoothDevice *>(obj);
        if (device && device->address() == address) {
            return device;
        }
    }
    return nullptr;
}

void BluetoothManager::addDevice(const QString &path, const QVariantMap &props) {
    if (findDeviceByPath(path)) {
        return;
    }

    BluetoothDevice *device = new BluetoothDevice(path, props, this);
    m_devices.append(device);
    // A device connecting after it was listed changes what apps and the
    // status bar show.
    const auto changed = [this, device]() {
        emit devicesChanged();
        if (device->paired())
            emit pairedDevicesChanged();
    };
    connect(device, &BluetoothDevice::connectedChanged, this, changed);
    connect(device, &BluetoothDevice::nameChanged, this, changed);
    connect(device, &BluetoothDevice::aliasChanged, this, changed);
    connect(device, &BluetoothDevice::trustedChanged, this, changed);
    connect(device, &BluetoothDevice::pairedChanged, this, [this]() {
        emit devicesChanged();
        emit pairedDevicesChanged();
    });

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
