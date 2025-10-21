#include "displaymanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QProcess>

DisplayManagerCpp::DisplayManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_maxBrightness(100)
{
    qDebug() << "[DisplayManagerCpp] Initializing";
    
    if (Platform::hasBacklightControl()) {
        m_available = detectBacklightDevice();
        if (m_available) {
            qInfo() << "[DisplayManagerCpp] Backlight control available:" << m_backlightDevice;
        } else {
            qInfo() << "[DisplayManagerCpp] No backlight devices found";
        }
    } else {
        qInfo() << "[DisplayManagerCpp] Backlight control not available on this platform";
    }
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

void DisplayManagerCpp::setBrightness(double brightness)
{
    if (!m_available) {
        qDebug() << "[DisplayManagerCpp] Backlight control not available";
        return;
    }
    
    // Clamp brightness to 0.0-1.0
    brightness = qBound(0.0, brightness, 1.0);
    
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
    } else {
        qDebug() << "[DisplayManagerCpp] Failed to set brightness: permission denied";
    }
}

