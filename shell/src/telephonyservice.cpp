#include "telephonyservice.h"
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDebug>

TelephonyService::TelephonyService(QObject *parent)
    : QObject(parent)
    , m_modemManager(nullptr)
    , m_voiceCall(nullptr)
    , m_callState("idle")
    , m_hasModem(false)
    , m_reconnectTimer(new QTimer(this)) {
    qDebug() << "[TelephonyService] Initializing";

    connectToModemManager();

    // Setup reconnect timer for modem detection
    m_reconnectTimer->setInterval(10000); // Check every 10 seconds
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, &TelephonyService::checkModemStatus);
    if (QDBusConnection::systemBus().isConnected()) {
        m_reconnectTimer->start();
    }

    qInfo() << "[TelephonyService] Initialized";
}

TelephonyService::~TelephonyService() {
    if (m_voiceCall) {
        delete m_voiceCall;
    }
    if (m_modemManager) {
        delete m_modemManager;
    }
}

QString TelephonyService::callState() const {
    return m_callState;
}

bool TelephonyService::hasModem() const {
    return m_hasModem;
}

QString TelephonyService::activeNumber() const {
    return m_activeNumber;
}

void TelephonyService::dial(const QString &number) {
    if (number.isEmpty()) {
        qWarning() << "[TelephonyService] Cannot dial empty number";
        return;
    }

    qInfo() << "[TelephonyService] Dialing:" << number;

    if (!m_hasModem) {
        qWarning() << "[TelephonyService] No modem available";
        emit callFailed("No modem available");
        return;
    }

    // Call ModemManager D-Bus method to create voice call
    QDBusInterface voiceInterface("org.freedesktop.ModemManager1", m_modemPath,
                                  "org.freedesktop.ModemManager1.Modem.Voice",
                                  QDBusConnection::systemBus());

    if (!voiceInterface.isValid()) {
        qWarning() << "[TelephonyService] Voice interface not available:"
                   << voiceInterface.lastError().message();
        emit callFailed("Voice interface not available");
        return;
    }

    // Create call
    QVariantMap properties;
    properties["number"] = number;

    QDBusReply<QDBusObjectPath> reply =
        voiceInterface.call("CreateCall", QVariant::fromValue(properties));

    if (!reply.isValid()) {
        qWarning() << "[TelephonyService] Failed to create call:" << reply.error().message();
        emit callFailed("Failed to create call: " + reply.error().message());
        return;
    }

    QString callPath = reply.value().path();
    qDebug() << "[TelephonyService] Call created:" << callPath;

    // Start the call
    QDBusInterface callInterface("org.freedesktop.ModemManager1", callPath,
                                 "org.freedesktop.ModemManager1.Call",
                                 QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Call interface not available";
        emit callFailed("Call interface not available");
        return;
    }

    QDBusReply<void> startReply = callInterface.call("Start");
    if (!startReply.isValid()) {
        qWarning() << "[TelephonyService] Failed to start call:" << startReply.error().message();
        emit callFailed("Failed to start call: " + startReply.error().message());
        return;
    }

    m_activeCallPath = callPath;
    m_activeNumber   = number;
    m_callState      = "dialing";

    // Monitor call state changes
    setupCallMonitoring(callPath);

    emit callStateChanged("dialing");
    emit activeNumberChanged(number);

    qInfo() << "[TelephonyService] ✓ Call started to:" << number;
}

void TelephonyService::answer() {
    qInfo() << "[TelephonyService] Answering call";

    if (m_activeCallPath.isEmpty()) {
        qWarning() << "[TelephonyService] No active call to answer";
        return;
    }

    // Handle simulation mode
    if (m_activeCallPath.contains("simulate")) {
        m_callState = "active";
        emit callStateChanged("active");
        qInfo() << "[TelephonyService] [SIMULATION] ✓ Call answered";
        return;
    }

    QDBusInterface callInterface("org.freedesktop.ModemManager1", m_activeCallPath,
                                 "org.freedesktop.ModemManager1.Call",
                                 QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Call interface not available";
        emit callFailed("Call interface not available");
        return;
    }

    QDBusReply<void> reply = callInterface.call("Accept");
    if (!reply.isValid()) {
        qWarning() << "[TelephonyService] Failed to answer call:" << reply.error().message();
        emit callFailed("Failed to answer call: " + reply.error().message());
        return;
    }

    m_callState = "active";
    emit callStateChanged("active");

    qInfo() << "[TelephonyService] ✓ Call answered";
}

void TelephonyService::hangup() {
    qInfo() << "[TelephonyService] Hanging up call";

    if (m_activeCallPath.isEmpty()) {
        qWarning() << "[TelephonyService] No active call to hang up";
        return;
    }

    // Handle simulation mode
    if (m_activeCallPath.contains("simulate")) {
        m_callState = "idle";
        m_activeCallPath.clear();
        m_activeNumber.clear();

        emit callStateChanged("idle");
        emit activeNumberChanged("");

        qInfo() << "[TelephonyService] [SIMULATION] ✓ Call hung up";
        return;
    }

    QDBusInterface callInterface("org.freedesktop.ModemManager1", m_activeCallPath,
                                 "org.freedesktop.ModemManager1.Call",
                                 QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Call interface not available";
        return;
    }

    QDBusReply<void> reply = callInterface.call("Hangup");
    if (!reply.isValid()) {
        qWarning() << "[TelephonyService] Failed to hang up:" << reply.error().message();
        return;
    }

    m_callState = "idle";
    m_activeCallPath.clear();
    m_activeNumber.clear();

    emit callStateChanged("idle");
    emit activeNumberChanged("");

    qInfo() << "[TelephonyService] ✓ Call hung up";
}

void TelephonyService::sendDTMF(const QString &digit) {
    qDebug() << "[TelephonyService] Sending DTMF:" << digit;

    if (m_activeCallPath.isEmpty()) {
        qWarning() << "[TelephonyService] No active call for DTMF";
        return;
    }

    if (m_callState != "active") {
        qWarning() << "[TelephonyService] Call must be active to send DTMF";
        return;
    }

    QDBusInterface callInterface("org.freedesktop.ModemManager1", m_activeCallPath,
                                 "org.freedesktop.ModemManager1.Call",
                                 QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Call interface not available";
        return;
    }

    QDBusReply<void> reply = callInterface.call("SendDtmf", digit);
    if (!reply.isValid()) {
        qWarning() << "[TelephonyService] Failed to send DTMF:" << reply.error().message();
        return;
    }

    qDebug() << "[TelephonyService] ✓ DTMF sent:" << digit;
}

void TelephonyService::simulateIncomingCall(const QString &number) {
    qInfo() << "[TelephonyService] [SIMULATION] Simulating incoming call from:" << number;

    m_activeNumber   = number;
    m_callState      = "incoming";
    m_activeCallPath = "/org/freedesktop/ModemManager1/Call/simulate"; // Mock path for simulation

    emit incomingCall(number);
    emit callStateChanged("incoming");
    emit activeNumberChanged(number);
}

void TelephonyService::simulateCallStateChange(const QString &state) {
    qInfo() << "[TelephonyService] [SIMULATION] Simulating call state change to:" << state;

    if (state != m_callState) {
        m_callState = state;
        emit callStateChanged(state);

        if (state == "idle" || state == "terminated") {
            m_activeCallPath.clear();
            m_activeNumber.clear();
            emit activeNumberChanged("");
        }
    }
}

void TelephonyService::connectToModemManager() {
    qDebug() << "[TelephonyService] Connecting to ModemManager";

    m_modemManager = new QDBusInterface(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", QDBusConnection::systemBus(), this);

    if (!m_modemManager->isValid()) {
        qDebug() << "[TelephonyService] ModemManager not available:"
                 << m_modemManager->lastError().message();
        return;
    }

    qInfo() << "[TelephonyService] ✓ Connected to ModemManager";

    setupDBusConnections();
    checkModemStatus();
}

void TelephonyService::setupDBusConnections() {
    // Monitor for modems being added/removed
    QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", this, SLOT(checkModemStatus()));

    QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved", this, SLOT(checkModemStatus()));
}

void TelephonyService::checkModemStatus() {
    if (!m_modemManager || !m_modemManager->isValid()) {
        if (m_hasModem) {
            m_hasModem = false;
            emit modemChanged(false);
        }
        return;
    }

    // Get list of modems - use correct DBus type
    typedef QMap<QString, QVariantMap>           InterfaceList;
    typedef QMap<QDBusObjectPath, InterfaceList> ManagedObjectList;

    QDBusMessage                                 msg = m_modemManager->call("GetManagedObjects");
    if (msg.type() == QDBusMessage::ErrorMessage) {
        qDebug() << "[TelephonyService] Failed to get modems:" << msg.errorMessage();
        if (m_hasModem) {
            m_hasModem = false;
            emit modemChanged(false);
        }
        return;
    }

    const QDBusArgument arg = msg.arguments().at(0).value<QDBusArgument>();
    ManagedObjectList   objects;
    arg >> objects;

    // Find first modem with Voice capability
    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        QString       path       = it.key().path();
        InterfaceList interfaces = it.value();

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem.Voice")) {
            if (m_modemPath != path) {
                m_modemPath = path;
                qInfo() << "[TelephonyService] Modem with Voice capability found:" << path;
            }

            if (!m_hasModem) {
                m_hasModem = true;
                emit modemChanged(true);
            }

            // Monitor for incoming calls
            monitorIncomingCalls();
            return;
        }
    }

    // No modem found
    if (m_hasModem) {
        m_hasModem = false;
        m_modemPath.clear();
        emit modemChanged(false);
        qDebug() << "[TelephonyService] No modem with Voice capability available";
    }
}

void TelephonyService::setupCallMonitoring(const QString &callPath) {
    // Monitor call property changes
    QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", callPath, "org.freedesktop.DBus.Properties",
        "PropertiesChanged", this,
        SLOT(onModemManagerPropertiesChanged(QString, QVariantMap, QStringList)));
}

void TelephonyService::monitorIncomingCalls() {
    if (m_modemPath.isEmpty())
        return;

    // Monitor for new calls being added
    QDBusConnection::systemBus().connect("org.freedesktop.ModemManager1", m_modemPath,
                                         "org.freedesktop.ModemManager1.Modem.Voice", "CallAdded",
                                         this, SLOT(onCallAdded(QDBusObjectPath)));
}

void TelephonyService::onCallAdded(const QDBusObjectPath &callPath) {
    QString path = callPath.path();
    qInfo() << "[TelephonyService] New call detected:" << path;

    // Get call properties
    QDBusInterface callInterface("org.freedesktop.ModemManager1", path,
                                 "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Cannot get call properties";
        return;
    }

    // Get call direction (incoming/outgoing)
    QDBusReply<QVariant> directionReply =
        callInterface.call("Get", "org.freedesktop.ModemManager1.Call", "Direction");

    if (directionReply.isValid()) {
        uint direction = directionReply.value().toUInt();

        // 0 = unknown, 1 = incoming, 2 = outgoing
        if (direction == 1) {
            // Incoming call
            QDBusReply<QVariant> numberReply =
                callInterface.call("Get", "org.freedesktop.ModemManager1.Call", "Number");

            QString number = "Unknown";
            if (numberReply.isValid()) {
                number = numberReply.value().toString();
            }

            m_activeCallPath = path;
            m_activeNumber   = number;
            m_callState      = "incoming";

            setupCallMonitoring(path);

            emit incomingCall(number);
            emit callStateChanged("incoming");
            emit activeNumberChanged(number);

            qInfo() << "[TelephonyService] ✓ Incoming call from:" << number;
        }
    }
}

void TelephonyService::onModemManagerPropertiesChanged(const QString     &interface,
                                                       const QVariantMap &changed,
                                                       const QStringList &invalidated) {
    Q_UNUSED(invalidated)

    if (interface == "org.freedesktop.ModemManager1.Call") {
        if (changed.contains("State")) {
            uint    state    = changed.value("State").toUInt();
            QString newState = callStateFromModemManager(state);

            if (newState != m_callState) {
                m_callState = newState;
                emit callStateChanged(newState);
                qDebug() << "[TelephonyService] Call state changed to:" << newState;

                // Call ended
                if (newState == "idle" || newState == "terminated") {
                    m_activeCallPath.clear();
                    m_activeNumber.clear();
                    emit activeNumberChanged("");
                }
            }
        }
    }
}

QString TelephonyService::callStateFromModemManager(uint mmState) {
    // ModemManager call states:
    // 0 = Unknown, 1 = Dialing, 2 = Ringing-out, 3 = Ringing-in
    // 4 = Active, 5 = Held, 6 = Waiting, 7 = Terminated

    switch (mmState) {
        case 0: return "unknown";
        case 1: return "dialing";
        case 2: return "ringing";
        case 3: return "incoming";
        case 4: return "active";
        case 5: return "held";
        case 6: return "waiting";
        case 7: return "terminated";
        default: return "unknown";
    }
}

QString TelephonyService::extractNumberFromPath(const QString &path) {
    // Extract number from call path if embedded
    // This is a fallback; normally we get it from properties
    return "Unknown";
}
