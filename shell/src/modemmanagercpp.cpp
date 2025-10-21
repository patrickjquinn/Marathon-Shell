#include "modemmanagercpp.h"
#include <QDebug>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QDBusMetaType>
#include <QRandomGenerator>

ModemManagerCpp::ModemManagerCpp(QObject* parent)
    : QObject(parent)
    , m_mmInterface(nullptr)
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
    , m_dataConnected(false)
{
    qDebug() << "[ModemManagerCpp] Initializing";
    
    m_mmInterface = new QDBusInterface(
        "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        QDBusConnection::systemBus(),
        this
    );
    
    if (m_mmInterface->isValid()) {
        m_hasModemManager = true;
        qInfo() << "[ModemManagerCpp] Connected to ModemManager D-Bus";
        setupDBusConnections();
        discoverModem();
    } else {
        qDebug() << "[ModemManagerCpp] ModemManager D-Bus not available:" << m_mmInterface->lastError().message();
        qInfo() << "[ModemManagerCpp] Using mock mode (no cellular hardware)";
    }
    
    // Setup state monitor
    m_stateMonitor = new QTimer(this);
    m_stateMonitor->setInterval(5000); // Poll every 5 seconds
    connect(m_stateMonitor, &QTimer::timeout, this, &ModemManagerCpp::queryModemState);
    if (m_hasModemManager) {
        m_stateMonitor->start();
    }
}

void ModemManagerCpp::setupDBusConnections()
{
    if (!m_hasModemManager) return;
    
    // Connect to InterfacesAdded signal for modem hotplug
    bool connected = QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        "InterfacesAdded",
        this,
        SLOT(discoverModem())
    );
    
    if (!connected) {
        qDebug() << "[ModemManagerCpp] InterfacesAdded signal connection failed (expected - using polling)";
    }
}

void ModemManagerCpp::discoverModem()
{
    if (!m_hasModemManager) return;
    
    QDBusMessage call = QDBusMessage::createMethodCall(
        "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects"
    );
    
    QDBusReply<QVariantMap> reply = QDBusConnection::systemBus().call(call);
    if (!reply.isValid()) {
        qDebug() << "[ModemManagerCpp] Failed to get modems:" << reply.error().message();
        return;
    }
    
    QVariantMap objects = reply.value();
    if (objects.isEmpty()) {
        if (m_modemAvailable) {
            m_modemAvailable = false;
            emit modemAvailableChanged();
            qInfo() << "[ModemManagerCpp] No modems found";
        }
        return;
    }
    
    // Use the first modem found
    m_modemPath = objects.firstKey();
    m_modemAvailable = true;
    emit modemAvailableChanged();
    qInfo() << "[ModemManagerCpp] Modem found:" << m_modemPath;
    
    queryModemState();
}

void ModemManagerCpp::queryModemState()
{
    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty()) return;
    
    // Query Modem interface
    QDBusInterface modem(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem",
        QDBusConnection::systemBus()
    );
    
    if (!modem.isValid()) return;
    
    // Get signal strength
    QDBusInterface modemSignal(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem.Signal",
        QDBusConnection::systemBus()
    );
    
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
    QDBusInterface modem3gpp(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem.Modem3gpp",
        QDBusConnection::systemBus()
    );
    
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
    uint accessTech = modem.property("AccessTechnologies").toUInt();
    QString netType = networkTypeFromAccessTech(accessTech);
    if (m_networkType != netType) {
        m_networkType = netType;
        emit networkTypeChanged();
    }
}

QString ModemManagerCpp::networkTypeFromAccessTech(uint accessTech)
{
    // ModemManager access technology bitmask
    if (accessTech & 0x8000) return "5G"; // MM_MODEM_ACCESS_TECHNOLOGY_5GNR
    if (accessTech & 0x4000) return "LTE"; // MM_MODEM_ACCESS_TECHNOLOGY_LTE
    if (accessTech & 0x0600) return "HSPA+"; // HSUPA/HSDPA
    if (accessTech & 0x0100) return "HSPA";
    if (accessTech & 0x0020) return "UMTS"; // 3G
    if (accessTech & 0x0010) return "EDGE"; // 2.5G
    if (accessTech & 0x0002) return "GPRS"; // 2.5G
    if (accessTech & 0x0001) return "GSM"; // 2G
    return "Unknown";
}

void ModemManagerCpp::enable()
{
    qDebug() << "[ModemManagerCpp] Enabling modem";
    
    if (!m_hasModemManager || !m_modemAvailable) {
        qDebug() << "[ModemManagerCpp] Cannot enable - no modem available";
        return;
    }
    
    QDBusInterface modem(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem",
        QDBusConnection::systemBus()
    );
    
    modem.asyncCall("Enable", true);
    m_modemEnabled = true;
    emit modemEnabledChanged();
}

void ModemManagerCpp::disable()
{
    qDebug() << "[ModemManagerCpp] Disabling modem";
    
    if (!m_hasModemManager || !m_modemAvailable) return;
    
    QDBusInterface modem(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem",
        QDBusConnection::systemBus()
    );
    
    modem.asyncCall("Enable", false);
    m_modemEnabled = false;
    emit modemEnabledChanged();
}

void ModemManagerCpp::enableData()
{
    qDebug() << "[ModemManagerCpp] Enabling mobile data";
    m_dataEnabled = true;
    emit dataEnabledChanged();
}

void ModemManagerCpp::disableData()
{
    qDebug() << "[ModemManagerCpp] Disabling mobile data";
    m_dataEnabled = false;
    emit dataEnabledChanged();
}

