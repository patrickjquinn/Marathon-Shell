#include "powermanagercpp.h"
#include <QDebug>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusError>

PowerManagerCpp::PowerManagerCpp(QObject* parent)
    : QObject(parent)
    , m_upowerInterface(nullptr)
    , m_logindInterface(nullptr)
    , m_batteryLevel(75)
    , m_isCharging(false)
    , m_isPowerSaveMode(false)
    , m_estimatedBatteryTime(-1)
    , m_hasUPower(false)
    , m_hasLogind(false)
{
    qDebug() << "[PowerManagerCpp] Initializing";
    
    // Try to connect to UPower D-Bus
    m_upowerInterface = new QDBusInterface(
        "org.freedesktop.UPower",
        "/org/freedesktop/UPower",
        "org.freedesktop.UPower",
        QDBusConnection::systemBus(),
        this
    );
    
    if (m_upowerInterface->isValid()) {
        m_hasUPower = true;
        qDebug() << "[PowerManagerCpp] Connected to UPower D-Bus";
        setupDBusConnections();
        queryBatteryState();
    } else {
        qDebug() << "[PowerManagerCpp] UPower D-Bus not available:" << m_upowerInterface->lastError().message();
        qDebug() << "[PowerManagerCpp] Using simulated battery";
    }
    
    // Try to connect to systemd-logind
    m_logindInterface = new QDBusInterface(
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        QDBusConnection::systemBus(),
        this
    );
    
    if (m_logindInterface->isValid()) {
        m_hasLogind = true;
        qDebug() << "[PowerManagerCpp] Connected to systemd-logind D-Bus";
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind D-Bus not available:" << m_logindInterface->lastError().message();
    }
    
    // Setup battery monitor
    m_batteryMonitor = new QTimer(this);
    m_batteryMonitor->setInterval(30000); // Update every 30 seconds
    connect(m_batteryMonitor, &QTimer::timeout, this, &PowerManagerCpp::queryBatteryState);
    m_batteryMonitor->start();
}

PowerManagerCpp::~PowerManagerCpp()
{
    if (m_upowerInterface) delete m_upowerInterface;
    if (m_logindInterface) delete m_logindInterface;
}

void PowerManagerCpp::setupDBusConnections()
{
    if (!m_hasUPower) return;
    
    // Connect to UPower device changes
    QDBusConnection::systemBus().connect(
        "org.freedesktop.UPower",
        "/org/freedesktop/UPower",
        "org.freedesktop.UPower",
        "DeviceChanged",
        this,
        SLOT(queryBatteryState())
    );
}

void PowerManagerCpp::queryBatteryState()
{
    if (m_hasUPower) {
        // Query battery devices from UPower
        QDBusReply<QList<QDBusObjectPath>> devices = m_upowerInterface->call("EnumerateDevices");
        if (devices.isValid()) {
            // Find battery device and query its properties
            // This is simplified - real implementation would iterate devices
            qDebug() << "[PowerManagerCpp] Found" << devices.value().count() << "power devices";
        }
    } else {
        // Simulate battery drain/charge
        simulateBatteryUpdate();
    }
}

void PowerManagerCpp::simulateBatteryUpdate()
{
    // Simple simulation for testing
    if (m_isCharging) {
        if (m_batteryLevel < 100) {
            m_batteryLevel = qMin(100, m_batteryLevel + 1);
            emit batteryLevelChanged();
        }
    } else {
        if (m_batteryLevel > 0) {
            m_batteryLevel = qMax(0, m_batteryLevel - 1);
            emit batteryLevelChanged();
            
            if (m_batteryLevel <= 5) {
                emit criticalBattery();
            }
        }
    }
}

void PowerManagerCpp::suspend()
{
    qDebug() << "[PowerManagerCpp] Suspending system";
    
    if (m_hasLogind) {
        QDBusReply<void> reply = m_logindInterface->call("Suspend", true);
        if (!reply.isValid()) {
            qDebug() << "[PowerManagerCpp] Failed to suspend:" << reply.error().message();
            emit powerError("Failed to suspend system");
        }
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind not available, cannot suspend";
        emit powerError("Suspend not available");
    }
}

void PowerManagerCpp::hibernate()
{
    qDebug() << "[PowerManagerCpp] Hibernating system";
    
    if (m_hasLogind) {
        QDBusReply<void> reply = m_logindInterface->call("Hibernate", true);
        if (!reply.isValid()) {
            qDebug() << "[PowerManagerCpp] Failed to hibernate:" << reply.error().message();
            emit powerError("Failed to hibernate system");
        }
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind not available, cannot hibernate";
        emit powerError("Hibernate not available");
    }
}

void PowerManagerCpp::shutdown()
{
    qDebug() << "[PowerManagerCpp] Shutting down system";
    
    if (m_hasLogind) {
        QDBusReply<void> reply = m_logindInterface->call("PowerOff", true);
        if (!reply.isValid()) {
            qDebug() << "[PowerManagerCpp] Failed to shutdown:" << reply.error().message();
            emit powerError("Failed to shutdown system");
        }
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind not available, cannot shutdown";
        emit powerError("Shutdown not available");
    }
}

void PowerManagerCpp::restart()
{
    qDebug() << "[PowerManagerCpp] Restarting system";
    
    if (m_hasLogind) {
        QDBusReply<void> reply = m_logindInterface->call("Reboot", true);
        if (!reply.isValid()) {
            qDebug() << "[PowerManagerCpp] Failed to restart:" << reply.error().message();
            emit powerError("Failed to restart system");
        }
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind not available, cannot restart";
        emit powerError("Restart not available");
    }
}

void PowerManagerCpp::setPowerSaveMode(bool enabled)
{
    qDebug() << "[PowerManagerCpp] Power save mode:" << enabled;
    m_isPowerSaveMode = enabled;
    emit isPowerSaveModeChanged();
}

void PowerManagerCpp::refreshBatteryInfo()
{
    qDebug() << "[PowerManagerCpp] Refreshing battery info";
    queryBatteryState();
}

