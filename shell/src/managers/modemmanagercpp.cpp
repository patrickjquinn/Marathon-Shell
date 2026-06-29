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

    m_stateMonitor = new QTimer(this);
    // 60s safety-net poll for cosmetic status-bar fields (signal bars,
    // operator name, network type). Incoming calls and SMS come via
    // ModemManager's CallAdded / SMS signals from the daemon side; this
    // poll is only a backstop for property drift the signal subscriptions
    // may have missed. 5s here was burning ~17280 D-Bus calls/day for
    // properties that change on the minute-scale.
    m_stateMonitor->setInterval(60000);
    connect(m_stateMonitor, &QTimer::timeout, this, [this]() {
        // If we lost the race with ModemManager at shell startup, the
        // initial discoverModem() returned no objects and InterfacesAdded
        // never fired (modem was already there from MM's perspective).
        // Retry discovery on every tick until we latch on; this is what
        // makes the cellular icon appear after a cold boot where the
        // shell came up before ModemManager finished publishing the
        // Modem object path on the system bus.
        if (m_hasModemManager && !m_modemAvailable)
            discoverModem();
        queryModemState();
    });

    m_dbusRetryTimer = new QTimer(this);
    m_dbusRetryTimer->setSingleShot(true);
    connect(m_dbusRetryTimer, &QTimer::timeout, this, &ModemManagerCpp::retryDBusConnection);

    initializeDBusConnection();
}

void ModemManagerCpp::initializeDBusConnection() {

    if (!QDBusConnection::systemBus().isConnected()) {
        qWarning() << "[ModemManagerCpp] D-Bus system bus not connected, will retry...";

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

    m_mmInterface = new QDBusInterface(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", QDBusConnection::systemBus(), this);

    if (m_mmInterface->isValid()) {
        m_hasModemManager = true;
        m_dbusRetryCount  = 0;
        qInfo() << "[ModemManagerCpp] Connected to ModemManager D-Bus";
        setupDBusConnections();
        discoverModem();
        m_stateMonitor->start();
    } else {
        qDebug() << "[ModemManagerCpp] ModemManager service not available:"
                 << m_mmInterface->lastError().message();

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

    bool connected = QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", this, SLOT(discoverModem()));

    if (!connected) {
        qDebug() << "[ModemManagerCpp] InterfacesAdded signal connection failed (expected - using "
                    "polling)";
    }
}

void ModemManagerCpp::attachModemPropertySubscriptions() {
    if (m_modemPath.isEmpty())
        return;

    // Per-interface PropertiesChanged. Path-scoped so we don't catch
    // unrelated PropertiesChanged on every sibling object the daemon
    // emits — the system bus argument-path match keeps this cheap.
    QDBusConnection bus     = QDBusConnection::systemBus();
    const QString   props   = QStringLiteral("org.freedesktop.DBus.Properties");
    const QString   changed = QStringLiteral("PropertiesChanged");

    bus.connect("org.freedesktop.ModemManager1", m_modemPath, props, changed, this,
                SLOT(onModemPropertiesChanged()));

    qDebug() << "[ModemManagerCpp] Subscribed to PropertiesChanged on" << m_modemPath;
}

void ModemManagerCpp::onModemPropertiesChanged() {
    // The 60s safety-net stays armed (queryModemState fires it via the
    // m_stateMonitor timer) — this push-driven path just makes us
    // react instantly on real changes instead of waiting up to a
    // minute for the next poll. queryModemState is idempotent and
    // cheap (six property fetches against an already-cached daemon
    // path), so we don't bother filtering by changed_props here.
    queryModemState();
}

void ModemManagerCpp::discoverModem() {
    if (!m_hasModemManager)
        return;

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

    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        QString              path       = it.key().path();
        const InterfaceList &interfaces = it.value();

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem")) {
            m_modemPath      = path;
            m_modemAvailable = true;
            emit modemAvailableChanged();
            qInfo() << "[ModemManagerCpp] Modem found:" << m_modemPath;

            attachModemPropertySubscriptions();
            queryModemState();
            return;
        }
    }

    if (m_modemAvailable) {
        m_modemAvailable = false;
        emit modemAvailableChanged();
        qInfo() << "[ModemManagerCpp] No valid modem found";
    }
}

void ModemManagerCpp::queryModemState() {
    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty())
        return;

    QDBusInterface modem("org.freedesktop.ModemManager1", m_modemPath,
                         "org.freedesktop.ModemManager1.Modem", QDBusConnection::systemBus());

    if (!modem.isValid())
        return;

    // Query SIM presence via the Modem's Sim property (object path, empty = no SIM)
    QVariant simPathVar = modem.property("Sim");
    bool hasSim = simPathVar.isValid() && !simPathVar.value<QDBusObjectPath>().path().isEmpty() &&
        simPathVar.value<QDBusObjectPath>().path() != "/";
    if (m_simPresent != hasSim) {
        m_simPresent = hasSim;
        emit simPresentChanged();
        qInfo() << "[ModemManagerCpp] SIM present:" << m_simPresent;
    }

    // Query modem enabled state
    uint modemState = modem.property("State").toUInt();
    bool enabled    = (modemState >= 3); // MM_MODEM_STATE_ENABLED = 3
    if (m_modemEnabled != enabled) {
        m_modemEnabled = enabled;
        emit modemEnabledChanged();
    }

    QDBusInterface modemSignal("org.freedesktop.ModemManager1", m_modemPath,
                               "org.freedesktop.ModemManager1.Modem.Signal",
                               QDBusConnection::systemBus());

    if (modemSignal.isValid()) {
        QVariant signalVar = modemSignal.property("Rssi");
        if (signalVar.isValid()) {
            int rssi = signalVar.toInt();

            int strength = qBound(0, (rssi + 100) * 2, 100);
            if (m_signalStrength != strength) {
                m_signalStrength = strength;
                emit signalStrengthChanged();
            }
        }
    }

    QDBusInterface modem3gpp("org.freedesktop.ModemManager1", m_modemPath,
                             "org.freedesktop.ModemManager1.Modem.Modem3gpp",
                             QDBusConnection::systemBus());

    if (modem3gpp.isValid()) {
        QString opName = modem3gpp.property("OperatorName").toString();
        if (!opName.isEmpty() && m_operatorName != opName) {
            m_operatorName = opName;
            emit operatorNameChanged();
        }

        QString opCode = modem3gpp.property("OperatorCode").toString();
        if (m_operatorCode != opCode) {
            m_operatorCode = opCode;
            emit operatorCodeChanged();
        }

        uint registrationState = modem3gpp.property("RegistrationState").toUInt();
        bool isRegistered      = (registrationState == 1 || registrationState == 5);
        if (m_registered != isRegistered) {
            m_registered = isRegistered;
            emit registeredChanged();
        }

        // MM_MODEM_3GPP_REGISTRATION_STATE_ROAMING = 5
        bool isRoaming = (registrationState == 5);
        if (m_roaming != isRoaming) {
            m_roaming = isRoaming;
            emit roamingChanged();
        }
    }

    uint    accessTech = modem.property("AccessTechnologies").toUInt();
    QString netType    = networkTypeFromAccessTech(accessTech);
    if (m_networkType != netType) {
        m_networkType = netType;
        emit networkTypeChanged();
    }

    // Emergency-call posture: Voice.EmergencyOnly is true when only 112/911-class
    // calls will be accepted (no SIM, PIN-locked, limited service). Sim.EmergencyNumbers
    // surfaces the EF_ECC list -- readable while PIN-locked. The lock-screen
    // affordance reads both; we never hard-code the list (3GPP TS 22.101 + the SIM provide it).
    QDBusInterface modemVoice("org.freedesktop.ModemManager1", m_modemPath,
                              "org.freedesktop.ModemManager1.Modem.Voice",
                              QDBusConnection::systemBus());
    if (modemVoice.isValid()) {
        QVariant emergencyOnlyVar = modemVoice.property("EmergencyOnly");
        if (emergencyOnlyVar.isValid()) {
            const bool eo = emergencyOnlyVar.toBool();
            if (m_emergencyOnly != eo) {
                m_emergencyOnly = eo;
                emit emergencyOnlyChanged();
                qInfo() << "[ModemManagerCpp] Emergency-only:" << m_emergencyOnly;
            }
        }
    }

    QString simPath = simPathVar.value<QDBusObjectPath>().path();
    if (!simPath.isEmpty() && simPath != "/") {
        QDBusInterface sim("org.freedesktop.ModemManager1", simPath,
                           "org.freedesktop.ModemManager1.Sim", QDBusConnection::systemBus());
        if (sim.isValid()) {
            QStringList simEcc = sim.property("EmergencyNumbers").toStringList();
            if (m_simEmergencyNumbers != simEcc) {
                m_simEmergencyNumbers = simEcc;
                emit simEmergencyNumbersChanged();
            }
        }
    } else if (!m_simEmergencyNumbers.isEmpty()) {
        m_simEmergencyNumbers.clear();
        emit simEmergencyNumbersChanged();
    }
}

QString ModemManagerCpp::networkTypeFromAccessTech(uint accessTech) {

    if (accessTech & 0x8000)
        return "5G";
    if (accessTech & 0x4000)
        return "LTE";
    if (accessTech & 0x0600)
        return "HSPA+";
    if (accessTech & 0x0100)
        return "HSPA";
    if (accessTech & 0x0020)
        return "UMTS";
    if (accessTech & 0x0010)
        return "EDGE";
    if (accessTech & 0x0002)
        return "GPRS";
    if (accessTech & 0x0001)
        return "GSM";
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

    QDBusInterface simpleInterface("org.freedesktop.ModemManager1", m_modemPath,
                                   "org.freedesktop.ModemManager1.Modem.Simple",
                                   QDBusConnection::systemBus());

    if (!simpleInterface.isValid()) {
        qWarning() << "[ModemManagerCpp] Simple interface not available:"
                   << simpleInterface.lastError().message();
        return;
    }

    QVariantMap properties;
    properties["apn"] = "";

    QDBusReply<void> reply = simpleInterface.call("Connect", properties);
    if (!reply.isValid()) {
        qWarning() << "[ModemManagerCpp] Failed to enable data:" << reply.error().message();
        return;
    }

    m_dataEnabled   = true;
    m_dataConnected = true;
    emit dataEnabledChanged();
    emit dataConnectedChanged();

    qInfo() << "[ModemManagerCpp] Mobile data enabled";
}

void ModemManagerCpp::disableData() {
    qDebug() << "[ModemManagerCpp] Disabling mobile data";

    if (!m_hasModemManager || !m_modemAvailable || m_modemPath.isEmpty()) {
        return;
    }

    QDBusInterface simpleInterface("org.freedesktop.ModemManager1", m_modemPath,
                                   "org.freedesktop.ModemManager1.Modem.Simple",
                                   QDBusConnection::systemBus());

    if (!simpleInterface.isValid()) {
        return;
    }

    QDBusReply<void> reply = simpleInterface.call("Disconnect", "/");
    if (!reply.isValid()) {
        qWarning() << "[ModemManagerCpp] Failed to disable data:" << reply.error().message();
        return;
    }

    m_dataEnabled   = false;
    m_dataConnected = false;
    emit dataEnabledChanged();
    emit dataConnectedChanged();

    qInfo() << "[ModemManagerCpp] Mobile data disabled";
}

void ModemManagerCpp::setApn(const QString &apn, const QString &username, const QString &password) {
    qInfo() << "[ModemManagerCpp] Setting APN:" << apn;

    m_apn         = apn;
    m_apnUsername = username;
    m_apnPassword = password;

    if (m_dataEnabled) {
        disableData();

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

            qInfo() << "[ModemManagerCpp] Connected with custom APN";
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
