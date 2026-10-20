#include "displaymanagercpp.h"
#include "powermanagercpp.h"
#include "rotationmanager.h"
#include "sensormanagercpp.h"
#include "platform.h"
#include "deviceprofile.h"
#include "marathon-shell-native/src/backlight.cxxqt.h"
#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QTextStream>
#include <QEventLoop>
#include <QProcess>
#include <QtMath>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QTimer>
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
// [floor, 1.0]: slider 0% -> ~floor real duty, slider 100% -> 100%. The
// floor is a per-device panel trait (L5 default 0.28), sourced from
// DeviceProfile so an overlay can declare its own. All hardware writes go
// through brightnessUserToHw() and all sysfs reads come back through
// brightnessHwToUser() so the slider still reflects the user's 0..100.
static inline double minVisibleBrightness() {
    return DeviceProfile::instance().brightnessFloor();
}

static inline double brightnessUserToHw(double user) {
    const double floor = minVisibleBrightness();
    user               = qBound(0.0, user, 1.0);
    return floor + (1.0 - floor) * user;
}

static inline double brightnessHwToUser(double hw) {
    const double floor = minVisibleBrightness();
    return qBound(0.0, (hw - floor) / (1.0 - floor), 1.0);
}

DisplayManagerCpp::DisplayManagerCpp(PowerManagerCpp *powerManager,
                                     RotationManager *rotationManager, QObject *parent,
                                     const QString &backlightDir)
    : QObject(parent)
    , m_available(false)
    , m_backlightDir(backlightDir)
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

    if (QFile::exists(m_backlightDir)) {
        m_available = detectBacklightDevice();
        if (m_available) {
            qInfo() << "[DisplayManagerCpp] Backlight control available:" << m_backlightDevice;
            m_brightness   = readBrightness();
            m_sysfsWritable = QFileInfo(backlightFile("brightness")).isWritable();
            m_backlight     = new Backlight();
            m_backlight->setParent(this);
            m_backlight->setDevice(m_backlightDir + u'/' + m_backlightDevice);
            connect(m_backlight, &Backlight::levelReadBack, this, &DisplayManagerCpp::onLevelReadBack);
            connect(m_backlight, &Backlight::litChecked, this, [this](bool lit) {
                if (lit)
                    return;
                if (m_wakeVerifyTries-- > 0) {
                    qWarning() << "[DisplayManagerCpp] wake: panel still dark -- re-asserting backlight,"
                               << "tries left" << m_wakeVerifyTries;
                    forceBacklightOn();
                    if (m_wakeVerifyTimer)
                        m_wakeVerifyTimer->start();
                } else {
                    qWarning() << "[DisplayManagerCpp] wake: panel failed to light after retries";
                }
            });

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
    QDir backlightDir(m_backlightDir);
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

    QString maxBrightnessPath = backlightFile("max_brightness");

    QFile   maxFile(maxBrightnessPath);
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

// The nearest hardware level, never a truncated one: the HackberryPi's
// backlight has 10 levels, and truncating left a +10% step on the same one.
int DisplayManagerCpp::backlightLevel(double user) const {
    return qBound(1, qRound(brightnessUserToHw(user) * m_maxBrightness), m_maxBrightness);
}

double DisplayManagerCpp::brightness() const {
    return m_brightness;
}

// The LED's power cycle runs on the I/O thread (Backlight::forceOn): after
// the display domain gated in deep-idle Doze, a pwm-backlight duty can stay
// latched at 0, and a plain bl_power=0 leaves it dark. Waking to a lit
// panel is non-negotiable, at the user's level through the visible floor.
void DisplayManagerCpp::forceBacklightOn() {
    if (m_backlight)
        m_backlight->forceOn(backlightLevel(m_brightness));
}

double DisplayManagerCpp::getBrightness() {
    return m_brightness;
}

// Once, at startup; afterwards the cache follows every write and read-back.
double DisplayManagerCpp::readBrightness() const {
    if (!m_available) {
        return 0.5;
    }

    QString brightnessPath = backlightFile("brightness");

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
    if (m_rampTimer)
        m_rampTimer->stop();

    // Drive the hardware with the remapped value so 0% still lights the
    // panel (~28% duty), and keep the USER value of the level it lands on.
    const int brightnessValue = backlightLevel(brightness);
    m_brightness = brightnessHwToUser(static_cast<double>(brightnessValue) / m_maxBrightness);

    // The device's udev rule makes the sysfs node writable; GSD (desktop runs)
    // and logind are the fallbacks. Either way asynchronously: a slider drag
    // calls this per step.
    if (m_sysfsWritable && m_backlight) {
        m_backlight->setLevel(brightnessValue);
        emit brightnessChanged();
        return;
    }
    setBrightnessOverDBus(brightnessValue);
}

void DisplayManagerCpp::setBrightnessOverDBus(int brightnessValue) {
    QDBusMessage gsd = QDBusMessage::createMethodCall("org.gnome.SettingsDaemon.Power",
                                                      "/org/gnome/SettingsDaemon/Power",
                                                      "org.freedesktop.DBus.Properties", "Set");
    gsd << QStringLiteral("org.gnome.SettingsDaemon.Power.Screen") << QStringLiteral("Brightness")
        << QVariant::fromValue(QDBusVariant(qRound(brightnessValue * 100.0 / m_maxBrightness)));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(gsd), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, brightnessValue](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (!w->isError()) {
                    emit brightnessChanged();
                    return;
                }
                if (!Platform::hasLogind()) {
                    qWarning() << "[DisplayManagerCpp] Failed to set brightness:" << w->error().message();
                    return;
                }
                QDBusMessage logind = QDBusMessage::createMethodCall(
                    "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                    "org.freedesktop.login1.Session", "SetBrightness");
                logind << QStringLiteral("backlight") << m_backlightDevice << uint(brightnessValue);
                auto *set = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(logind), this);
                connect(set, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *l) {
                    l->deleteLater();
                    if (l->isError())
                        qWarning() << "[DisplayManagerCpp] Failed to set brightness:" << l->error().message();
                    else
                        emit brightnessChanged();
                });
            });
}

bool DisplayManagerCpp::rotationAvailable() const {
    return m_rotationManager && m_rotationManager->available();
}

bool DisplayManagerCpp::lightSensorAvailable() const {
    return m_sensorManager && m_sensorManager->lightAvailable();
}

void DisplayManagerCpp::setSensorManager(SensorManagerCpp *sensorManager) {
    m_sensorManager = sensorManager;
    if (m_sensorManager && m_autoBrightnessEnabled) {
        connect(m_sensorManager, &SensorManagerCpp::ambientLightChanged, this,
                &DisplayManagerCpp::onAmbientLightChanged);
    }
}

void DisplayManagerCpp::setAutoBrightness(bool enabled) {
    if (enabled && !lightSensorAvailable()) {
        qInfo() << "[DisplayManagerCpp] No light sensor: auto-brightness stays off";
        return;
    }
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
// A smoothstep ease over m_rampDurationMs, as the hardware levels it passes:
// a 10-level backlight is written four or five times, not thirty.
void DisplayManagerCpp::startBrightnessRamp(double targetUser) {
    if (!m_available || !m_backlight)
        return;
    constexpr int kStepMs  = 20;
    const double  from     = m_brightness;
    m_rampToUser           = qBound(0.0, targetUser, 1.0);
    QList<int>    levels;
    const int     steps = m_rampDurationMs / kStepMs;
    for (int i = 1; i <= steps; ++i) {
        const double t = double(i) / steps;
        levels.append(backlightLevel(from + (m_rampToUser - from) * t * t * (3.0 - 2.0 * t)));
    }
    m_backlight->ramp(levels, kStepMs);

    if (!m_rampTimer) {
        m_rampTimer = new QTimer(this);
        m_rampTimer->setSingleShot(true);
        connect(m_rampTimer, &QTimer::timeout, this, [this] {
            m_brightness = m_rampToUser;
            emit brightnessChanged();
        });
    }
    m_rampTimer->start(m_rampDurationMs);
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
    if (blank)
        qWarning() << "[DisplayManagerCpp] screen off by proximity during a call";

    // Unblanking restores the duty from before, through the visible floor.
    if (m_backlight)
        m_backlight->blank(blank, backlightLevel(m_brightness));
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

void DisplayManagerCpp::setScreenState(bool on, const QString &reason) {
    if (!on)
        qWarning().noquote() << "[DisplayManagerCpp] screen off by" << reason;

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
        QFile blPower(backlightFile("bl_power"));
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

    if (m_screenOn != on) {
        m_screenOn = on;
        emit screenOnChanged(on);
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

// bl_power 0 means the panel lit; Backlight answers with litChecked, which
// re-asserts the backlight a few times if it didn't.
void DisplayManagerCpp::verifyWakeLit() {
    if (m_backlight)
        m_backlight->checkLit();
}

void DisplayManagerCpp::setupBrightnessMonitoring() {

    if (!m_backlightDevice.isEmpty()) {
        QString             actualPath = backlightFile("actual_brightness");
        QString             reqPath    = backlightFile("brightness");

        QFileSystemWatcher *watcher = new QFileSystemWatcher(this);
        watcher->addPath(actualPath);
        watcher->addPath(reqPath);

        // Read back on the I/O thread; only a level the shell didn't write answers.
        connect(watcher, &QFileSystemWatcher::fileChanged, m_backlight, &Backlight::refresh);
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

void DisplayManagerCpp::onLevelReadBack(int actualVal, int reqVal) {
    if (m_maxBrightness <= 0)
        return;
    // Hardware values are in the remapped [floor,1] domain; compare in the
    // user's [0,1] domain.
    for (const int level : {reqVal, actualVal}) {
        if (level < 0)
            continue;
        const double user = brightnessHwToUser(double(level) / m_maxBrightness);
        if (qAbs(user - m_brightness) > 0.02) {
            m_brightness = user;
            emit brightnessChanged();
            return;
        }
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
