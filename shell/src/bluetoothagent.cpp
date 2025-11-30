#include "bluetoothagent.h"
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusError>
#include <QDebug>
#include <QEventLoop>

BluetoothAgent::BluetoothAgent(QObject *parent)
    : QObject(parent)
    , m_agentPath("/org/marathon/bluetooth/agent")
    , m_registered(false)
    , m_waitingForResponse(false) {
    qDebug() << "[BluetoothAgent] Initialized";
}

BluetoothAgent::~BluetoothAgent() {
    if (m_registered) {
        unregisterAgent();
    }
}

bool BluetoothAgent::registerAgent() {
    qDebug() << "[BluetoothAgent] Registering agent at" << m_agentPath;

    QDBusConnection bus = QDBusConnection::systemBus();

    // Register agent object on D-Bus
    if (!bus.registerObject(m_agentPath, this, QDBusConnection::ExportAllSlots)) {
        qWarning() << "[BluetoothAgent] Failed to register object:" << bus.lastError().message();
        return false;
    }

    // Register agent with BlueZ AgentManager
    QDBusInterface agentManager("org.bluez", "/org/bluez", "org.bluez.AgentManager1", bus);

    if (!agentManager.isValid()) {
        // Only log as debug - expected when no bluetooth hardware is present
        qDebug() << "[BluetoothAgent] BlueZ AgentManager not available:"
                 << agentManager.lastError().message();
        qDebug() << "[BluetoothAgent] This is expected when no bluetooth hardware is present";
        bus.unregisterObject(m_agentPath);
        return false;
    }

    // Register agent with "KeyboardDisplay" capability - supports all pairing methods
    QDBusReply<void> reply =
        agentManager.call("RegisterAgent", QVariant::fromValue(QDBusObjectPath(m_agentPath)),
                          QString("KeyboardDisplay"));

    if (!reply.isValid()) {
        qWarning() << "[BluetoothAgent] Failed to register with AgentManager:"
                   << reply.error().message();
        bus.unregisterObject(m_agentPath);
        return false;
    }

    // Request to be the default agent
    QDBusReply<void> defaultReply =
        agentManager.call("RequestDefaultAgent", QVariant::fromValue(QDBusObjectPath(m_agentPath)));

    if (!defaultReply.isValid()) {
        qWarning() << "[BluetoothAgent] Failed to set as default agent:"
                   << defaultReply.error().message();
        // This is not critical - continue anyway
    }

    m_registered = true;
    qInfo() << "[BluetoothAgent] ✓ Successfully registered as Bluetooth pairing agent";
    return true;
}

void BluetoothAgent::unregisterAgent() {
    if (!m_registered)
        return;

    qDebug() << "[BluetoothAgent] Unregistering agent";

    QDBusConnection bus = QDBusConnection::systemBus();

    QDBusInterface  agentManager("org.bluez", "/org/bluez", "org.bluez.AgentManager1", bus);
    if (agentManager.isValid()) {
        agentManager.call("UnregisterAgent", QVariant::fromValue(QDBusObjectPath(m_agentPath)));
    }

    bus.unregisterObject(m_agentPath);
    m_registered = false;

    qInfo() << "[BluetoothAgent] Unregistered";
}

void BluetoothAgent::Release() {
    qInfo() << "[BluetoothAgent] Release() called - agent being released by BlueZ";
    m_registered = false;
}

QString BluetoothAgent::RequestPinCode(const QDBusObjectPath &device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] PIN code requested for device:" << deviceName << "(" << devicePath
            << ")";

    m_pendingDevicePath  = devicePath;
    m_pendingMessage     = message();
    m_waitingForResponse = true;
    setDelayedReply(true);

    emit pairingPinCodeRequested(devicePath, deviceName);

    // Response will be sent via providePinCode()
    return QString(); // Won't be used due to delayed reply
}

quint32 BluetoothAgent::RequestPasskey(const QDBusObjectPath &device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Passkey requested for device:" << deviceName << "(" << devicePath
            << ")";

    m_pendingDevicePath  = devicePath;
    m_pendingMessage     = message();
    m_waitingForResponse = true;
    setDelayedReply(true);

    emit pairingPasskeyRequested(devicePath, deviceName);

    // Response will be sent via providePasskey()
    return 0; // Won't be used due to delayed reply
}

void BluetoothAgent::DisplayPinCode(const QDBusObjectPath &device, const QString &pincode) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Display PIN code for device:" << deviceName << "PIN:" << pincode;

    emit pairingPasskeyDisplay(devicePath, deviceName, pincode.toUInt());
}

void BluetoothAgent::DisplayPasskey(const QDBusObjectPath &device, quint32 passkey,
                                    quint16 entered) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Display passkey for device:" << deviceName << "Passkey:" << passkey
            << "Entered:" << entered;

    emit pairingPasskeyDisplay(devicePath, deviceName, passkey);
}

void BluetoothAgent::RequestConfirmation(const QDBusObjectPath &device, quint32 passkey) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Confirmation requested for device:" << deviceName
            << "Passkey:" << passkey;

    m_pendingDevicePath  = devicePath;
    m_pendingMessage     = message();
    m_waitingForResponse = true;
    setDelayedReply(true);

    emit pairingConfirmationRequested(devicePath, deviceName, passkey);

    // Response will be sent via confirmPairing()
}

void BluetoothAgent::RequestAuthorization(const QDBusObjectPath &device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Authorization requested for device:" << deviceName;

    m_pendingDevicePath  = devicePath;
    m_pendingMessage     = message();
    m_waitingForResponse = true;
    setDelayedReply(true);

    emit pairingAuthorizationRequested(devicePath, deviceName);

    // Response will be sent via authorizeConnection()
}

void BluetoothAgent::AuthorizeService(const QDBusObjectPath &device, const QString &uuid) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qInfo() << "[BluetoothAgent] Service authorization requested for device:" << deviceName
            << "UUID:" << uuid;

    // Auto-authorize all services for now
    // Could be made configurable in the future
}

void BluetoothAgent::Cancel() {
    qInfo() << "[BluetoothAgent] Pairing cancelled by remote device or timeout";

    m_waitingForResponse = false;
    m_pendingDevicePath.clear();

    emit pairingCancelled();
}

void BluetoothAgent::providePinCode(const QString &pinCode) {
    if (!m_waitingForResponse) {
        qWarning() << "[BluetoothAgent] providePinCode() called but not waiting for response";
        return;
    }

    qDebug() << "[BluetoothAgent] Providing PIN code:" << pinCode;

    QDBusMessage reply = m_pendingMessage.createReply();
    reply << pinCode;
    QDBusConnection::systemBus().send(reply);

    m_waitingForResponse = false;
    emit pairingCompleted(m_pendingDevicePath, true);
}

void BluetoothAgent::providePasskey(quint32 passkey) {
    if (!m_waitingForResponse) {
        qWarning() << "[BluetoothAgent] providePasskey() called but not waiting for response";
        return;
    }

    qDebug() << "[BluetoothAgent] Providing passkey:" << passkey;

    QDBusMessage reply = m_pendingMessage.createReply();
    reply << passkey;
    QDBusConnection::systemBus().send(reply);

    m_waitingForResponse = false;
    emit pairingCompleted(m_pendingDevicePath, true);
}

void BluetoothAgent::confirmPairing(bool confirmed) {
    if (!m_waitingForResponse) {
        qWarning() << "[BluetoothAgent] confirmPairing() called but not waiting for response";
        return;
    }

    qDebug() << "[BluetoothAgent] Pairing" << (confirmed ? "confirmed" : "rejected");

    if (confirmed) {
        QDBusMessage reply = m_pendingMessage.createReply();
        QDBusConnection::systemBus().send(reply);
        emit pairingCompleted(m_pendingDevicePath, true);
    } else {
        QDBusMessage error = m_pendingMessage.createErrorReply("org.bluez.Error.Rejected",
                                                               "Pairing rejected by user");
        QDBusConnection::systemBus().send(error);
        emit pairingCompleted(m_pendingDevicePath, false);
    }

    m_waitingForResponse = false;
}

void BluetoothAgent::authorizeConnection(bool authorized) {
    if (!m_waitingForResponse) {
        qWarning() << "[BluetoothAgent] authorizeConnection() called but not waiting for response";
        return;
    }

    qDebug() << "[BluetoothAgent] Connection" << (authorized ? "authorized" : "rejected");

    if (authorized) {
        QDBusMessage reply = m_pendingMessage.createReply();
        QDBusConnection::systemBus().send(reply);
        emit pairingCompleted(m_pendingDevicePath, true);
    } else {
        QDBusMessage error = m_pendingMessage.createErrorReply("org.bluez.Error.Rejected",
                                                               "Connection rejected by user");
        QDBusConnection::systemBus().send(error);
        emit pairingCompleted(m_pendingDevicePath, false);
    }

    m_waitingForResponse = false;
}

QString BluetoothAgent::getDeviceName(const QString &devicePath) {
    QDBusInterface device("org.bluez", devicePath, "org.freedesktop.DBus.Properties",
                          QDBusConnection::systemBus());

    if (!device.isValid()) {
        return "Unknown Device";
    }

    QDBusReply<QVariant> reply = device.call("Get", "org.bluez.Device1", "Alias");
    if (reply.isValid()) {
        return reply.value().toString();
    }

    return "Unknown Device";
}

void BluetoothAgent::sendDBusError(const QString &errorName, const QString &errorMessage) {
    if (m_waitingForResponse) {
        QDBusMessage error = m_pendingMessage.createErrorReply(errorName, errorMessage);
        QDBusConnection::systemBus().send(error);
        m_waitingForResponse = false;
    }
}
