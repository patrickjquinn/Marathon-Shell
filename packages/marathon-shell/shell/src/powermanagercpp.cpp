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
        qInfo() << "[PowerManagerCpp] Connected to UPower D-Bus";
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
    if (m_hasUPower) {
        // Connect to UPower device changes
        bool connected = QDBusConnection::systemBus().connect(
            "org.freedesktop.UPower",
            "/org/freedesktop/UPower",
            "org.freedesktop.UPower",
            "DeviceChanged",
            this,
            SLOT(queryBatteryState())
        );
        
        if (!connected) {
            qDebug() << "[PowerManagerCpp] UPower DeviceChanged signal connection failed (expected - using polling instead)";
        } else {
            qInfo() << "[PowerManagerCpp] Connected to UPower DeviceChanged signal";
        }
    }
    
    // Connect to PrepareForSleep signal for lock-before-suspend
    if (m_hasLogind) {
        bool sleepConnected = QDBusConnection::systemBus().connect(
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "PrepareForSleep",
            this,
            SLOT(onPrepareForSleep(bool))
        );
        
        if (sleepConnected) {
            qInfo() << "[PowerManagerCpp] Connected to PrepareForSleep signal";
        } else {
            qDebug() << "[PowerManagerCpp] PrepareForSleep signal connection failed";
        }
    }
}

void PowerManagerCpp::queryBatteryState()
{
    if (!m_hasUPower) {
        simulateBatteryUpdate();
        return;
    }
    
    // Query battery devices from UPower
    QDBusReply<QList<QDBusObjectPath>> devicesReply = m_upowerInterface->call("EnumerateDevices");
    if (!devicesReply.isValid()) {
        qDebug() << "[PowerManagerCpp] Failed to enumerate UPower devices";
        return;
    }
    
    QList<QDBusObjectPath> devices = devicesReply.value();
    qInfo() << "[PowerManagerCpp] Found" << devices.count() << "power devices";
    
    // Handle VM/no-battery scenario
    if (devices.isEmpty()) {
        qInfo() << "[PowerManagerCpp] No power devices found (VM/virtualized environment)";
        qInfo() << "[PowerManagerCpp] Set to 100% (mains power, no battery hardware)";
        if (m_batteryLevel != 100 || !m_isCharging) {
            m_batteryLevel = 100;
            m_isCharging = true;
            emit batteryLevelChanged();
            emit isChargingChanged();
        }
        return;
    }
    
    // Find the first battery device
    for (const QDBusObjectPath& devicePath : devices) {
        QDBusInterface device(
            "org.freedesktop.UPower",
            devicePath.path(),
            "org.freedesktop.UPower.Device",
            QDBusConnection::systemBus()
        );
        
        if (!device.isValid()) continue;
        
        // Check if it's a battery (Type == 2)
        uint type = device.property("Type").toUInt();
        if (type != 2) continue; // Not a battery
        
        // Get battery percentage
        double percentage = device.property("Percentage").toDouble();
        int newLevel = qRound(percentage);
        
        // Get charging state
        uint state = device.property("State").toUInt();
        // 0=Unknown, 1=Charging, 2=Discharging, 3=Empty, 4=Fully charged, 5=Pending charge, 6=Pending discharge
        bool charging = (state == 1 || state == 5);
        
        // Check if on AC power
        bool onBattery = device.property("IsPresent").toBool();
        if (!onBattery) {
            newLevel = 100;
            charging = true;
        }
        
        // Update state if changed
        bool changed = false;
        if (m_batteryLevel != newLevel) {
            m_batteryLevel = newLevel;
            emit batteryLevelChanged();
            changed = true;
            
            // Check for critical battery
            if (m_batteryLevel <= 5 && !charging) {
                emit criticalBattery();
            }
        }
        
        if (m_isCharging != charging) {
            m_isCharging = charging;
            emit isChargingChanged();
            changed = true;
        }
        
        if (changed) {
            qInfo() << "[PowerManagerCpp] Battery:" << m_batteryLevel << "% Charging:" << m_isCharging;
        }
        
        break; // Use first battery found
    }
}

void PowerManagerCpp::onPrepareForSleep(bool beforeSleep)
{
    if (beforeSleep) {
        qInfo() << "[PowerManagerCpp] System about to sleep - emitting aboutToSleep signal";
        emit aboutToSleep();
    } else {
        qInfo() << "[PowerManagerCpp] System resumed from sleep - emitting resumedFromSleep signal";
        emit resumedFromSleep();
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

