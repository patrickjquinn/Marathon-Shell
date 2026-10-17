#include "powermanagercpp.h"
#include "waketimers.h"
#include <QJSEngine>
#include <QQmlEngine>
#include <QDebug>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusPendingCallWatcher>
#include <QDateTime>
#include <QFile>
#include <QDBusServiceWatcher>

namespace {

    QString powerProfilesService() {
        return QStringLiteral("org.freedesktop.UPower.PowerProfiles");
    }
    QString powerProfilesPath() {
        return QStringLiteral("/org/freedesktop/UPower/PowerProfiles");
    }

} // namespace

PowerManagerCpp *PowerManagerCpp::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new PowerManagerCpp(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}
QStringList PowerManagerCpp::activeWakelocks() const {
    QStringList result;
    for (auto it = m_activeWakelocks.constBegin(); it != m_activeWakelocks.constEnd(); ++it) {
        if (it.value())
            result.push_back(it.key());
    }
    return result;
}

PowerManagerCpp::PowerManagerCpp(QObject *parent)
    : QObject(parent)
    , m_upowerInterface(nullptr)
    , m_logindInterface(nullptr)
    , m_batteryLevel(75)
    , m_warningLevel(0)
    , m_isCharging(false)
    , m_isPluggedIn(false)
    , m_isPowerSaveMode(false)
    , m_estimatedBatteryTime(-1)
    , m_hasUPower(false)
    , m_hasLogind(false)
    , m_powerProfileString("balanced")
    , m_powerProfilesSupported(false)
    , m_idleTimeout(300)
    , m_autoSuspendEnabled(true)
    , m_isIdle(false)
    , m_lastActivityTime(QDateTime::currentMSecsSinceEpoch())
    , m_wakelockSupported(false)
    , m_fallbackMode("none")
    , m_wakeTimers(new WakeTimers(QDBusConnection::sessionBus(), this))
    , m_criticalAction(QStringLiteral("PowerOff")) {
    qInfo() << "[PowerManagerCpp] Initializing";

    m_upowerInterface =
        new QDBusInterface("org.freedesktop.UPower", "/org/freedesktop/UPower",
                           "org.freedesktop.UPower", QDBusConnection::systemBus(), this);

    if (m_upowerInterface->isValid()) {
        m_hasUPower = true;
        qInfo() << "[PowerManagerCpp] Connected to UPower D-Bus";

        QDBusReply<QString> criticalReply = m_upowerInterface->call("GetCriticalAction");
        if (criticalReply.isValid() && !criticalReply.value().isEmpty()) {
            m_criticalAction = criticalReply.value();
        }
        qInfo() << "[PowerManagerCpp] UPower critical action:" << m_criticalAction;
        setupDBusConnections();
        setupDisplayDevice();
    } else {
        qDebug() << "[PowerManagerCpp] UPower D-Bus not available:"
                 << m_upowerInterface->lastError().message();
        qDebug() << "[PowerManagerCpp] Using simulated battery";
    }

    m_logindInterface =
        new QDBusInterface("org.freedesktop.login1", "/org/freedesktop/login1",
                           "org.freedesktop.login1.Manager", QDBusConnection::systemBus(), this);

    if (m_logindInterface->isValid()) {
        m_hasLogind = true;
        qDebug() << "[PowerManagerCpp] Connected to systemd-logind D-Bus";
        // Take the lifelong sleep/delay inhibit at boot. setupDBusConnections
        // runs from the UPower branch above (so PrepareForSleep is wired even
        // when UPower is missing), but we have to defer the actual inhibit
        // call until after m_logindInterface is alive.
        inhibitSuspend("marathon-shell", "Handle wake events");
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind D-Bus not available:"
                 << m_logindInterface->lastError().message();
    }

    setupPowerProfiles();

    checkWakelockSupport();

    m_idleTimer = new QTimer(this);
    m_idleTimer->setInterval(10000);
    connect(m_idleTimer, &QTimer::timeout, this, &PowerManagerCpp::checkIdleState);
    m_idleTimer->start();

    qInfo() << "[PowerManagerCpp] Power profiles supported:" << m_powerProfilesSupported;
    qInfo() << "[PowerManagerCpp] Current power profile:" << m_powerProfileString;
    qInfo() << "[PowerManagerCpp] Wakelock support:"
            << (m_wakelockSupported ? "enabled" : "disabled (will use inhibitors)");
}

PowerManagerCpp::~PowerManagerCpp() {

    cleanupWakelocks();
    releaseInhibitor();

    // m_upowerInterface, m_displayDeviceInterface, and m_logindInterface
    // are parented to this; Qt will delete them
}

void PowerManagerCpp::setupDBusConnections() {
    // Subscribe to PrepareForSleep regardless of m_hasLogind -- the system
    // bus is global, signals route by name, and we want this in place even
    // before m_logindInterface initialises later in the constructor.
    QDBusConnection::systemBus().connect("org.freedesktop.login1", "/org/freedesktop/login1",
                                         "org.freedesktop.login1.Manager", "PrepareForSleep", this,
                                         SLOT(onPrepareForSleep(bool)));
    // The lifelong sleep/delay inhibit is taken in PowerManagerCpp() right
    // after logind init -- see PowerManagerCpp::PowerManagerCpp.
}

void PowerManagerCpp::setupDisplayDevice() {
    m_displayDeviceInterface = new QDBusInterface(
        "org.freedesktop.UPower", "/org/freedesktop/UPower/devices/DisplayDevice",
        "org.freedesktop.UPower.Device", QDBusConnection::systemBus(), this);

    if (m_displayDeviceInterface->isValid()) {
        qInfo() << "[PowerManagerCpp] Connected to DisplayDevice";

        QDBusConnection::systemBus().connect("org.freedesktop.UPower",
                                             "/org/freedesktop/UPower/devices/DisplayDevice",
                                             "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                             this, SLOT(updateAggregateState()));

        updateAggregateState();
    } else {
        qWarning() << "[PowerManagerCpp] DisplayDevice not available:"
                   << m_displayDeviceInterface->lastError().message();
    }
}

void PowerManagerCpp::updateAggregateState() {
    if (!m_displayDeviceInterface || !m_displayDeviceInterface->isValid()) {

        if (m_batteryLevel != 100) {
            m_batteryLevel       = 100;
            m_isCharging         = false;
            m_isPluggedIn        = true;
            m_warningLevel       = 1;
            emit batteryLevelChanged();
            emit warningLevelChanged();
            emit isChargingChanged();
            emit isPluggedInChanged();
        }
        return;
    }

    int          newLevel     = qRound(m_displayDeviceInterface->property("Percentage").toDouble());
    uint         state        = m_displayDeviceInterface->property("State").toUInt();
    const uint   warningLevel = m_displayDeviceInterface->property("WarningLevel").toUInt();
    const qint64 timeToEmptySeconds =
        m_displayDeviceInterface->property("TimeToEmpty").toLongLong();
    const qint64 timeToFullSeconds = m_displayDeviceInterface->property("TimeToFull").toLongLong();

    const bool   newCharging  = (state == 1 || state == 5);
    const bool   newPluggedIn = (state == 1 || state == 4 || state == 5);

    if (m_batteryLevel != newLevel) {
        qInfo() << "[PowerManagerCpp] Battery Level Changed:" << m_batteryLevel << "->" << newLevel;
        m_batteryLevel = newLevel;
        emit batteryLevelChanged();
    }

    if (m_warningLevel != warningLevel) {
        m_warningLevel = warningLevel;
        emit warningLevelChanged();

        if (m_warningLevel >= 4) {
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

    int newEstimatedMinutes = -1;
    if (state == 2 || state == 6) {
        if (timeToEmptySeconds > 0)
            newEstimatedMinutes = static_cast<int>(timeToEmptySeconds / 60);
    } else if (state == 1 || state == 5) {
        if (timeToFullSeconds > 0)
            newEstimatedMinutes = static_cast<int>(timeToFullSeconds / 60);
    }

    if (m_estimatedBatteryTime != newEstimatedMinutes) {
        m_estimatedBatteryTime = newEstimatedMinutes;
        emit estimatedBatteryTimeChanged();
    }

    qDebug() << "[PowerManagerCpp] State Updated - Level:" << m_batteryLevel
             << "% Charging:" << m_isCharging << "PluggedIn:" << m_isPluggedIn;
}

bool PowerManagerCpp::isBackgroundWake(const QString &markerPath, qint64 alarmSecs,
                                       qint64 nowSecs) {
    const auto wokeFor = [nowSecs](qint64 t) { return nowSecs >= t - 10 && nowSecs <= t + 60; };
    if (alarmSecs > 0 && wokeFor(alarmSecs))
        return false;
    QFile marker(markerPath);
    if (!marker.open(QIODevice::ReadOnly))
        return false;
    bool         ok    = false;
    const qint64 armed = marker.readAll().trimmed().toLongLong(&ok);
    return ok && wokeFor(armed);
}

void PowerManagerCpp::onPrepareForSleep(bool beforeSleep) {
    if (beforeSleep) {
        qInfo() << "[PowerManagerCpp] System preparing for sleep";
        releaseInhibitor();
        m_wakelockInhibitors.clear();
    } else {
        const bool background = isBackgroundWake(QStringLiteral("/run/marathon-background/wake"),
                                                 m_alarmWake, QDateTime::currentSecsSinceEpoch());
        qInfo() << "[PowerManagerCpp] System resumed from sleep"
                << (background ? "for background work" : "");
        emit resumedFromSuspend(background);

        for (auto it = m_activeWakelocks.begin(); it != m_activeWakelocks.end(); ++it) {
            if (!it.value())
                continue;
            qDebug() << "[PowerManagerCpp] Re-acquiring wakelock after resume:" << it.key();
            if (m_fallbackMode == "inhibitor")
                m_wakelockInhibitors.insert(
                    it.key(), takeInhibitor("Marathon Shell", "Wakelock: " + it.key()));
            else
                writeToFile("/sys/power/wake_lock", it.key());
        }

        // Reacquire the lifelong delay-inhibit so the next suspend cycle
        // gives us another window to handle radio events.
        if (m_hasLogind && !m_inhibitorFd.isValid())
            inhibitSuspend("marathon-shell", "Handle wake events");
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

void PowerManagerCpp::hybridSleep() {
    qDebug() << "[PowerManagerCpp] Hybrid sleeping system";

    if (m_hasLogind) {
        QDBusReply<void> reply = m_logindInterface->call("HybridSleep", true);
        if (!reply.isValid()) {
            qDebug() << "[PowerManagerCpp] Failed to hybrid sleep:" << reply.error().message();
            emit powerError("Failed to hybrid sleep system");
        }
    } else {
        qDebug() << "[PowerManagerCpp] systemd-logind not available, cannot hybrid sleep";
        emit powerError("HybridSleep not available");
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
    if (m_isPowerSaveMode == enabled)
        return;
    qInfo() << "[PowerManagerCpp] Power save mode:" << enabled;
    m_isPowerSaveMode = enabled;

    // Saver used to be a cosmetic bool. Give it real, SAFE effects:
    //  1) switch to the power-saver power profile (the profile daemon owns
    //     the CPU governor; exit restores the profile from before), and
    //  2) shorten the idle timeout so the display Dozes sooner.
    // Deliberately does NOT enable auto-suspend (S3): on this hardware S3 has
    // an unresolved unwakeable-screen bug, so Saver must never push the device
    // into it. Doze (display-off, ~0.1 W, power-key-wakeable) is the low-power
    // path we lean on instead.
    static const int kSaverIdleTimeoutSeconds = 30;
    if (enabled) {
        m_preSaverIdleTimeout = m_idleTimeout;
        m_preSaverProfile     = m_powerProfileString;
        setPowerProfile(QStringLiteral("power-saver"));
        if (m_idleTimeout <= 0 || m_idleTimeout > kSaverIdleTimeoutSeconds)
            setIdleTimeout(kSaverIdleTimeoutSeconds);
    } else {
        setPowerProfile(m_preSaverProfile.isEmpty() ? QStringLiteral("balanced")
                                                    : m_preSaverProfile);
        if (m_preSaverIdleTimeout > 0)
            setIdleTimeout(m_preSaverIdleTimeout);
    }

    emit isPowerSaveModeChanged();
}

void PowerManagerCpp::setPowerProfile(const QString &profile) {
    QString name = QStringLiteral("balanced");
    if (profile == QLatin1String("performance"))
        name = QStringLiteral("performance");
    else if (profile == QLatin1String("power-saver") || profile == QLatin1String("powersave"))
        name = QStringLiteral("power-saver");

    if (!m_powerProfilesSupported) {
        qWarning() << "[PowerManagerCpp] No power profile service; cannot set" << name;
        return;
    }
    qInfo() << "[PowerManagerCpp] Setting power profile to:" << name;

    QDBusMessage set = QDBusMessage::createMethodCall(
        powerProfilesService(), powerProfilesPath(),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
    set.setArguments({powerProfilesService(), QStringLiteral("ActiveProfile"),
                      QVariant::fromValue(QDBusVariant(name))});
    // A profile switch runs the daemon's tuning; never wait for it here.
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(set), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, name](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                const QDBusPendingReply<> reply = *w;
                if (reply.isError()) {
                    qWarning() << "[PowerManagerCpp] Power profile" << name
                               << "refused:" << reply.error().message();
                    return;
                }
                applyActiveProfile(name);
            });
}

void PowerManagerCpp::setupPowerProfiles() {
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(powerProfilesService(), powerProfilesPath(),
                QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("PropertiesChanged"), this,
                SLOT(onPowerProfilesChanged(QString, QVariantMap, QStringList)));
    auto *watcher = new QDBusServiceWatcher(powerProfilesService(), bus,
                                            QDBusServiceWatcher::WatchForRegistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this,
            &PowerManagerCpp::readActiveProfile);
    readActiveProfile();
}

void PowerManagerCpp::readActiveProfile() {
    QDBusMessage get = QDBusMessage::createMethodCall(
        powerProfilesService(), powerProfilesPath(),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    get.setArguments({powerProfilesService(), QStringLiteral("ActiveProfile")});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<QDBusVariant> reply = *w;
        if (reply.isError()) {
            qInfo() << "[PowerManagerCpp] No power profile service:" << reply.error().message();
            return;
        }
        applyActiveProfile(reply.value().variant().toString());
    });
}

void PowerManagerCpp::onPowerProfilesChanged(const QString &, const QVariantMap &changed,
                                             const QStringList &) {
    const auto it = changed.constFind(QStringLiteral("ActiveProfile"));
    if (it != changed.constEnd())
        applyActiveProfile(it->toString());
}

void PowerManagerCpp::applyActiveProfile(const QString &profile) {
    if (!m_powerProfilesSupported || m_powerProfileString != profile) {
        m_powerProfilesSupported = true;
        m_powerProfileString     = profile;
        emit powerProfileChanged();
    }
    const bool saver = profile == QLatin1String("power-saver");
    if (m_isPowerSaveMode != saver) {
        m_isPowerSaveMode = saver;
        emit isPowerSaveModeChanged();
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

void PowerManagerCpp::updateActivity() {
    m_lastActivityTime = QDateTime::currentMSecsSinceEpoch();
    if (m_isIdle) {
        m_isIdle = false;
        emit idleStateChanged(false);
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

        if (nowIdle && m_autoSuspendEnabled) {
            qInfo() << "[PowerManagerCpp] Auto-suspend triggered after" << m_idleTimeout
                    << "seconds";
        }
    }
}

void PowerManagerCpp::checkWakelockSupport() {

    QFile wakeLockFile("/sys/power/wake_lock");
    m_wakelockSupported = wakeLockFile.exists();

    if (m_wakelockSupported) {
        qInfo() << "[PowerManagerCpp] Kernel wakelock support detected";

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

    if (m_wakelockSupported && m_fallbackMode != "inhibitor") {
        if (writeToFile("/sys/power/wake_lock", name)) {
            m_activeWakelocks[name] = true;
            m_fallbackMode          = "wakelock";
            qInfo() << "[PowerManagerCpp] Acquired wakelock:" << name;
            emit activeWakelocksChanged();
            return true;
        } else {
            qWarning() << "[PowerManagerCpp] Failed to acquire wakelock, falling back to inhibitor";
            m_fallbackMode = "inhibitor";
        }
    }

    if (m_hasLogind) {
        const QDBusUnixFileDescriptor fd = takeInhibitor("Marathon Shell", "Wakelock: " + name);
        if (fd.isValid()) {
            m_wakelockInhibitors.insert(name, fd);
            m_activeWakelocks[name] = true;
            qInfo() << "[PowerManagerCpp] Acquired inhibitor lock for:" << name;
            emit activeWakelocksChanged();
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

    if (m_fallbackMode == "wakelock") {
        success = writeToFile("/sys/power/wake_unlock", name);
        if (success) {
            qInfo() << "[PowerManagerCpp] Released wakelock:" << name;
        } else {
            qWarning() << "[PowerManagerCpp] Failed to release wakelock:" << name;
        }
    } else if (m_fallbackMode == "inhibitor") {
        m_wakelockInhibitors.remove(name);
        qInfo() << "[PowerManagerCpp] Released inhibitor lock for:" << name;
        success = true;
    }

    if (success || m_fallbackMode == "inhibitor") {
        m_activeWakelocks[name] = false;
        emit activeWakelocksChanged();
    }

    return success;
}

QDBusUnixFileDescriptor PowerManagerCpp::takeInhibitor(const QString &who, const QString &why) {
    if (!m_hasLogind) {
        qWarning() << "[PowerManagerCpp] Cannot inhibit - logind not available";
        return {};
    }

    QDBusReply<QDBusUnixFileDescriptor> reply =
        m_logindInterface->call("Inhibit", "sleep", who, why, "delay");
    if (!reply.isValid()) {
        qWarning() << "[PowerManagerCpp] Failed to acquire inhibitor lock:"
                   << reply.error().message();
        return {};
    }
    qDebug() << "[PowerManagerCpp] Acquired inhibitor lock:" << who << "-" << why;
    return reply.value();
}

bool PowerManagerCpp::inhibitSuspend(const QString &who, const QString &why) {
    m_inhibitorFd = takeInhibitor(who, why);
    return m_inhibitorFd.isValid();
}

void PowerManagerCpp::releaseInhibitor() {

    if (m_inhibitorFd.isValid()) {
        m_inhibitorFd = QDBusUnixFileDescriptor();
        qDebug() << "[PowerManagerCpp] Released inhibitor lock";
    }
}

void PowerManagerCpp::cleanupWakelocks() {

    qInfo() << "[PowerManagerCpp] Cleaning up wakelocks...";
    for (auto it = m_activeWakelocks.begin(); it != m_activeWakelocks.end(); ++it) {
        if (it.value()) {
            releaseWakelock(it.key());
        }
    }
    emit activeWakelocksChanged();
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

void PowerManagerCpp::setAlarmWake(qint64 epochSecs) {
    m_alarmWake = epochSecs;
    m_wakeTimers->set(QStringLiteral("alarm"), epochSecs);
}
