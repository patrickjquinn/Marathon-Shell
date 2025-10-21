#include "telephonyservice.h"
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDebug>

TelephonyService::TelephonyService(QObject *parent)
    : QObject(parent)
    , m_modemManager(nullptr)
    , m_voiceCall(nullptr)
    , m_callState("idle")
    , m_hasModem(false)
    , m_reconnectTimer(new QTimer(this))
{
#ifdef Q_OS_MACOS
    m_stubMode = true;
    qDebug() << "[TelephonyService] Running in STUB mode (macOS)";
#else
    connectToModemManager();
    
    // Setup reconnect timer for modem detection (longer interval to reduce spam in VMs)
    m_reconnectTimer->setInterval(30000);  // Changed from 5s to 30s
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, &TelephonyService::checkModemStatus);
    // Only start timer if we have a chance of finding a modem
    if (QDBusConnection::systemBus().isConnected()) {
        m_reconnectTimer->start();
    }
#endif
    
    qDebug() << "[TelephonyService] Initialized";
}

TelephonyService::~TelephonyService()
{
    if (m_voiceCall) {
        delete m_voiceCall;
    }
    if (m_modemManager) {
        delete m_modemManager;
    }
}

QString TelephonyService::callState() const
{
    return m_callState;
}

bool TelephonyService::hasModem() const
{
    return m_hasModem;
}

QString TelephonyService::activeNumber() const
{
    return m_activeNumber;
}

void TelephonyService::dial(const QString& number)
{
    if (number.isEmpty()) {
        qWarning() << "[TelephonyService] Cannot dial empty number";
        return;
    }
    
    qDebug() << "[TelephonyService] Dialing:" << number;
    
#ifdef Q_OS_MACOS
    handleStubDial(number);
#else
    if (!m_hasModem) {
        qWarning() << "[TelephonyService] No modem available";
        emit callFailed("No modem available");
        return;
    }
    
    // Call ModemManager D-Bus method to create voice call
    QDBusInterface voiceInterface(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.ModemManager1.Modem.Voice",
        QDBusConnection::systemBus()
    );
    
    if (!voiceInterface.isValid()) {
        qWarning() << "[TelephonyService] Voice interface not available";
        emit callFailed("Voice interface not available");
        return;
    }
    
    QDBusReply<QDBusObjectPath> reply = voiceInterface.call("CreateCall", number);
    
    if (reply.isValid()) {
        QString callPath = reply.value().path();
        qDebug() << "[TelephonyService] Call created:" << callPath;
        
        // Start the call
        QDBusInterface callInterface(
            "org.freedesktop.ModemManager1",
            callPath,
            "org.freedesktop.ModemManager1.Call",
            QDBusConnection::systemBus()
        );
        
        QDBusReply<void> startReply = callInterface.call("Start");
        if (startReply.isValid()) {
            m_activeNumber = number;
            m_callState = "dialing";
            emit callStateChanged(m_callState);
            emit activeNumberChanged(m_activeNumber);
        } else {
            qWarning() << "[TelephonyService] Failed to start call:" << startReply.error().message();
            emit callFailed(startReply.error().message());
        }
    } else {
        qWarning() << "[TelephonyService] Failed to create call:" << reply.error().message();
        emit callFailed(reply.error().message());
    }
#endif
}

void TelephonyService::answer()
{
    qDebug() << "[TelephonyService] Answering call";
    
#ifdef Q_OS_MACOS
    m_callState = "active";
    emit callStateChanged(m_callState);
#else
    if (m_voiceCall && m_voiceCall->isValid()) {
        QDBusReply<void> reply = m_voiceCall->call("Accept");
        if (reply.isValid()) {
            m_callState = "active";
            emit callStateChanged(m_callState);
        } else {
            qWarning() << "[TelephonyService] Failed to answer call:" << reply.error().message();
        }
    }
#endif
}

void TelephonyService::hangup()
{
    qDebug() << "[TelephonyService] Hanging up call";
    
#ifdef Q_OS_MACOS
    m_callState = "idle";
    m_activeNumber.clear();
    emit callStateChanged(m_callState);
    emit activeNumberChanged(m_activeNumber);
#else
    if (m_voiceCall && m_voiceCall->isValid()) {
        QDBusReply<void> reply = m_voiceCall->call("Hangup");
        if (reply.isValid()) {
            m_callState = "idle";
            m_activeNumber.clear();
            emit callStateChanged(m_callState);
            emit activeNumberChanged(m_activeNumber);
        } else {
            qWarning() << "[TelephonyService] Failed to hangup:" << reply.error().message();
        }
    }
#endif
}

void TelephonyService::sendDTMF(const QString& digit)
{
    qDebug() << "[TelephonyService] Sending DTMF:" << digit;
    
#ifndef Q_OS_MACOS
    if (m_voiceCall && m_voiceCall->isValid()) {
        QDBusReply<void> reply = m_voiceCall->call("SendDtmf", digit);
        if (!reply.isValid()) {
            qWarning() << "[TelephonyService] Failed to send DTMF:" << reply.error().message();
        }
    }
#endif
}

void TelephonyService::connectToModemManager()
{
#ifndef Q_OS_MACOS
    qDebug() << "[TelephonyService] Connecting to ModemManager...";
    
    // Check if ModemManager is available on D-Bus
    QDBusConnectionInterface *interface = QDBusConnection::systemBus().interface();
    if (!interface->isServiceRegistered("org.freedesktop.ModemManager1")) {
        qWarning() << "[TelephonyService] ModemManager not available on D-Bus";
        m_hasModem = false;
        emit modemChanged(false);
        return;
    }
    
    // Connect to ModemManager
    m_modemManager = new QDBusInterface(
        "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        QDBusConnection::systemBus(),
        this
    );
    
    if (!m_modemManager->isValid()) {
        qWarning() << "[TelephonyService] Failed to connect to ModemManager:" << m_modemManager->lastError().message();
        m_hasModem = false;
        emit modemChanged(false);
        return;
    }
    
    // Get list of modems
    QDBusReply<QVariantMap> reply = m_modemManager->call("GetManagedObjects");
    if (reply.isValid()) {
        QVariantMap objects = reply.value();
        
        if (objects.isEmpty()) {
            qDebug() << "[TelephonyService] No modems detected";
            m_hasModem = false;
            emit modemChanged(false);
        } else {
            // Use first modem found
            m_modemPath = objects.keys().first();
            m_hasModem = true;
            emit modemChanged(true);
            qDebug() << "[TelephonyService] Modem detected:" << m_modemPath;
            
            setupDBusConnections();
        }
    } else {
        // Reduce log spam - only log once or when status changes
        static bool hasLogged = false;
        if (!hasLogged) {
            qDebug() << "[TelephonyService] No modem detected (running in VM or no hardware)";
            hasLogged = true;
        }
        m_hasModem = false;
        emit modemChanged(false);
        // Stop polling if consistently failing
        if (m_reconnectTimer && m_reconnectTimer->isActive()) {
            m_reconnectTimer->stop();
        }
    }
#endif
}

void TelephonyService::setupDBusConnections()
{
#ifndef Q_OS_MACOS
    // Monitor modem properties for incoming calls and state changes
    QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1",
        m_modemPath,
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        this,
        SLOT(onModemManagerPropertiesChanged(QString, QVariantMap, QStringList))
    );
    
    qDebug() << "[TelephonyService] D-Bus connections established";
#endif
}

void TelephonyService::onModemManagerPropertiesChanged(const QString& interface, const QVariantMap& changed, const QStringList& invalidated)
{
    Q_UNUSED(invalidated);
    
    qDebug() << "[TelephonyService] Properties changed on" << interface;
    
    // Handle voice call state changes
    if (interface.contains("Call")) {
        if (changed.contains("State")) {
            int state = changed["State"].toInt();
            // ModemManager call states: 0=unknown, 1=dialing, 2=ringing-out, 3=ringing-in, 4=active, 5=held, 6=waiting, 7=terminated
            
            switch (state) {
                case 1:
                    m_callState = "dialing";
                    break;
                case 2:
                    m_callState = "ringing";
                    break;
                case 3:
                    m_callState = "incoming";
                    if (changed.contains("Number")) {
                        m_activeNumber = changed["Number"].toString();
                        emit incomingCall(m_activeNumber);
                        emit activeNumberChanged(m_activeNumber);
                    }
                    break;
                case 4:
                    m_callState = "active";
                    break;
                case 7:
                    m_callState = "idle";
                    m_activeNumber.clear();
                    emit activeNumberChanged(m_activeNumber);
                    break;
                default:
                    m_callState = "unknown";
            }
            
            emit callStateChanged(m_callState);
        }
    }
}

void TelephonyService::checkModemStatus()
{
#ifndef Q_OS_MACOS
    // Periodically check if modem became available
    if (!m_hasModem) {
        connectToModemManager();
    }
#endif
}

QString TelephonyService::extractNumberFromPath(const QString& path)
{
    // Extract phone number from D-Bus object path
    QStringList parts = path.split('/');
    if (!parts.isEmpty()) {
        return parts.last();
    }
    return QString();
}

#ifdef Q_OS_MACOS
void TelephonyService::handleStubDial(const QString& number)
{
    qDebug() << "[TelephonyService] STUB: Would dial" << number;
    m_activeNumber = number;
    m_callState = "dialing";
    emit callStateChanged(m_callState);
    emit activeNumberChanged(m_activeNumber);
    
    // Simulate call connecting after 2 seconds
    QTimer::singleShot(2000, this, [this]() {
        m_callState = "active";
        emit callStateChanged(m_callState);
    });
}
#endif

