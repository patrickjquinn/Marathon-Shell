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

void DisplayManagerCpp::onAmbientLightChanged() {
    if (!m_autoBrightnessEnabled || !m_sensorManager)
        return;

    int lux = m_sensorManager->ambientLight();
    // Map lux to brightness: 0 lux → 0.05, ~500 lux → 0.5, ~10000+ lux → 1.0
    double target = qBound(0.05, 0.05 + 0.95 * (qLn(lux + 1.0) / qLn(10001.0)), 1.0);

    if (qAbs(target - m_brightness) > 0.03) {
        qDebug() << "[DisplayManagerCpp] Auto-brightness: lux=" << lux << "→ brightness=" << target;
        setBrightness(target);
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
