#include "displaymanagercpp.h"
#include "powermanagercpp.h"
#include "rotationmanager.h"
#include "sensormanagercpp.h"
#include "platform.h"
#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QEventLoop>
#include <QProcess>
#include <QtMath>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QTimer>
#include <QThread>
#include <QFileSystemWatcher>
#include <QScreen>
#include <QSettings>
#include <QStringList>
#include <cmath>
#if MARATHON_HAVE_QT_GUI_PRIVATE
#include <qpa/qplatformscreen.h>
#endif

// Minimum PHYSICAL backlight duty. The user-facing brightness slider
// runs 0..100%, but 0% must never make the panel invisible — on the
// Librem 5 a fully-dimmed backlight is indistinguishable from a dead
// screen. So we remap the user's [0,1] onto the hardware range
// [kMinVisibleBrightness, 1.0]: slider 0% -> ~28% real duty, slider
// 100% -> 100%. All hardware writes go through brightnessUserToHw() and
// all sysfs reads come back through brightnessHwToUser() so the slider
// still reflects the user's own 0..100 setting.
static constexpr double kMinVisibleBrightness = 0.28;

static inline double    brightnessUserToHw(double user) {
    user = qBound(0.0, user, 1.0);
    return kMinVisibleBrightness + (1.0 - kMinVisibleBrightness) * user;
}

static inline double brightnessHwToUser(double hw) {
    return qBound(0.0, (hw - kMinVisibleBrightness) / (1.0 - kMinVisibleBrightness), 1.0);
}

DisplayManagerCpp::DisplayManagerCpp(PowerManagerCpp *powerManager,
                                     RotationManager *rotationManager, QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_maxBrightness(100)
    , m_autoBrightnessEnabled(false)
    , m_rotationLocked(false)
    , m_screenTimeout(300)
    , m_brightness(0.5)
    , m_nightLightEnabled(false)
    , m_nightLightTemperature(3400)
    , m_nightLightSchedule("off")
    , m_powerManager(powerManager)
    , m_rotationManager(rotationManager) {
    qDebug() << "[DisplayManagerCpp] Initializing";

    if (Platform::hasBacklightControl()) {
        m_available = detectBacklightDevice();
        if (m_available) {
            qInfo() << "[DisplayManagerCpp] Backlight control available:" << m_backlightDevice;
            m_brightness = getBrightness();

            setupBrightnessMonitoring();
        } else {
            qInfo() << "[DisplayManagerCpp] No backlight devices found";
        }
    } else {
        qInfo() << "[DisplayManagerCpp] Backlight control not available on this platform";
    }

    loadSettings();
}

bool DisplayManagerCpp::detectBacklightDevice() {
    QDir backlightDir("/sys/class/backlight");
    if (!backlightDir.exists()) {
        return false;
    }

    QStringList devices = backlightDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (devices.isEmpty()) {
        return false;
    }

    if (devices.contains("apple-panel-bl")) {
        m_backlightDevice = "apple-panel-bl";
    } else if (devices.contains("intel_backlight")) {
        m_backlightDevice = "intel_backlight";
    } else {
        m_backlightDevice = devices.first();
    }

    QString maxBrightnessPath =
        QString("/sys/class/backlight/%1/max_brightness").arg(m_backlightDevice);

    QFile maxFile(maxBrightnessPath);
    if (maxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString value   = maxFile.readAll().trimmed();
        m_maxBrightness = value.toInt();
        maxFile.close();
        qInfo() << "[DisplayManagerCpp] Detected backlight device:" << m_backlightDevice
                << "max brightness:" << m_maxBrightness;
        return true;
    }

    return false;
}

double DisplayManagerCpp::brightness() const {
    // Live sysfs read on every binding evaluation. The cached m_brightness
    // drifts when systemd-logind or kernel auto-brightness writes the
    // brightness file without firing the QFileSystemWatcher inotify event
    // we expect (sysfs nodes are "special" — replaced not renamed on some
    // kernel paths). QML caches the binding result until brightnessChanged
    // emits, so the perceived cost is one sysfs read per emit, not per
    // frame.
    if (!m_available)
        return m_brightness;
    QFile file(QStringLiteral("/sys/class/backlight/%1/brightness").arg(m_backlightDevice));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const int v = file.readAll().trimmed().toInt();
        file.close();
        if (m_maxBrightness > 0)
            return brightnessHwToUser(static_cast<double>(v) / m_maxBrightness);
    }
    return m_brightness;
}

void DisplayManagerCpp::forceBacklightOn() {
    if (m_backlightDevice.isEmpty())
        return;

    const QString blPath =
        QStringLiteral("/sys/class/backlight/%1/bl_power").arg(m_backlightDevice);
    const QString brPath =
        QStringLiteral("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);

    // Target duty = user brightness remapped through the visible floor
    // (never below ~28% real). Waking to a lit panel is non-negotiable.
    const int target = qBound(
        1, static_cast<int>(brightnessUserToHw(m_brightness) * m_maxBrightness), m_maxBrightness);

    auto writeFile = [](const QString &path, const QByteArray &val) {
        QFile f(path);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(val + "\n");
            f.close();
            return true;
        }
        return false;
    };

    // Full power-cycle of the backlight LED. After the display domain
    // gated (deep-idle Doze), the pwm-backlight duty can stay latched at
    // 0; a plain bl_power=0 leaves it dark. Powering the LED down, letting
    // the PWM/domain settle, then back up + re-writing the duty re-inits
    // it reliably — this is the exact sequence verified to recover a
    // wedged panel on i.MX8MQ. The brief msleep runs on the wake path
    // only (a one-time transition, not a hot path); the scene-graph render
    // thread is unaffected.
    writeFile(blPath, "4");
    QThread::msleep(30);
    writeFile(blPath, "0");
    // Nudge low->target across two stores so pwm_backlight_update_status
    // re-applies the duty (a single idempotent write can be skipped).
    writeFile(brPath, "1");
    if (!writeFile(brPath, QByteArray::number(target))) {
        qWarning() << "[DisplayManagerCpp] forceBacklightOn: cannot write brightness";
    }
}

double DisplayManagerCpp::getBrightness() {
    if (!m_available) {
        return 0.5;
    }

    QString brightnessPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);

    QFile   file(brightnessPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString value        = file.readAll().trimmed();
        int     currentValue = value.toInt();
        file.close();

        double brightness = brightnessHwToUser(static_cast<double>(currentValue) / m_maxBrightness);
        qDebug() << "[DisplayManagerCpp] Current brightness:" << currentValue << "/"
                 << m_maxBrightness << "=" << (brightness * 100) << "% (user)";
        return brightness;
    }

    qWarning() << "[DisplayManagerCpp] Failed to read brightness";
    return 0.5;
}

void DisplayManagerCpp::setBrightness(double brightness) {
    if (!m_available) {
        qDebug() << "[DisplayManagerCpp] Backlight control not available";
        return;
    }

    brightness = qBound(0.0, brightness, 1.0);

    qInfo() << "[DisplayManagerCpp] Setting brightness to" << brightness
            << " (current internal:" << m_brightness << ")";

    // Manual set — the user's intent wins over auto-brightness for a
    // grace window, and any in-flight auto ramp is abandoned.
    m_lastManualSetMs = QDateTime::currentMSecsSinceEpoch();
    if (m_rampTimer && m_rampTimer->isActive())
        m_rampTimer->stop();

    // Store the USER value (what the slider shows); drive the hardware
    // with the remapped value so 0% still lights the panel (~28% duty).
    m_brightness = brightness;

    const double hwBrightness    = brightnessUserToHw(brightness);
    int          brightnessValue = static_cast<int>(hwBrightness * m_maxBrightness);

    QString brightnessPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);

    QDBusMessage    message = QDBusMessage::createMethodCall("org.gnome.SettingsDaemon.Power",
                                                             "/org/gnome/SettingsDaemon/Power",
                                                             "org.freedesktop.DBus.Properties", "Set");

    QList<QVariant> args;
    args << "org.gnome.SettingsDaemon.Power.Screen";
    args << "Brightness";

    int gsdValue = static_cast<int>(hwBrightness * 100.0);
    args << QVariant::fromValue(QDBusVariant(gsdValue));
    message.setArguments(args);

    QDBusMessage reply = QDBusConnection::sessionBus().call(message);
    if (reply.type() != QDBusMessage::ErrorMessage) {
        qInfo() << "[DisplayManagerCpp] Set brightness to:" << brightnessValue << "% via GSD D-Bus";
        emit brightnessChanged();
        return;
    } else {
        qDebug() << "[DisplayManagerCpp] GSD D-Bus call failed:" << reply.errorMessage();
    }

    if (Platform::hasLogind()) {
        QDBusMessage logindMsg = QDBusMessage::createMethodCall(
            "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session", "SetBrightness");

        QList<QVariant> logindArgs;
        logindArgs << "backlight";
        logindArgs << m_backlightDevice;
        logindArgs << (uint)brightnessValue;
        logindMsg.setArguments(logindArgs);

        QDBusMessage logindReply = QDBusConnection::systemBus().call(logindMsg);
        if (logindReply.type() != QDBusMessage::ErrorMessage) {
            qInfo() << "[DisplayManagerCpp] Set brightness to:" << brightnessValue << "via logind";
            emit brightnessChanged();
            return;
        } else {
            qDebug() << "[DisplayManagerCpp] logind call failed:" << logindReply.errorMessage();
        }
    }

    QFile file(brightnessPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << brightnessValue;
        file.close();
        qDebug() << "[DisplayManagerCpp] Set brightness to:" << brightnessValue << "("
                 << (brightness * 100) << "%) via sysfs";
        emit brightnessChanged();
    } else {
        qDebug() << "[DisplayManagerCpp] Failed to set brightness: permission denied (sysfs) and "
                    "D-Bus methods failed";
    }
}

void DisplayManagerCpp::setSensorManager(SensorManagerCpp *sensorManager) {
    m_sensorManager = sensorManager;
    if (m_sensorManager && m_autoBrightnessEnabled) {
        connect(m_sensorManager, &SensorManagerCpp::ambientLightChanged, this,
                &DisplayManagerCpp::onAmbientLightChanged);
    }
}

void DisplayManagerCpp::setAutoBrightness(bool enabled) {
    if (m_autoBrightnessEnabled == enabled) {
        return;
    }

    m_autoBrightnessEnabled = enabled;
    emit autoBrightnessEnabledChanged();
    saveSettings();

    if (m_sensorManager) {
        if (enabled) {
            connect(m_sensorManager, &SensorManagerCpp::ambientLightChanged, this,
                    &DisplayManagerCpp::onAmbientLightChanged, Qt::UniqueConnection);
            onAmbientLightChanged();
        } else {
            disconnect(m_sensorManager, &SensorManagerCpp::ambientLightChanged, this,
                       &DisplayManagerCpp::onAmbientLightChanged);
        }
    }

    qInfo() << "[DisplayManagerCpp] Auto-brightness" << (enabled ? "enabled" : "disabled");
}

// Perceptual lux -> user-brightness [0,1] curve. Human brightness
// perception is roughly logarithmic, so we map on log10(lux). Anchored
// so a dark room (0 lux) sits just above the visible floor and direct
// sun (~10000 lux) hits 100%. The user domain is then remapped through
// kMinVisibleBrightness on the way to hardware (setBrightness /
// forceBacklightOn), so this never drives the panel invisible.
double DisplayManagerCpp::baseCurve(double lux) const {
    if (lux < 0.0)
        lux = 0.0;
    // 0 lux -> 0.05, 50 -> ~0.46, 500 -> ~0.70, 1000 -> ~0.77, 10000 -> 1.0
    const double u = 0.05 + 0.24 * std::log10(lux + 1.0);
    return qBound(0.0, u, 1.0);
}

// Long-term learned offset: piecewise-linear over kAdaptAnchors anchors spaced
// 0.5 apart in log10(lux+1), covering lux 0..10000.
double DisplayManagerCpp::longTermOffset(double logLux) const {
    const double ll = qBound(0.0, logLux, 4.0);
    const double f  = ll / 0.5;
    int          i  = static_cast<int>(std::floor(f));
    if (i >= kAdaptAnchors - 1)
        i = kAdaptAnchors - 2;
    const double t = f - i;
    return m_ltOffset[i] * (1.0 - t) + m_ltOffset[i + 1] * t;
}

// Effective offset = long-term baseline, overridden by the short-term exact fit
// with a Gaussian falloff so your last correction fully applies in that lighting
// and relaxes to the learned baseline as the ambient level moves away from it.
double DisplayManagerCpp::learnedOffset(double lux) const {
    const double ll = std::log10((lux < 0.0 ? 0.0 : lux) + 1.0);
    const double lt = longTermOffset(ll);
    if (m_stLogLux < 0.0)
        return lt;
    const double d = (ll - m_stLogLux) / 0.6; // ~0.6 decade sigma
    const double w = std::exp(-d * d);
    return lt + w * (m_stOffset - lt);
}

double DisplayManagerCpp::luxToUserBrightness(double lux) const {
    return qBound(0.05, baseCurve(lux) + learnedOffset(lux), 1.0);
}

// Teach the adaptive curve from a genuine user brightness choice at the current
// ambient level. Short-term takes the exact delta (instant, exact satisfaction);
// long-term blends toward it at a gentle rate so one-off corrections don't
// dominate but repeated ones stick across sessions.
void DisplayManagerCpp::learnFromUser(double userBrightness) {
    if (!m_autoBrightnessEnabled || !m_sensorManager)
        return;
    double lux = (m_luxEwma >= 0.0) ? m_luxEwma : m_sensorManager->ambientLight();
    if (lux < 0.0)
        lux = 0.0;
    const double ll      = std::log10(lux + 1.0);
    const double desired = qBound(-0.5, userBrightness - baseCurve(lux), 0.5);

    // Short-term takes effect instantly so the live setting sticks in this
    // lighting; the long-term blend + disk write are debounced to the settled
    // value so a slider drag teaches once, not once per intermediate frame.
    m_stOffset       = desired;
    m_stLogLux       = ll;
    m_pendingDesired = desired;
    m_pendingLogLux  = ll;

    if (!m_learnCommitTimer) {
        m_learnCommitTimer = new QTimer(this);
        m_learnCommitTimer->setSingleShot(true);
        m_learnCommitTimer->setInterval(600);
        connect(m_learnCommitTimer, &QTimer::timeout, this, &DisplayManagerCpp::commitLearning);
    }
    m_learnCommitTimer->start();
}

void DisplayManagerCpp::commitLearning() {
    if (m_pendingLogLux < 0.0)
        return;
    // Blend the two bracketing anchors toward the settled correction.
    const double clampedLt = qBound(-0.4, m_pendingDesired, 0.4);
    const double f         = qBound(0.0, m_pendingLogLux, 4.0) / 0.5;
    int          i         = static_cast<int>(std::floor(f));
    if (i >= kAdaptAnchors - 1)
        i = kAdaptAnchors - 2;
    constexpr double kLearnRate = 0.5;
    for (int k : {i, i + 1}) {
        m_ltOffset[k] += kLearnRate * (clampedLt - m_ltOffset[k]);
        m_ltOffset[k] = qBound(-0.4, m_ltOffset[k], 0.4);
    }
    saveSettings();
}

void DisplayManagerCpp::setBrightnessFromUser(double brightness) {
    setBrightness(brightness);
    learnFromUser(brightness);
}

void DisplayManagerCpp::onAmbientLightChanged() {
    if (!m_autoBrightnessEnabled || !m_sensorManager)
        return;

    // Respect a manual override: if the user just touched brightness,
    // hold auto off for a grace window so their intent wins.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastManualSetMs < 5000)
        return;

    const double lux = m_sensorManager->ambientLight();

    // EWMA smoothing to reject sensor spikes (alpha 0.25).
    if (m_luxEwma < 0.0)
        m_luxEwma = lux;
    else
        m_luxEwma = 0.25 * lux + 0.75 * m_luxEwma;

    const double target = luxToUserBrightness(m_luxEwma);
    const double delta  = target - m_brightness;

    // Deadband — ignore micro-changes so the panel never hunts.
    constexpr double kDeadband = 0.06;
    if (std::abs(delta) < kDeadband) {
        m_luxAboveSinceMs = 0;
        m_luxBelowSinceMs = 0;
        return;
    }

    // Asymmetric dwell: brighten fast (you walked into sunlight), dim
    // slow (don't chase flickering / passing shadows). This is the
    // iOS/Android feel — responsive up, gentle down.
    constexpr qint64 kBrightenDwellMs = 300;
    constexpr qint64 kDimDwellMs      = 1500;

    if (delta > 0) { // need to brighten
        m_luxBelowSinceMs = 0;
        if (m_luxAboveSinceMs == 0)
            m_luxAboveSinceMs = now;
        if (now - m_luxAboveSinceMs < kBrightenDwellMs)
            return;
    } else { // need to dim
        m_luxAboveSinceMs = 0;
        if (m_luxBelowSinceMs == 0)
            m_luxBelowSinceMs = now;
        if (now - m_luxBelowSinceMs < kDimDwellMs)
            return;
    }
    m_luxAboveSinceMs = 0;
    m_luxBelowSinceMs = 0;

    m_autoTargetUser = target;
    startBrightnessRamp(target);
}

// Smoothly ease the backlight from the current value to targetUser over
// m_rampDurationMs, writing intermediate hardware values directly (cheap
// sysfs writes) so the change is a glide, not a step. m_brightness (the
// user-facing value) + brightnessChanged fire once at the end.
void DisplayManagerCpp::startBrightnessRamp(double targetUser) {
    if (!m_available || m_backlightDevice.isEmpty())
        return;

    if (!m_rampTimer) {
        m_rampTimer = new QTimer(this);
        m_rampTimer->setInterval(20); // ~50 Hz — smooth to the eye
        connect(m_rampTimer, &QTimer::timeout, this, &DisplayManagerCpp::rampStep);
    }

    m_rampFromUser = m_brightness;
    m_rampToUser   = qBound(0.0, targetUser, 1.0);
    m_rampStartMs  = QDateTime::currentMSecsSinceEpoch();
    if (!m_rampTimer->isActive())
        m_rampTimer->start();
}

void DisplayManagerCpp::rampStep() {
    const qint64 now  = QDateTime::currentMSecsSinceEpoch();
    double       t    = double(now - m_rampStartMs) / double(m_rampDurationMs);
    bool         done = false;
    if (t >= 1.0) {
        t    = 1.0;
        done = true;
    }
    // smoothstep ease
    const double e       = t * t * (3.0 - 2.0 * t);
    const double curUser = m_rampFromUser + (m_rampToUser - m_rampFromUser) * e;

    const int    hwVal =
        qBound(1, static_cast<int>(brightnessUserToHw(curUser) * m_maxBrightness), m_maxBrightness);
    QFile f(QStringLiteral("/sys/class/backlight/%1/brightness").arg(m_backlightDevice));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QByteArray::number(hwVal) + "\n");
        f.close();
    }

    if (done) {
        m_rampTimer->stop();
        m_brightness = m_rampToUser;
        emit brightnessChanged();
    }
}

// A lightweight, call-scoped backlight blank — NOT the deep-idle Doze
// (no CRTC teardown, no lock, no app freeze). The user moving the phone
// to/from their ear must toggle the panel instantly and repeatedly, so
// this only powers the backlight LED down/up. Owned by
// TelephonyIntegration (gated on active-call + proximity).
void DisplayManagerCpp::setCallProximityBlank(bool blank) {
    if (m_proximityBlanked == blank)
        return;
    if (m_backlightDevice.isEmpty())
        return;
    m_proximityBlanked = blank;

    QFile blPower(QStringLiteral("/sys/class/backlight/%1/bl_power").arg(m_backlightDevice));
    if (blPower.open(QIODevice::WriteOnly)) {
        blPower.write(blank ? "4\n" : "0\n");
        blPower.close();
    }
    if (!blank) {
        // Restore the pre-blank duty (through the visible floor).
        const int target =
            qBound(1, static_cast<int>(brightnessUserToHw(m_brightness) * m_maxBrightness),
                   m_maxBrightness);
        QFile br(QStringLiteral("/sys/class/backlight/%1/brightness").arg(m_backlightDevice));
        if (br.open(QIODevice::WriteOnly)) {
            br.write(QByteArray::number(target) + "\n");
            br.close();
        }
    }
}

void DisplayManagerCpp::setRotationLock(bool locked) {
    if (m_rotationLocked == locked)
        return;

    m_rotationLocked = locked;
    emit rotationLockedChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Rotation lock" << (locked ? "enabled" : "disabled");

    if (!m_rotationManager) {
        qWarning() << "[DisplayManagerCpp] No RotationManager available";
        return;
    }

    if (locked) {
        QString ori = m_rotationManager->currentOrientation();
        m_rotationManager->lockOrientation(ori);
        qInfo() << "[DisplayManagerCpp] Orientation locked to" << ori;
    } else {
        m_rotationManager->unlockOrientation();
        qInfo() << "[DisplayManagerCpp] Orientation unlocked";
    }
}

void DisplayManagerCpp::setScreenTimeout(int seconds) {
    if (m_screenTimeout == seconds) {
        return;
    }

    m_screenTimeout = seconds;
    emit screenTimeoutChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Screen timeout set to" << seconds << "seconds";
}

QString DisplayManagerCpp::screenTimeoutString() const {
    if (m_screenTimeout == 0) {
        return "Never";
    } else if (m_screenTimeout < 60) {
        return QString("%1 seconds").arg(m_screenTimeout);
    } else if (m_screenTimeout < 3600) {
        int minutes = m_screenTimeout / 60;
        return QString("%1 minute%2").arg(minutes).arg(minutes > 1 ? "s" : "");
    } else {
        int hours = m_screenTimeout / 3600;
        return QString("%1 hour%2").arg(hours).arg(hours > 1 ? "s" : "");
    }
}

void DisplayManagerCpp::loadSettings() {
    QSettings s;
    s.beginGroup("displayManager");
    m_autoBrightnessEnabled = s.value("autoBrightness", m_autoBrightnessEnabled).toBool();
    m_rotationLocked        = s.value("rotationLocked", m_rotationLocked).toBool();
    m_screenTimeout         = s.value("screenTimeoutSeconds", m_screenTimeout).toInt();
    m_nightLightEnabled     = s.value("nightLightEnabled", m_nightLightEnabled).toBool();
    m_nightLightTemperature = s.value("nightLightTemperature", m_nightLightTemperature).toInt();
    m_nightLightSchedule    = s.value("nightLightSchedule", m_nightLightSchedule).toString();
    const QStringList off =
        s.value("adaptiveBrightnessOffsets").toString().split(',', Qt::SkipEmptyParts);
    for (int i = 0; i < kAdaptAnchors && i < off.size(); ++i)
        m_ltOffset[i] = qBound(-0.4, off.at(i).toDouble(), 0.4);
    s.endGroup();
    qDebug() << "[DisplayManagerCpp] Settings loaded (timeout=" << m_screenTimeout
             << "rotationLocked=" << m_rotationLocked << ")";
}

void DisplayManagerCpp::saveSettings() {
    QSettings s;
    s.beginGroup("displayManager");
    s.setValue("autoBrightness", m_autoBrightnessEnabled);
    s.setValue("rotationLocked", m_rotationLocked);
    s.setValue("screenTimeoutSeconds", m_screenTimeout);
    s.setValue("nightLightEnabled", m_nightLightEnabled);
    s.setValue("nightLightTemperature", m_nightLightTemperature);
    s.setValue("nightLightSchedule", m_nightLightSchedule);
    QStringList off;
    off.reserve(kAdaptAnchors);
    for (double o : m_ltOffset)
        off << QString::number(o, 'f', 4);
    s.setValue("adaptiveBrightnessOffsets", off.join(','));
    s.endGroup();
    s.sync();
    qDebug() << "[DisplayManagerCpp] Settings saved";
}

void DisplayManagerCpp::setNightLightEnabled(bool enabled) {
    if (m_nightLightEnabled == enabled) {
        return;
    }

    m_nightLightEnabled = enabled;
    emit nightLightEnabledChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Night Light" << (enabled ? "enabled" : "disabled") << "at"
            << m_nightLightTemperature << "K";
}

void DisplayManagerCpp::setNightLightTemperature(int temperature) {

    temperature = qBound(2700, temperature, 6500);

    if (m_nightLightTemperature == temperature) {
        return;
    }

    m_nightLightTemperature = temperature;
    emit nightLightTemperatureChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Night Light temperature set to" << temperature << "K";
}

void DisplayManagerCpp::setNightLightSchedule(const QString &schedule) {
    if (m_nightLightSchedule == schedule) {
        return;
    }

    m_nightLightSchedule = schedule;
    emit nightLightScheduleChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Night Light schedule:" << schedule;
}

void DisplayManagerCpp::setScreenState(bool on) {
    // Order matters. The Qt eglfs_kms backend does NOT inspect DPMS state
    // before calling drmModePageFlip; if a flip is in flight when the
    // platform screen goes to PowerStateOff, the flip lands on a sleeping
    // CRTC and the driver returns EINVAL ("Could not queue DRM page flip on
    // screen Virtual1 (Invalid argument)"). On virtio-gpu the wedge is
    // permanent until DPMS turns back on, but Marathon's render loop will
    // keep trying to flip into the dead CRTC every frame.
    //
    // Suspend the compositor's render thread before powering the CRTC down,
    // and bring the CRTC back up before resuming the compositor.

    // ORDER MATTERS relative to the compositor's CRTC power state.
    // screenStateChanged (emitted below) is wired — via a synchronous QML
    // .connect — to WaylandCompositor::setCompositorActive, which toggles
    // the CRTC ACTIVE property. So by the time `emit` returns, the CRTC is
    // already on (wake) or off (doze).
    //
    //   Doze  (on=false): power the backlight LED DOWN first, THEN let the
    //                     compositor disable the CRTC.
    //   Wake  (on=true):  let the compositor enable the CRTC first, THEN
    //                     re-assert the backlight (see forceBacklightOn()).
    //
    // Getting this backwards is what left the panel rendering-but-dark: a
    // bl_power/brightness write that lands while the display power domain
    // is still gated (deep-idle Doze, CRTC ACTIVE=0) is silently dropped,
    // so the LED stays at 0% duty even though sysfs reads back healthy.
    if (!on && !m_backlightDevice.isEmpty()) {
        QFile blPower(QStringLiteral("/sys/class/backlight/%1/bl_power").arg(m_backlightDevice));
        if (blPower.open(QIODevice::WriteOnly)) {
            blPower.write("4\n"); // FB_BLANK_POWERDOWN
            blPower.close();
        } else {
            qWarning() << "[DisplayManagerCpp] cannot open" << blPower.fileName()
                       << "for write — udev rule missing?";
#if MARATHON_HAVE_QT_GUI_PRIVATE
            QPlatformScreen *platformScreen = QGuiApplication::primaryScreen()->handle();
            if (platformScreen) {
                QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
                platformScreen->setPowerState(QPlatformScreen::PowerStateOff);
            }
#endif
        }
    }

    emit screenStateChanged(on);

    // Wake: the CRTC is now powered on (ACTIVE=1 ran synchronously above).
    // Re-assert the backlight in the correct order — this is the fix for
    // the dark-panel-on-wake wedge.
    if (on && !m_backlightDevice.isEmpty()) {
        forceBacklightOn();
        // Self-heal the dark-panel-on-wake race. If the CRTC re-enable and
        // the backlight write above race (the domain-gated write is silently
        // dropped, per forceBacklightOn's comment), the panel stays dark with
        // no retry -- the exact "power key fires but screen doesn't wake"
        // signature. Verify shortly after and re-assert if still dark. Only
        // fires work when the panel FAILED to light, so the happy path is
        // one cheap sysfs read.
        m_wakeVerifyTries = 3;
        if (!m_wakeVerifyTimer) {
            m_wakeVerifyTimer = new QTimer(this);
            m_wakeVerifyTimer->setSingleShot(true);
            m_wakeVerifyTimer->setInterval(120);
            connect(m_wakeVerifyTimer, &QTimer::timeout, this, &DisplayManagerCpp::verifyWakeLit);
        }
        m_wakeVerifyTimer->start();
    } else if (!on && m_wakeVerifyTimer) {
        // Going back to sleep -- cancel any pending wake re-assert.
        m_wakeVerifyTimer->stop();
        m_wakeVerifyTries = 0;
    }

    if (m_powerManager) {
        if (on) {
            m_powerManager->acquireWakelock("display");
            qInfo() << "[DisplayManagerCpp] Acquired display wakelock";
        } else {
            m_powerManager->releaseWakelock("display");
            qInfo() << "[DisplayManagerCpp] Released display wakelock";
        }
    }
}

void DisplayManagerCpp::verifyWakeLit() {
    if (m_backlightDevice.isEmpty())
        return;

    // bl_power == "0" (FB_BLANK_UNBLANK) means the panel actually lit.
    // Anything else (4 == FB_BLANK_POWERDOWN, latched) means the wake write
    // did not take -- re-assert the backlight until it holds or we give up.
    QByteArray state;
    QFile      blPower(QStringLiteral("/sys/class/backlight/%1/bl_power").arg(m_backlightDevice));
    if (blPower.open(QIODevice::ReadOnly)) {
        state = blPower.readAll().trimmed();
        blPower.close();
    }
    if (state == "0")
        return; // lit -- wake succeeded

    if (m_wakeVerifyTries-- > 0) {
        qWarning() << "[DisplayManagerCpp] wake: panel still dark (bl_power=" << state
                   << ") -- re-asserting backlight, tries left" << m_wakeVerifyTries;
        forceBacklightOn();
        if (m_wakeVerifyTimer)
            m_wakeVerifyTimer->start();
    } else {
        qWarning() << "[DisplayManagerCpp] wake: panel failed to light after retries";
    }
}

void DisplayManagerCpp::setupBrightnessMonitoring() {

    if (!m_backlightDevice.isEmpty()) {
        QString actualPath =
            QString("/sys/class/backlight/%1/actual_brightness").arg(m_backlightDevice);
        QString reqPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);

        QFileSystemWatcher *watcher = new QFileSystemWatcher(this);
        watcher->addPath(actualPath);
        watcher->addPath(reqPath);

        connect(watcher, &QFileSystemWatcher::fileChanged, this,
                &DisplayManagerCpp::onExternalBrightnessChanged);
        qInfo() << "[DisplayManagerCpp] Monitoring sysfs paths:" << actualPath << "and" << reqPath;
    }

    QDBusConnection bus = QDBusConnection::sessionBus();
    bool            connected =
        bus.connect("org.gnome.SettingsDaemon.Power", "/org/gnome/SettingsDaemon/Power",
                    "org.freedesktop.DBus.Properties", "PropertiesChanged", this,
                    SLOT(onDBusPropertiesChanged(QString, QVariantMap, QStringList)));

    if (connected) {
        qInfo() << "[DisplayManagerCpp] Connected to GSD Power properties changes";
    } else {
        qWarning() << "[DisplayManagerCpp] Failed to connect to GSD Power properties";
    }
}

void DisplayManagerCpp::onExternalBrightnessChanged() {

    if (m_backlightDevice.isEmpty())
        return;

    QString actualPath =
        QString("/sys/class/backlight/%1/actual_brightness").arg(m_backlightDevice);
    QFile actualFile(actualPath);
    int   actualVal = -1;

    if (actualFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&actualFile);
        actualVal = in.readAll().trimmed().toInt();
        actualFile.close();
    }

    QString reqPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);
    QFile   reqFile(reqPath);
    int     reqVal = -1;

    if (reqFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&reqFile);
        reqVal = in.readAll().trimmed().toInt();
        reqFile.close();
    }

    double currentBrightness = m_brightness;
    bool   changed           = false;

    // Hardware values are in the remapped [floor,1] domain; convert back
    // to the user's [0,1] domain before comparing against m_brightness.
    if (actualVal != -1) {
        double actualNorm = brightnessHwToUser((double)actualVal / m_maxBrightness);
        if (qAbs(actualNorm - m_brightness) > 0.02) {
            currentBrightness = actualNorm;
            changed           = true;
            qDebug() << "[DisplayManagerCpp] Hardware brightness changed (actual):" << actualVal;
        }
    }

    if (!changed && reqVal != -1) {
        double reqNorm = brightnessHwToUser((double)reqVal / m_maxBrightness);
        if (qAbs(reqNorm - m_brightness) > 0.02) {
            currentBrightness = reqNorm;
            changed           = true;
            qDebug() << "[DisplayManagerCpp] Hardware brightness changed (requested):" << reqVal;
        }
    }

    if (changed) {
        m_brightness = currentBrightness;
        emit brightnessChanged();
    }
}

void DisplayManagerCpp::onDBusPropertiesChanged(const QString     &interface,
                                                const QVariantMap &changed,
                                                const QStringList &invalidated) {
    Q_UNUSED(invalidated)

    if (interface == "org.gnome.SettingsDaemon.Power.Screen") {
        if (changed.contains("Brightness")) {
            int    gsdBrightness = changed["Brightness"].toInt();

            double newBrightness = gsdBrightness / 100.0;

            if (qAbs(newBrightness - m_brightness) > 0.01) {
                qInfo() << "[DisplayManagerCpp] GSD Brightness changed to:" << gsdBrightness;
                m_brightness = newBrightness;
                emit brightnessChanged();
            }
        }
    }
}
