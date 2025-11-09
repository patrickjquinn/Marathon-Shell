#include "displaymanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QProcess>
#include <QtMath>

DisplayManagerCpp::DisplayManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_maxBrightness(100)
    , m_autoBrightnessEnabled(false)
    , m_rotationLocked(false)
    , m_screenTimeout(300) // 5 minutes default
    , m_brightness(0.5)
    , m_nightLightEnabled(false)
    , m_nightLightTemperature(3400) // Warm default (between 2700-6500K)
    , m_nightLightSchedule("off")
{
    qDebug() << "[DisplayManagerCpp] Initializing";
    
    if (Platform::hasBacklightControl()) {
        m_available = detectBacklightDevice();
        if (m_available) {
            qInfo() << "[DisplayManagerCpp] Backlight control available:" << m_backlightDevice;
            m_brightness = getBrightness();
        } else {
            qInfo() << "[DisplayManagerCpp] No backlight devices found";
        }
    } else {
        qInfo() << "[DisplayManagerCpp] Backlight control not available on this platform";
    }
    
    loadSettings();
}

bool DisplayManagerCpp::detectBacklightDevice()
{
    QDir backlightDir("/sys/class/backlight");
    if (!backlightDir.exists()) {
        return false;
    }
    
    QStringList devices = backlightDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (devices.isEmpty()) {
        return false;
    }
    
    // Use the first backlight device found
    m_backlightDevice = devices.first();
    QString maxBrightnessPath = QString("/sys/class/backlight/%1/max_brightness").arg(m_backlightDevice);
    
    QFile maxFile(maxBrightnessPath);
    if (maxFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString value = maxFile.readAll().trimmed();
        m_maxBrightness = value.toInt();
        maxFile.close();
        qInfo() << "[DisplayManagerCpp] Detected backlight device:" << m_backlightDevice 
                << "max brightness:" << m_maxBrightness;
        return true;
    }
    
    return false;
}

double DisplayManagerCpp::getBrightness()
{
    if (!m_available) {
        return 0.5; // Default 50%
    }
    
    QString brightnessPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);
    
    QFile file(brightnessPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString value = file.readAll().trimmed();
        int currentValue = value.toInt();
        file.close();
        
        // Convert to 0.0-1.0 range
        double brightness = static_cast<double>(currentValue) / m_maxBrightness;
        qDebug() << "[DisplayManagerCpp] Current brightness:" << currentValue << "/" << m_maxBrightness << "=" << (brightness * 100) << "%";
        return brightness;
    }
    
    qWarning() << "[DisplayManagerCpp] Failed to read brightness";
    return 0.5; // Default fallback
}

void DisplayManagerCpp::setBrightness(double brightness)
{
    if (!m_available) {
        qDebug() << "[DisplayManagerCpp] Backlight control not available";
        return;
    }
    
    // Clamp brightness to 0.0-1.0
    brightness = qBound(0.0, brightness, 1.0);
    
    if (qAbs(m_brightness - brightness) < 0.01) {
        return; // No significant change
    }
    
    m_brightness = brightness;
    
    int brightnessValue = static_cast<int>(brightness * m_maxBrightness);
    
    QString brightnessPath = QString("/sys/class/backlight/%1/brightness").arg(m_backlightDevice);
    
    // Try using systemd-logind SetBrightness method first (requires no root)
    if (Platform::hasLogind()) {
        QProcess process;
        process.start("busctl", {
            "call",
            "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session",
            "SetBrightness",
            "ssu",
            "backlight",
            m_backlightDevice,
            QString::number(brightnessValue)
        });
        
        if (process.waitForFinished(1000) && process.exitCode() == 0) {
            qDebug() << "[DisplayManagerCpp] Set brightness to:" << brightnessValue 
                     << "(" << (brightness * 100) << "%) via logind";
            emit brightnessChanged();
            return;
        }
    }
    
    // Fallback: Try direct sysfs write (requires permissions)
    QFile file(brightnessPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << brightnessValue;
        file.close();
        qDebug() << "[DisplayManagerCpp] Set brightness to:" << brightnessValue 
                 << "(" << (brightness * 100) << "%) via sysfs";
        emit brightnessChanged();
    } else {
        qDebug() << "[DisplayManagerCpp] Failed to set brightness: permission denied";
    }
}

void DisplayManagerCpp::setAutoBrightness(bool enabled)
{
    if (m_autoBrightnessEnabled == enabled) {
        return;
    }
    
    m_autoBrightnessEnabled = enabled;
    emit autoBrightnessEnabledChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Auto-brightness" << (enabled ? "enabled" : "disabled");
    
    // TODO: Implement actual auto-brightness using ambient light sensor
    // For now, this just tracks the preference
}

void DisplayManagerCpp::setRotationLock(bool locked)
{
    if (m_rotationLocked == locked) {
        return;
    }
    
    m_rotationLocked = locked;
    emit rotationLockedChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Rotation lock" << (locked ? "enabled" : "disabled");
}

void DisplayManagerCpp::setScreenTimeout(int seconds)
{
    if (m_screenTimeout == seconds) {
        return;
    }
    
    m_screenTimeout = seconds;
    emit screenTimeoutChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Screen timeout set to" << seconds << "seconds";
}

QString DisplayManagerCpp::screenTimeoutString() const
{
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

void DisplayManagerCpp::loadSettings()
{
    // Load from SettingsManager or QSettings
    // For now, use defaults - will be integrated with SettingsManager later
    qDebug() << "[DisplayManagerCpp] Settings loaded";
}

void DisplayManagerCpp::saveSettings()
{
    // Save to SettingsManager or QSettings
    // For now, just log - will be integrated with SettingsManager later
    qDebug() << "[DisplayManagerCpp] Settings saved";
}

void DisplayManagerCpp::setNightLightEnabled(bool enabled)
{
    if (m_nightLightEnabled == enabled) {
        return;
    }
    
    m_nightLightEnabled = enabled;
    emit nightLightEnabledChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Night Light" << (enabled ? "enabled" : "disabled") 
            << "at" << m_nightLightTemperature << "K";
    
    // TODO: Apply color temperature filter
    // This would require compositor-level color correction or QML shader
}

void DisplayManagerCpp::setNightLightTemperature(int temperature)
{
    // Clamp to valid range (2700K = very warm, 6500K = daylight)
    temperature = qBound(2700, temperature, 6500);
    
    if (m_nightLightTemperature == temperature) {
        return;
    }
    
    m_nightLightTemperature = temperature;
    emit nightLightTemperatureChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Night Light temperature set to" << temperature << "K";
    
    // TODO: Apply new color temperature if enabled
}

void DisplayManagerCpp::setNightLightSchedule(const QString& schedule)
{
    if (m_nightLightSchedule == schedule) {
        return;
    }
    
    m_nightLightSchedule = schedule;
    emit nightLightScheduleChanged();
    saveSettings();
    
    qInfo() << "[DisplayManagerCpp] Night Light schedule:" << schedule;
    
    // TODO: Implement schedule logic (sunset/sunrise based on location, custom times)
}

void DisplayManagerCpp::setScreenState(bool on)
{
    QString blankPath = "/sys/class/graphics/fb0/blank";
    QFile file(blankPath);
    
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream stream(&file);
        // 0 = unblank (screen on), 4 = powerdown (screen off)
        stream << (on ? "0" : "4");
        file.close();
        qInfo() << "[DisplayManagerCpp] Screen" << (on ? "ON" : "OFF") << "via" << blankPath;
    } else {
        // Silently fail in VM/desktop environments where framebuffer doesn't exist
        // This is expected behavior and will work on real hardware
        qDebug() << "[DisplayManagerCpp] Framebuffer control not available (expected in VM/desktop)";
    }
}

