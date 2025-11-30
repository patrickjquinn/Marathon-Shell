#include "powermanagercpp.h"
#include <QDebug>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusPendingCallWatcher>
#include <QDateTime>
#include <QFile>
#include <QProcess>

PowerManagerCpp::PowerManagerCpp(QObject *parent)
    : QObject(parent)
    , m_upowerInterface(nullptr)
    , m_logindInterface(nullptr)
    , m_batteryLevel(75)
    , m_isCharging(false)
    , m_isPluggedIn(false)
    , m_isPowerSaveMode(false)
    , m_estimatedBatteryTime(-1)
    , m_hasUPower(false)
    , m_hasLogind(false)
    , m_currentProfile(Balanced)
    , m_powerProfileString("balanced")
    , m_powerProfilesSupported(false)
    , m_idleTimeout(300)
    , m_autoSuspendEnabled(true)
    , m_isIdle(false)
    , m_lastActivityTime(QDateTime::currentMSecsSinceEpoch())
    , m_systemSuspended(false)
    , m_wakelockSupported(false)
    , m_fallbackMode("none")
    , m_rtcAlarmSupported(false) {
    qCritical() << "[PowerManagerCpp] Initializing PowerManagerCpp Service";

    // Try to connect to UPower D-Bus
    m_upowerInterface =
        new QDBusInterface("org.freedesktop.UPower", "/org/freedesktop/UPower",
                           "org.freedesktop.UPower", QDBusConnection::systemBus(), this);

    if (m_upowerInterface->isValid()) {
        m_hasUPower = true;
        qInfo() << "[PowerManagerCpp] Connected to UPower D-Bus";
        setupDBusConnections();
        setupDisplayDevice();
    } else {
        qDebug() << "[PowerManagerCpp] UPower D-Bus not available:"
                 << m_upowerInterface->lastError().message();
        qDebug() << "[PowerManagerCpp] Using simulated battery";
    }

    // Try to connect to systemd-logind
    m_logindInterface =
        new QDBusInterface("org.freedesktop.login1", "/org/freedesktop/login1",
                           "org.freedesktop.login1.Manager", QDBusConnection::systemBus(), this);

    if (m_logindInterface->isValid()) {
        m_hasLogind = true;
        qDebug() << "[PowerManagerCpp] Connected to systemd-logind D-Bus";
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind D-Bus not available:"
                 << m_logindInterface->lastError().message();
    }

    // Check CPU governor support
    checkCPUGovernorSupport();

    // Check wakelock and RTC alarm support
    checkWakelockSupport();
    checkRtcAlarmSupport();

    // Setup idle timer
    m_idleTimer = new QTimer(this);
    m_idleTimer->setInterval(10000); // Check idle every 10 seconds
    connect(m_idleTimer, &QTimer::timeout, this, &PowerManagerCpp::checkIdleState);
    m_idleTimer->start();

    qInfo() << "[PowerManagerCpp] Power profiles supported:" << m_powerProfilesSupported;
    qInfo() << "[PowerManagerCpp] Current power profile:" << m_powerProfileString;
    qInfo() << "[PowerManagerCpp] Wakelock support:"
            << (m_wakelockSupported ? "enabled" : "disabled (will use inhibitors)");
    qInfo() << "[PowerManagerCpp] RTC alarm support:"
            << (m_rtcAlarmSupported ? "enabled" : "disabled");
}

PowerManagerCpp::~PowerManagerCpp() {
    // Clean up all wakelocks before shutdown
    cleanupWakelocks();
    releaseInhibitor();

    if (m_upowerInterface)
        delete m_upowerInterface;
    if (m_displayDeviceInterface)
        delete m_displayDeviceInterface;
    if (m_logindInterface)
        delete m_logindInterface;
}

void PowerManagerCpp::setupDBusConnections() {
    // Connect to PrepareForSleep signal for lock-before-suspend
    if (m_hasLogind) {
        QDBusConnection::systemBus().connect("org.freedesktop.login1", "/org/freedesktop/login1",
                                             "org.freedesktop.login1.Manager", "PrepareForSleep",
                                             this, SLOT(onPrepareForSleep(bool)));
    }
}

void PowerManagerCpp::setupDisplayDevice() {
    m_displayDeviceInterface = new QDBusInterface(
        "org.freedesktop.UPower", "/org/freedesktop/UPower/devices/DisplayDevice",
        "org.freedesktop.UPower.Device", QDBusConnection::systemBus(), this);

    if (m_displayDeviceInterface->isValid()) {
        qInfo() << "[PowerManagerCpp] Connected to DisplayDevice";

        // Connect to property changes
        QDBusConnection::systemBus().connect("org.freedesktop.UPower",
                                             "/org/freedesktop/UPower/devices/DisplayDevice",
                                             "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                             this, SLOT(updateAggregateState()));

        // Initial update
        updateAggregateState();
    } else {
        qWarning() << "[PowerManagerCpp] DisplayDevice not available:"
                   << m_displayDeviceInterface->lastError().message();
    }
}

void PowerManagerCpp::updateAggregateState() {
    if (!m_displayDeviceInterface || !m_displayDeviceInterface->isValid()) {
        // VM/No Battery Fallback
        if (m_batteryLevel != 100) {
            m_batteryLevel = 100;
            m_isCharging =
                false; // "Fully Charged" usually means not charging, but for VM we can say plugged in.
            m_isPluggedIn = true;
            emit batteryLevelChanged();
            emit isChargingChanged();
            emit isPluggedInChanged();
        }
        return;
    }

    int  newLevel = qRound(m_displayDeviceInterface->property("Percentage").toDouble());
    uint state    = m_displayDeviceInterface->property("State").toUInt();
    uint type     = m_displayDeviceInterface->property("Type").toUInt();

    bool newCharging  = (state == 1 || state == 5); // 1=Charging, 5=Pending Charge
    bool newPluggedIn = (state == 1 || state == 4 || state == 5 || type == 1); // 4=Fully Charged

    if (m_batteryLevel != newLevel) {
        qInfo() << "[PowerManagerCpp] Battery Level Changed:" << m_batteryLevel << "->" << newLevel;
        m_batteryLevel = newLevel;
        emit batteryLevelChanged();

        if (m_batteryLevel <= 5) {
            emit criticalBattery();
        }
    }

    if (m_isCharging != newCharging) {
        m_isCharging = newCharging;
        emit isChargingChanged();
    }

    if (m_isPluggedIn != newPluggedIn) {
        m_isPluggedIn = newPluggedIn;
        emit isPluggedInChanged();
    }

    qDebug() << "[PowerManagerCpp] State Updated - Level:" << m_batteryLevel
             << "% Charging:" << m_isCharging << "PluggedIn:" << m_isPluggedIn;
}

void PowerManagerCpp::onPrepareForSleep(bool beforeSleep) {
    if (beforeSleep) {
        qInfo() << "[PowerManagerCpp] System preparing for sleep";
        m_systemSuspended = true;
        emit systemSuspendedChanged();
        emit aboutToSleep();
        emit prepareForSuspend();

        // Release inhibitor if we had one (delay inhibitor releases automatically)
        releaseInhibitor();
    } else {
        qInfo() << "[PowerManagerCpp] System resumed from sleep";
        m_systemSuspended = false;
        emit systemSuspendedChanged();
        emit resumedFromSleep();
        emit resumedFromSuspend();

        // Re-acquire wakelocks that were held before suspend
        // (kernel wakelocks persist across suspend, but we re-apply for safety)
        for (auto it = m_activeWakelocks.begin(); it != m_activeWakelocks.end(); ++it) {
            if (it.value()) {
                qDebug() << "[PowerManagerCpp] Re-acquiring wakelock after resume:" << it.key();
                writeToFile("/sys/power/wake_lock", it.key());
            }
        }
    }
}

void PowerManagerCpp::simulateBatteryUpdate() {
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

void PowerManagerCpp::suspend() {
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

void PowerManagerCpp::hibernate() {
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

void PowerManagerCpp::shutdown() {
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

void PowerManagerCpp::restart() {
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

void PowerManagerCpp::setPowerSaveMode(bool enabled) {
    qDebug() << "[PowerManagerCpp] Power save mode:" << enabled;
    m_isPowerSaveMode = enabled;
    emit isPowerSaveModeChanged();
}

void PowerManagerCpp::refreshBatteryInfo() {
    qDebug() << "[PowerManagerCpp] Refreshing battery info";
    if (m_hasUPower) {
        updateAggregateState();
    } else {
        simulateBatteryUpdate();
    }
}

void PowerManagerCpp::setPowerProfile(const QString &profile) {
    qInfo() << "[PowerManagerCpp] Setting power profile to:" << profile;

    PowerProfile newProfile;
    if (profile == "performance") {
        newProfile           = Performance;
        m_powerProfileString = "performance";
    } else if (profile == "power-saver" || profile == "powersave") {
        newProfile           = PowerSaver;
        m_powerProfileString = "power-saver";
    } else {
        newProfile           = Balanced;
        m_powerProfileString = "balanced";
    }

    if (m_currentProfile != newProfile) {
        m_currentProfile = newProfile;
        applyCPUGovernor(newProfile);
        emit powerProfileChanged();
    }
}

void PowerManagerCpp::setIdleTimeout(int seconds) {
    if (m_idleTimeout != seconds) {
        m_idleTimeout = seconds;
        qInfo() << "[PowerManagerCpp] Idle timeout set to:" << seconds << "seconds";
        emit idleTimeoutChanged();
    }
}

void PowerManagerCpp::setAutoSuspendEnabled(bool enabled) {
    if (m_autoSuspendEnabled != enabled) {
        m_autoSuspendEnabled = enabled;
        qInfo() << "[PowerManagerCpp] Auto-suspend:" << (enabled ? "enabled" : "disabled");
        emit autoSuspendEnabledChanged();
    }
}

void PowerManagerCpp::checkIdleState() {
    qint64 currentTime = QDateTime::currentMSecsSinceEpoch();
    qint64 idleTime    = currentTime - m_lastActivityTime;
    bool   nowIdle     = (idleTime / 1000) > m_idleTimeout;

    if (nowIdle != m_isIdle) {
        m_isIdle = nowIdle;
        qInfo() << "[PowerManagerCpp] Idle state changed:" << (nowIdle ? "idle" : "active");
        emit idleStateChanged(nowIdle);

        // If idle and auto-suspend is enabled, emit aboutToSleep
        if (nowIdle && m_autoSuspendEnabled) {
            qInfo() << "[PowerManagerCpp] Auto-suspend triggered after" << m_idleTimeout
                    << "seconds";
            // Note: Actual suspend should be handled by QML/UI layer
            // This just signals that the system should prepare for sleep
        }
    }
}

void PowerManagerCpp::applyCPUGovernor(PowerProfile profile) {
    if (!m_powerProfilesSupported) {
        qDebug() << "[PowerManagerCpp] CPU governor control not supported";
        return;
    }

    QString governor;
    switch (profile) {
        case Performance: governor = "performance"; break;
        case PowerSaver: governor = "powersave"; break;
        case Balanced:
        default: governor = "schedutil"; break;
    }

    // Try to set CPU governor via sysfs
    // Note: This requires write permission to /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
    // which should be granted by udev rules (70-marathon-shell.rules)
    QProcess process;
    process.start("sh",
                  {"-c",
                   QString("echo %1 | tee /sys/devices/system/cpu/cpufreq/policy*/scaling_governor")
                       .arg(governor)});
    process.waitForFinished(1000);

    if (process.exitCode() == 0) {
        qInfo() << "[PowerManagerCpp] CPU governor set to:" << governor;
    } else {
        qWarning() << "[PowerManagerCpp] Failed to set CPU governor:" << process.errorString();
        qWarning() << "[PowerManagerCpp] Error output:" << process.readAllStandardError();
    }
}

void PowerManagerCpp::checkCPUGovernorSupport() {
    // Check if CPU frequency scaling is available
    QFile scalingAvailable("/sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors");
    if (scalingAvailable.exists() && scalingAvailable.open(QIODevice::ReadOnly)) {
        QString governors = QString::fromLatin1(scalingAvailable.readAll()).trimmed();
        scalingAvailable.close();

        m_powerProfilesSupported = !governors.isEmpty();
        qInfo() << "[PowerManagerCpp] Available CPU governors:" << governors;
    } else {
        m_powerProfilesSupported = false;
        qDebug() << "[PowerManagerCpp] CPU frequency scaling not available";
    }
}

// ============================================================================
// Wakelock Management
// ============================================================================

void PowerManagerCpp::checkWakelockSupport() {
    // Check if kernel wakelock interface is available
    QFile wakeLockFile("/sys/power/wake_lock");
    m_wakelockSupported = wakeLockFile.exists();

    if (m_wakelockSupported) {
        qInfo() << "[PowerManagerCpp] Kernel wakelock support detected";
        // Test if we can write to it (requires CAP_BLOCK_SUSPEND or appropriate permissions)
        if (wakeLockFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            wakeLockFile.close();
            m_fallbackMode = "wakelock";
            qInfo() << "[PowerManagerCpp] Wakelock write access granted";
        } else {
            qDebug() << "[PowerManagerCpp] Wakelock write access denied - will use inhibitors";
            m_wakelockSupported = false;
            m_fallbackMode      = "inhibitor";
        }
    } else {
        qDebug() << "[PowerManagerCpp] Kernel wakelock interface not available "
                    "(CONFIG_PM_WAKELOCKS not enabled)";
        m_fallbackMode = "inhibitor";
    }
}

bool PowerManagerCpp::acquireWakelock(const QString &name) {
    if (m_activeWakelocks.contains(name) && m_activeWakelocks[name]) {
        qDebug() << "[PowerManagerCpp] Wakelock already held:" << name;
        return true;
    }

    // Try kernel wakelock first
    if (m_wakelockSupported && m_fallbackMode != "inhibitor") {
        if (writeToFile("/sys/power/wake_lock", name)) {
            m_activeWakelocks[name] = true;
            m_fallbackMode          = "wakelock";
            qInfo() << "[PowerManagerCpp] Acquired wakelock:" << name;
            return true;
        } else {
            qWarning() << "[PowerManagerCpp] Failed to acquire wakelock, falling back to inhibitor";
            m_fallbackMode = "inhibitor";
        }
    }

    // Fallback to systemd-logind inhibitor
    if (m_hasLogind) {
        bool success = inhibitSuspend("Marathon Shell", "Wakelock: " + name);
        if (success) {
            m_activeWakelocks[name] = true;
            qInfo() << "[PowerManagerCpp] Acquired inhibitor lock for:" << name;
            return true;
        }
    }

    qWarning() << "[PowerManagerCpp] Failed to acquire wakelock:" << name;
    return false;
}

bool PowerManagerCpp::releaseWakelock(const QString &name) {
    if (!m_activeWakelocks.contains(name) || !m_activeWakelocks[name]) {
        qDebug() << "[PowerManagerCpp] Wakelock not held:" << name;
        return true;
    }

    bool success = false;

    // Release kernel wakelock if that's what we're using
    if (m_fallbackMode == "wakelock") {
        success = writeToFile("/sys/power/wake_unlock", name);
        if (success) {
            qInfo() << "[PowerManagerCpp] Released wakelock:" << name;
        } else {
            qWarning() << "[PowerManagerCpp] Failed to release wakelock:" << name;
        }
    } else if (m_fallbackMode == "inhibitor") {
        // For inhibitors, we release all at once (single FD)
        // This is a limitation of the inhibitor API
        releaseInhibitor();
        qInfo() << "[PowerManagerCpp] Released inhibitor lock for:" << name;
        success = true;
    }

    if (success || m_fallbackMode == "inhibitor") {
        m_activeWakelocks[name] = false;
    }

    return success;
}

bool PowerManagerCpp::hasWakelock(const QString &name) const {
    return m_activeWakelocks.value(name, false);
}

bool PowerManagerCpp::inhibitSuspend(const QString &who, const QString &why) {
    if (!m_hasLogind) {
        qWarning() << "[PowerManagerCpp] Cannot inhibit - logind not available";
        return false;
    }

    // Call Inhibit method: Inhibit(what, who, why, mode)
    // Mode "delay" allows system to delay suspend for up to 5 seconds (safer for mobile)
    QDBusReply<QDBusUnixFileDescriptor> reply =
        m_logindInterface->call("Inhibit",
                                "sleep", // what: sleep, shutdown, idle, handle-power-key
                                who,     // who: human-readable application name
                                why,     // why: human-readable reason
                                "delay"  // mode: "block" or "delay"
        );

    if (reply.isValid()) {
        m_inhibitorFd = reply.value();
        qDebug() << "[PowerManagerCpp] Acquired inhibitor lock:" << who << "-" << why;
        return true;
    } else {
        qWarning() << "[PowerManagerCpp] Failed to acquire inhibitor lock:"
                   << reply.error().message();
        return false;
    }
}

void PowerManagerCpp::releaseInhibitor() {
    // Closing the file descriptor releases the inhibitor lock
    // QDBusUnixFileDescriptor automatically closes FD when reset
    if (m_inhibitorFd.isValid()) {
        m_inhibitorFd = QDBusUnixFileDescriptor();
        qDebug() << "[PowerManagerCpp] Released inhibitor lock";
    }
}

void PowerManagerCpp::cleanupWakelocks() {
    // Release all active wakelocks
    qInfo() << "[PowerManagerCpp] Cleaning up wakelocks...";
    for (auto it = m_activeWakelocks.begin(); it != m_activeWakelocks.end(); ++it) {
        if (it.value()) {
            releaseWakelock(it.key());
        }
    }
}

bool PowerManagerCpp::writeToFile(const QString &path, const QString &content) {
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream out(&file);
    out << content;
    file.close();

    return true;
}

// ============================================================================
// RTC Alarm Support
// ============================================================================

void PowerManagerCpp::checkRtcAlarmSupport() {
    // Check if RTC wakealarm interface is available
    QFile rtcWakeAlarm("/sys/class/rtc/rtc0/wakealarm");
    m_rtcAlarmSupported = rtcWakeAlarm.exists();

    if (m_rtcAlarmSupported) {
        qInfo() << "[PowerManagerCpp] RTC wakealarm support detected";
        // Test if we can write to it
        if (rtcWakeAlarm.open(QIODevice::WriteOnly | QIODevice::Text)) {
            rtcWakeAlarm.close();
            qInfo() << "[PowerManagerCpp] RTC wakealarm write access granted";
        } else {
            qDebug() << "[PowerManagerCpp] RTC wakealarm write access denied";
            m_rtcAlarmSupported = false;
        }
    } else {
        qDebug() << "[PowerManagerCpp] RTC wakealarm interface not available";
    }
}

bool PowerManagerCpp::setRtcAlarm(qint64 epochTime) {
    if (!m_rtcAlarmSupported) {
        qWarning() << "[PowerManagerCpp] RTC alarm not supported";
        return false;
    }

    // Clear existing alarm first
    if (!writeToRtcWakeAlarm("0")) {
        qWarning() << "[PowerManagerCpp] Failed to clear existing RTC alarm";
        return false;
    }

    // Set new alarm
    if (!writeToRtcWakeAlarm(QString::number(epochTime))) {
        qWarning() << "[PowerManagerCpp] Failed to set RTC alarm";
        return false;
    }

    QDateTime wakeTime = QDateTime::fromSecsSinceEpoch(epochTime);
    qInfo() << "[PowerManagerCpp] RTC alarm set for:" << wakeTime.toString();
    return true;
}

bool PowerManagerCpp::clearRtcAlarm() {
    if (!m_rtcAlarmSupported) {
        return false;
    }

    bool success = writeToRtcWakeAlarm("0");
    if (success) {
        qInfo() << "[PowerManagerCpp] RTC alarm cleared";
    }
    return success;
}

bool PowerManagerCpp::writeToRtcWakeAlarm(const QString &value) {
    QFile file("/sys/class/rtc/rtc0/wakealarm");
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[PowerManagerCpp] Failed to open wakealarm:" << file.errorString();
        return false;
    }

    QTextStream out(&file);
    out << value;
    file.close();

    return true;
}
