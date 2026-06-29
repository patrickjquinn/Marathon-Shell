#include "telephonyservice.h"
#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
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

    m_reconnectTimer->setInterval(10000);
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, &TelephonyService::checkModemStatus);
    if (QDBusConnection::systemBus().isConnected()) {
        m_reconnectTimer->start();
    }

    qInfo() << "[TelephonyService] Initialized";
}

TelephonyService::~TelephonyService() {

    delete m_voiceCall;

    // m_modemManager is parented to this; Qt will delete it
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

    auto *voiceInterface = new QDBusInterface("org.freedesktop.ModemManager1", m_modemPath,
                                              "org.freedesktop.ModemManager1.Modem.Voice",
                                              QDBusConnection::systemBus(), this);

    if (!voiceInterface->isValid()) {
        qWarning() << "[TelephonyService] Voice interface not available:"
                   << voiceInterface->lastError().message();
        emit callFailed("Voice interface not available");
        voiceInterface->deleteLater();
        return;
    }

    QVariantMap properties;
    properties["number"] = number;

    // Async CreateCall + Start. The synchronous version blocked the GUI thread
    // for up to 25 s while ModemManager negotiated the call setup, leaving the
    // dialer frozen on the dial pad with no in-call UI -- and on timeout it
    // emitted a spurious "Failed to start call" even when the modem had placed
    // the call successfully (the other phone rang fine, this end never got the
    // reply in time).
    //
    // Move to optimistic state: emit "dialing" immediately so the QML
    // ActiveCallPage transitions on the next frame, then drive real state from
    // ModemManager's CallAdded + Call.PropertiesChanged signals (handled in
    // monitorIncomingCalls / setupCallMonitoring).
    m_activeNumber = number;
    m_callState    = "dialing";
    emit callStateChanged("dialing");
    emit activeNumberChanged(number);
    qInfo() << "[TelephonyService] Call dialing (async):" << number;

    QDBusPendingCall pending =
        voiceInterface->asyncCall("CreateCall", QVariant::fromValue(properties));
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, voiceInterface, number](QDBusPendingCallWatcher *w) {
                QDBusPendingReply<QDBusObjectPath> r = *w;
                w->deleteLater();
                voiceInterface->deleteLater();
                if (r.isError()) {
                    qWarning() << "[TelephonyService] CreateCall failed:" << r.error().message();
                    // Don't roll back state -- the call may still go through via
                    // CallAdded. Only bail the UI back to idle if we get no
                    // CallAdded within the watchdog window (handled elsewhere).
                    emit callFailed("CreateCall: " + r.error().message());
                    return;
                }
                const QString callPath = r.value().path();
                qDebug() << "[TelephonyService] CreateCall returned:" << callPath;

                if (m_activeCallPath.isEmpty()) {
                    m_activeCallPath = callPath;
                    setupCallMonitoring(callPath);
                    acquireCallInhibit();
                }

                auto *callIface = new QDBusInterface("org.freedesktop.ModemManager1", callPath,
                                                     "org.freedesktop.ModemManager1.Call",
                                                     QDBusConnection::systemBus(), this);
                if (!callIface->isValid()) {
                    qWarning() << "[TelephonyService] Call iface invalid for" << callPath;
                    emit callFailed("Call interface not available");
                    callIface->deleteLater();
                    return;
                }
                QDBusPendingCall startPending = callIface->asyncCall("Start");
                auto            *startWatcher = new QDBusPendingCallWatcher(startPending, this);
                connect(startWatcher, &QDBusPendingCallWatcher::finished, this,
                        [callIface](QDBusPendingCallWatcher *sw) {
                            QDBusPendingReply<> sr = *sw;
                            sw->deleteLater();
                            callIface->deleteLater();
                            if (sr.isError())
                                qWarning() << "[TelephonyService] Call.Start failed:"
                                           << sr.error().message();
                            else
                                qInfo() << "[TelephonyService] Call.Start returned ok";
                        });
                Q_UNUSED(number);
            });
}

void TelephonyService::dialEmergency(const QString &number) {
    // Audit the attempt regardless of outcome -- emergency dials must always
    // appear in the journal even when the modem rejects them. This is logged
    // BEFORE the dial path so the line lands even if the dial blocks/crashes.
    QString op;
    if (m_modemManager && !m_modemPath.isEmpty()) {
        QDBusInterface modem3gpp("org.freedesktop.ModemManager1", m_modemPath,
                                 "org.freedesktop.ModemManager1.Modem.Modem3gpp",
                                 QDBusConnection::systemBus());
        if (modem3gpp.isValid())
            op = modem3gpp.property("OperatorName").toString();
    }
    qWarning().noquote() << QString("[SECURITY] Emergency dial: number=%1 modem=%2 operator=%3")
                                .arg(number, m_modemPath, op.isEmpty() ? QStringLiteral("?") : op);
    dial(number);
}

void TelephonyService::answer() {
    qInfo() << "[TelephonyService] Answering call";

    if (m_activeCallPath.isEmpty()) {
        qWarning() << "[TelephonyService] No active call to answer";
        return;
    }

    if (m_activeCallPath.contains("simulate")) {
        m_callState = "active";
        emit callStateChanged("active");
        qInfo() << "[TelephonyService] [SIMULATION]Call answered";
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

    qInfo() << "[TelephonyService] Call answered";
}

void TelephonyService::hangup() {
    qInfo() << "[TelephonyService] Hanging up call";

    if (m_activeCallPath.isEmpty()) {
        qWarning() << "[TelephonyService] No active call to hang up";
        return;
    }

    if (m_activeCallPath.contains("simulate")) {
        m_callState = "idle";
        m_activeCallPath.clear();
        m_activeNumber.clear();

        emit callStateChanged("idle");
        emit activeNumberChanged("");

        qInfo() << "[TelephonyService] [SIMULATION]Call hung up";
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

    qInfo() << "[TelephonyService] Call hung up";
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

    qDebug() << "[TelephonyService]DTMF sent:" << digit;
}

void TelephonyService::simulateIncomingCall(const QString &number) {
    qInfo() << "[TelephonyService] [SIMULATION] Simulating incoming call from:" << number;

    m_activeNumber   = number;
    m_callState      = "incoming";
    m_activeCallPath = "/org/freedesktop/ModemManager1/Call/simulate";

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

    qInfo() << "[TelephonyService] Connected to ModemManager";

    setupDBusConnections();
    checkModemStatus();
}

void TelephonyService::setupDBusConnections() {

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

    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        QString              path       = it.key().path();
        const InterfaceList &interfaces = it.value();

        if (interfaces.contains("org.freedesktop.ModemManager1.Modem.Voice")) {
            if (m_modemPath != path) {
                m_modemPath = path;
                qInfo() << "[TelephonyService] Modem with Voice capability found:" << path;
            }

            if (!m_hasModem) {
                m_hasModem = true;
                emit modemChanged(true);
            }

            monitorIncomingCalls();
            return;
        }
    }

    if (m_hasModem) {
        m_hasModem = false;
        m_modemPath.clear();
        emit modemChanged(false);
        qDebug() << "[TelephonyService] No modem with Voice capability available";
    }
}

void TelephonyService::setupCallMonitoring(const QString &callPath) {

    QDBusConnection::systemBus().connect(
        "org.freedesktop.ModemManager1", callPath, "org.freedesktop.DBus.Properties",
        "PropertiesChanged", this,
        SLOT(onModemManagerPropertiesChanged(QString, QVariantMap, QStringList)));
}

void TelephonyService::monitorIncomingCalls() {
    if (m_modemPath.isEmpty())
        return;

    QDBusConnection::systemBus().connect("org.freedesktop.ModemManager1", m_modemPath,
                                         "org.freedesktop.ModemManager1.Modem.Voice", "CallAdded",
                                         this, SLOT(onCallAdded(QDBusObjectPath)));
}

void TelephonyService::onCallAdded(const QDBusObjectPath &callPath) {
    QString path = callPath.path();
    qInfo() << "[TelephonyService] New call detected:" << path;

    QDBusInterface callInterface("org.freedesktop.ModemManager1", path,
                                 "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());

    if (!callInterface.isValid()) {
        qWarning() << "[TelephonyService] Cannot get call properties";
        return;
    }

    QDBusReply<QVariant> directionReply =
        callInterface.call("Get", "org.freedesktop.ModemManager1.Call", "Direction");
    if (!directionReply.isValid())
        return;

    const uint           direction = directionReply.value().toUInt();
    QDBusReply<QVariant> numberReply =
        callInterface.call("Get", "org.freedesktop.ModemManager1.Call", "Number");
    QString number =
        numberReply.isValid() ? numberReply.value().toString() : QStringLiteral("Unknown");

    if (direction == 1) {
        // MM_CALL_DIRECTION_INCOMING
        m_activeCallPath = path;
        m_activeNumber   = number;
        m_callState      = "incoming";

        setupCallMonitoring(path);
        acquireCallInhibit();

        emit incomingCall(number);
        emit callStateChanged("incoming");
        emit activeNumberChanged(number);

        qInfo() << "[TelephonyService] Incoming call from:" << number;
        return;
    }

    // direction == 2 (MM_CALL_DIRECTION_OUTGOING). Without this branch, the
    // outgoing dial path used to depend on the synchronous CreateCall reply to
    // know the call path -- if the reply was delayed (very common: MM serialises
    // call setup over modem AT/QMI and easily exceeds Qt's 25 s DBus timeout)
    // we never set m_activeCallPath, never subscribed to PropertiesChanged, and
    // the UI stayed frozen on "dialing" forever. Now we adopt the call here
    // whenever CallAdded fires for an outgoing call we don't already track.
    if (m_activeCallPath.isEmpty() || m_activeCallPath == path) {
        m_activeCallPath = path;
        if (m_activeNumber.isEmpty()) {
            m_activeNumber = number;
            emit activeNumberChanged(number);
        }
        setupCallMonitoring(path);
        acquireCallInhibit();
        qInfo() << "[TelephonyService] Outgoing call adopted:" << path << "to" << m_activeNumber;
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

                // Acquire/release the suspend block inhibit on call edges.
                // Pattern lifted from Plasma-Dialer's call-manager.cpp.
                if (newState == "active" || newState == "dialing" || newState == "incoming")
                    acquireCallInhibit();
                else if (newState == "idle" || newState == "terminated")
                    releaseCallInhibit();

                if (newState == "idle" || newState == "terminated") {
                    m_activeCallPath.clear();
                    m_activeNumber.clear();
                    emit activeNumberChanged("");
                }
            }
        }
    }
}

void TelephonyService::acquireCallInhibit() {
    if (m_callInhibitFd.isValid())
        return; // Already held -- nothing to do.
    QDBusInterface logind("org.freedesktop.login1", "/org/freedesktop/login1",
                          "org.freedesktop.login1.Manager", QDBusConnection::systemBus());
    if (!logind.isValid()) {
        qDebug() << "[TelephonyService] logind unavailable, skipping call inhibit";
        return;
    }
    QDBusReply<QDBusUnixFileDescriptor> reply = logind.call(
        "Inhibit", "sleep", "marathon-shell", "Active call inhibits system suspend", "block");
    if (reply.isValid()) {
        m_callInhibitFd = reply.value();
        qInfo() << "[TelephonyService] Acquired call sleep-block inhibit";
    } else {
        qWarning() << "[TelephonyService] Failed to acquire call inhibit:"
                   << reply.error().message();
    }
}

void TelephonyService::releaseCallInhibit() {
    if (m_callInhibitFd.isValid()) {
        m_callInhibitFd = QDBusUnixFileDescriptor();
        qInfo() << "[TelephonyService] Released call sleep-block inhibit";
    }
}

QString TelephonyService::callStateFromModemManager(uint mmState) {

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

    Q_UNUSED(path)
    return "Unknown";
}
