#include "displaymanagercpp.h"
#include "powermanagercpp.h"
#include "rotationmanager.h"
#include "platform.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QProcess>
#include <QtMath>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QTimer>
#include <QFileSystemWatcher>
#include <QScreen>
#if MARATHON_HAVE_QT_GUI_PRIVATE
#include <qpa/qplatformscreen.h>
#endif

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

        double brightness = static_cast<double>(currentValue) / m_maxBrightness;
        qDebug() << "[DisplayManagerCpp] Current brightness:" << currentValue << "/"
                 << m_maxBrightness << "=" << (brightness * 100) << "%";
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

    m_brightness = brightness;

    int     brightnessValue = static_cast<int>(brightness * m_maxBrightness);

    QString brightnessPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);

    QDBusMessage    message = QDBusMessage::createMethodCall("org.gnome.SettingsDaemon.Power",
                                                             "/org/gnome/SettingsDaemon/Power",
                                                             "org.freedesktop.DBus.Properties", "Set");

    QList<QVariant> args;
    args << "org.gnome.SettingsDaemon.Power.Screen";
    args << "Brightness";

    int gsdValue = static_cast<int>(brightness * 100.0);
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

void DisplayManagerCpp::setAutoBrightness(bool enabled) {
    if (m_autoBrightnessEnabled == enabled) {
        return;
    }

    m_autoBrightnessEnabled = enabled;
    emit autoBrightnessEnabledChanged();
    saveSettings();

    qInfo() << "[DisplayManagerCpp] Auto-brightness" << (enabled ? "enabled" : "disabled");
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

    qDebug() << "[DisplayManagerCpp] Settings loaded";
}

void DisplayManagerCpp::saveSettings() {

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
#if MARATHON_HAVE_QT_GUI_PRIVATE
    QPlatformScreen *platformScreen = QGuiApplication::primaryScreen()->handle();

    if (platformScreen) {
        platformScreen->setPowerState(on ? QPlatformScreen::PowerStateOn :
                                           QPlatformScreen::PowerStateOff);

        emit screenStateChanged(on);
        qDebug() << "[DisplayManagerCpp] Screen" << (on ? "ON" : "OFF")
                 << "via QPlatformScreen::setPowerState";
    } else {
        qDebug() << "[DisplayManagerCpp] No QPlatformScreen handle found!";
    }
#else
    Q_UNUSED(on);
    qDebug() << "[DisplayManagerCpp] Screen power control disabled (Qt GuiPrivate not enabled)";
#endif

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

    if (actualVal != -1) {
        double actualNorm = (double)actualVal / m_maxBrightness;
        if (qAbs(actualNorm - m_brightness) > 0.02) {
            currentBrightness = actualNorm;
            changed           = true;
            qDebug() << "[DisplayManagerCpp] Hardware brightness changed (actual):" << actualVal;
        }
    }

    if (!changed && reqVal != -1) {
        double reqNorm = (double)reqVal / m_maxBrightness;
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

void DisplayManagerCpp::pollBrightness() {}
