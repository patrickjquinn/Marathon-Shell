#include "modemmanagercpp.h"
#include <QDebug>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QDBusMetaType>
#include <QRandomGenerator>

ModemManagerCpp::ModemManagerCpp(QObject *parent)
    : QObject(parent)
    , m_mmInterface(nullptr)
    , m_stateMonitor(nullptr)
    , m_dbusRetryTimer(nullptr)
    , m_dbusRetryCount(0)
    , m_hasModemManager(false)
    , m_modemAvailable(false)
    , m_modemEnabled(false)
    , m_signalStrength(0)
    , m_registered(false)
    , m_operatorName("")
    , m_networkType("Unknown")
    , m_roaming(false)
    , m_simPresent(false)
    , m_dataEnabled(false)
    , m_dataConnected(false) {
    qDebug() << "[ModemManagerCpp] Initializing";

    // Setup state monitor (will start when D-Bus connects)
    m_stateMonitor = new QTimer(this);
    m_stateMonitor->setInterval(5000); // Poll every 5 seconds
    connect(m_stateMonitor, &QTimer::timeout, this, &ModemManagerCpp::queryModemState);

    // Setup D-Bus retry timer
    m_dbusRetryTimer = new QTimer(this);
    m_dbusRetryTimer->setSingleShot(true);
    connect(m_dbusRetryTimer, &QTimer::timeout, this, &ModemManagerCpp::retryDBusConnection);

    // Initial connection attempt
    initializeDBusConnection();
}

void ModemManagerCpp::initializeDBusConnection() {
    // Check if system bus is available
    if (!QDBusConnection::systemBus().isConnected()) {
        qWarning() << "[ModemManagerCpp] D-Bus system bus not connected, will retry...";

        // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms, 3200ms, then 5s max
        const int maxRetries = 10;
        if (m_dbusRetryCount < maxRetries) {
            int delay = qMin(100 * (1 << m_dbusRetryCount), 5000);
            m_dbusRetryCount++;
            qDebug() << "[ModemManagerCpp] Retry" << m_dbusRetryCount << "of" << maxRetries << "in"
                     << delay << "ms";
            m_dbusRetryTimer->start(delay);
        } else {
            qWarning() << "[ModemManagerCpp] Failed to connect to D-Bus after" << maxRetries
                       << "retries";
            qInfo() << "[ModemManagerCpp] Using mock mode (no cellular hardware)";
        }
        return;
    }

    // Create ModemManager D-Bus interface
    m_mmInterface = new QDBusInterface(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", QDBusConnection::systemBus(), this);

    if (m_mmInterface->isValid()) {
        m_hasModemManager = true;
        m_dbusRetryCount  = 0; // Reset retry count on success
        qInfo() << "[ModemManagerCpp] ✓ Connected to ModemManager D-Bus";
        setupDBusConnections();
        discoverModem();
        m_stateMonitor->start();
    } else {
        qDebug() << "[ModemManagerCpp] ModemManager service not available:"
                 << m_mmInterface->lastError().message();

        // Retry with exponential backoff
        const int maxRetries = 10;
        if (m_dbusRetryCount < maxRetries) {
            int delay = qMin(100 * (1 << m_dbusRetryCount), 5000);
            m_dbusRetryCount++;
            m_dbusRetryTimer->start(delay);
        } else {
            qWarning() << "[ModemManagerCpp] ModemManager not available after" << maxRetries
                       << "retries";
            qInfo() << "[ModemManagerCpp] Using mock mode (no cellular hardware)";
        }
    }
}

void ModemManagerCpp::retryDBusConnection() {
    initializeDBusConnection();
}

void ModemManagerCpp::setupDBusConnections() {
    if (!m_hasModemManager)
        return;

    // Connect to InterfacesAdded signal for modem hotplug
    bool connected = QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", this, SLOT(discoverModem()));

    if (!connected) {
        qDebug() << "[ModemManagerCpp] InterfacesAdded signal connection failed (expected - using "
                    "polling)";
    }
}

void ModemManagerCpp::discoverModem() {
    if (!m_hasModemManager)
        return;

    // Get list of modems - use correct DBus type signature
    typedef QMap<QString, QVariantMap>           InterfaceList;
    typedef QMap<QDBusObjectPath, InterfaceList> ManagedObjectList;

    QDBusMessage                                 call = QDBusMessage::createMethodCall(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "GetManagedObjects");

    QDBusMessage reply = QDBusConnection::systemBus().call(call);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qDebug() << "[ModemManagerCpp] Failed to get modems:" << reply.errorMessage();
        if (m_modemAvailable) {
            m_modemAvailable = false;
            emit modemAvailableChanged();
        }
        return;
    }

    // Parse the ObjectManager reply with correct signature: a{oa{sa{sv}}}
    const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();
    ManagedObjectList   objects;
    arg >> objects;

    if (objects.isEmpty()) {
        if (m_modemAvailable) {
            m_modemAvailable = false;
            emit modemAvailableChanged();
            qInfo() << "[ModemManagerCpp] No modems found";
        }
        return;
    }

    // Find first modem with Modem interface
    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        QString       path       = it.key().path();
        InterfaceList interfaces = it.value();

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem")) {
            m_modemPath      = path;
            m_modemAvailable = true;
            emit modemAvailableChanged();
            qInfo() << "[ModemManagerCpp] Modem found:" << m_modemPath;

            queryModemState();
            return;
        }
    }

    // No valid modem found
    if (m_modemAvailable) {
        m_modemAvailable = false;
        emit modemAvailableChanged();
        qInfo() << "[ModemManagerCpp] No valid modem found";
    }
}

void ModemManagerCpp::queryModemState() {
    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty())
        return;

    // Query Modem interface
    QDBusInterface modem("org.freedesktop.ModemManager1", m_modemPath,
                         "org.freedesktop.ModemManager1.Modem", QDBusConnection::systemBus());

    if (!modem.isValid())
        return;

    // Get signal strength
    QDBusInterface modemSignal("org.freedesktop.ModemManager1", m_modemPath,
                               "org.freedesktop.ModemManager1.Modem.Signal",
                               QDBusConnection::systemBus());

    if (modemSignal.isValid()) {
        QVariant signalVar = modemSignal.property("Rssi");
        if (signalVar.isValid()) {
            int rssi = signalVar.toInt(); // RSSI in dBm
            // Convert RSSI to percentage (rough approximation)
            // -50 dBm (excellent) = 100%, -100 dBm (poor) = 0%
            int strength = qBound(0, (rssi + 100) * 2, 100);
            if (m_signalStrength != strength) {
                m_signalStrength = strength;
                emit signalStrengthChanged();
            }
        }
    }

    // Get operator name and network type
    QDBusInterface modem3gpp("org.freedesktop.ModemManager1", m_modemPath,
                             "org.freedesktop.ModemManager1.Modem.Modem3gpp",
                             QDBusConnection::systemBus());

    if (modem3gpp.isValid()) {
        QString opName = modem3gpp.property("OperatorName").toString();
        if (!opName.isEmpty() && m_operatorName != opName) {
            m_operatorName = opName;
            emit operatorNameChanged();
        }

        uint registrationState = modem3gpp.property("RegistrationState").toUInt();
        bool isRegistered = (registrationState == 1 || registrationState == 5); // HOME or ROAMING
        if (m_registered != isRegistered) {
            m_registered = isRegistered;
            emit registeredChanged();
        }
    }

    // Get access technology (network type)
    uint    accessTech = modem.property("AccessTechnologies").toUInt();
    QString netType    = networkTypeFromAccessTech(accessTech);
    if (m_networkType != netType) {
        m_networkType = netType;
        emit networkTypeChanged();
    }
}

QString ModemManagerCpp::networkTypeFromAccessTech(uint accessTech) {
    // ModemManager access technology bitmask
    if (accessTech & 0x8000)
        return "5G"; // MM_MODEM_ACCESS_TECHNOLOGY_5GNR
    if (accessTech & 0x4000)
        return "LTE"; // MM_MODEM_ACCESS_TECHNOLOGY_LTE
    if (accessTech & 0x0600)
        return "HSPA+"; // HSUPA/HSDPA
    if (accessTech & 0x0100)
        return "HSPA";
    if (accessTech & 0x0020)
        return "UMTS"; // 3G
    if (accessTech & 0x0010)
        return "EDGE"; // 2.5G
    if (accessTech & 0x0002)
        return "GPRS"; // 2.5G
    if (accessTech & 0x0001)
        return "GSM"; // 2G
    return "Unknown";
}

void ModemManagerCpp::enable() {
    qDebug() << "[ModemManagerCpp] Enabling modem";

    if (!m_hasModemManager || !m_modemAvailable) {
        qDebug() << "[ModemManagerCpp] Cannot enable - no modem available";
        return;
    }

    QDBusInterface modem("org.freedesktop.ModemManager1", m_modemPath,
                         "org.freedesktop.ModemManager1.Modem", QDBusConnection::systemBus());

    modem.asyncCall("Enable", true);
    m_modemEnabled = true;
    emit modemEnabledChanged();
}

void ModemManagerCpp::disable() {
    qDebug() << "[ModemManagerCpp] Disabling modem";

    if (!m_hasModemManager || !m_modemAvailable)
        return;

    QDBusInterface modem("org.freedesktop.ModemManager1", m_modemPath,
                         "org.freedesktop.ModemManager1.Modem", QDBusConnection::systemBus());

    modem.asyncCall("Enable", false);
    m_modemEnabled = false;
    emit modemEnabledChanged();
}

void ModemManagerCpp::enableData() {
    qDebug() << "[ModemManagerCpp] Enabling mobile data";

    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty()) {
        qWarning() << "[ModemManagerCpp] Cannot enable data: no modem available";
        return;
    }

    // Connect bearer via ModemManager Simple interface
    QDBusInterface simpleInterface("org.freedesktop.ModemManager1", m_modemPath,
                                   "org.freedesktop.ModemManager1.Modem.Simple",
                                   QDBusConnection::systemBus());

    if (!simpleInterface.isValid()) {
        qWarning() << "[ModemManagerCpp] Simple interface not available:"
                   << simpleInterface.lastError().message();
        return;
    }

    // Connect with default APN (empty will use carrier default)
    QVariantMap properties;
    properties["apn"] = ""; // Use carrier default APN

    QDBusReply<void> reply = simpleInterface.call("Connect", properties);
    if (!reply.isValid()) {
        qWarning() << "[ModemManagerCpp] Failed to enable data:" << reply.error().message();
        return;
    }

    m_dataEnabled   = true;
    m_dataConnected = true;
    emit dataEnabledChanged();
    emit dataConnectedChanged();

    qInfo() << "[ModemManagerCpp] ✓ Mobile data enabled";
}

void ModemManagerCpp::disableData() {
    qDebug() << "[ModemManagerCpp] Disabling mobile data";

    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty()) {
        return;
    }

    // Disconnect bearer
    QDBusInterface simpleInterface("org.freedesktop.ModemManager1", m_modemPath,
                                   "org.freedesktop.ModemManager1.Modem.Simple",
                                   QDBusConnection::systemBus());

    if (!simpleInterface.isValid()) {
        return;
    }

    // Disconnect all bearers
    QDBusReply<void> reply = simpleInterface.call("Disconnect", "/");
    if (!reply.isValid()) {
        qWarning() << "[ModemManagerCpp] Failed to disable data:" << reply.error().message();
        return;
    }

    m_dataEnabled   = false;
    m_dataConnected = false;
    emit dataEnabledChanged();
    emit dataConnectedChanged();

    qInfo() << "[ModemManagerCpp] ✓ Mobile data disabled";
}

void ModemManagerCpp::setApn(const QString &apn, const QString &username, const QString &password) {
    qInfo() << "[ModemManagerCpp] Setting APN:" << apn;

    m_apn         = apn;
    m_apnUsername = username;
    m_apnPassword = password;

    // If data is currently enabled, reconnect with new APN
    if (m_dataEnabled) {
        disableData();

        // Wait a moment for disconnect
        QTimer::singleShot(500, this, [this, apn, username, password]() {
            if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty()) {
                return;
            }

            QDBusInterface simpleInterface("org.freedesktop.ModemManager1", m_modemPath,
                                           "org.freedesktop.ModemManager1.Modem.Simple",
                                           QDBusConnection::systemBus());

            if (!simpleInterface.isValid()) {
                return;
            }

            // Connect with APN settings
            QVariantMap properties;
            properties["apn"] = apn;

            if (!username.isEmpty()) {
                properties["user"] = username;
            }

            if (!password.isEmpty()) {
                properties["password"] = password;
            }

            QDBusReply<void> reply = simpleInterface.call("Connect", properties);
            if (!reply.isValid()) {
                qWarning() << "[ModemManagerCpp] Failed to connect with APN:"
                           << reply.error().message();
                return;
            }

            m_dataEnabled   = true;
            m_dataConnected = true;
            emit dataEnabledChanged();
            emit dataConnectedChanged();

            qInfo() << "[ModemManagerCpp] ✓ Connected with custom APN";
        });
    }
}

QString ModemManagerCpp::getApn() const {
    return m_apn;
}

QVariantMap ModemManagerCpp::getApnSettings() const {
    QVariantMap settings;
    settings["apn"]         = m_apn;
    settings["username"]    = m_apnUsername;
    settings["hasPassword"] = !m_apnPassword.isEmpty();
    return settings;
}
