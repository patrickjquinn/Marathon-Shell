#ifndef PLATFORM_H
#define PLATFORM_H

#include <QString>
#include <QProcess>
#include <QFile>
#include <QDebug>

namespace Platform {

    inline bool isLinux() {
#ifdef Q_OS_LINUX
        return true;
#else
        return false;
#endif
    }

    inline bool isMacOS() {
#ifdef Q_OS_MACOS
        return true;
#else
        return false;
#endif
    }

    inline bool hasSystemd() {
        if (!isLinux())
            return false;
        return QFile::exists("/run/systemd/system");
    }

    inline bool hasLogind() {
        return hasSystemd() && QFile::exists("/run/systemd/seats");
    }

    inline bool hasPulseAudio() {
        if (!isLinux())
            return false;
        QProcess process;
        process.start("pactl", {"--version"});
        process.waitForFinished(1000);
        return process.exitCode() == 0;
    }

    inline bool hasBacklightControl() {
        if (!isLinux())
            return false;
        return QFile::exists("/sys/class/backlight");
    }

    inline bool hasIIOSensors() {
        if (!isLinux())
            return false;
        return QFile::exists("/sys/bus/iio/devices");
    }

    inline bool hasHardwareKeyboard() {
        if (qEnvironmentVariableIsSet("MARATHON_FORCE_VKB")) {
            qInfo() << "[Platform] MARATHON_FORCE_VKB set - forcing virtual keyboard";
            return false;
        }

        if (!isLinux())
            return isMacOS();

        QFile devicesFile("/proc/bus/input/devices");
        if (!devicesFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            qWarning() << "[Platform] Could not open /proc/bus/input/devices";
            return false;
        }

        QString content = QString::fromUtf8(devicesFile.readAll());
        devicesFile.close();

        QStringList lines = content.split('\n');
        QString     currentDeviceName;
        QString     currentHandlers;
        bool        hasKeyboardEV = false;

        for (const QString &line : lines) {
            if (line.trimmed().isEmpty()) {
                if (!currentDeviceName.isEmpty() && hasKeyboardEV) {
                    if (currentHandlers.contains("kbd", Qt::CaseInsensitive)) {
                        qInfo() << "[Platform] Hardware keyboard detected:" << currentDeviceName;
                        return true;
                    }
                }
                currentDeviceName.clear();
                currentHandlers.clear();
                hasKeyboardEV = false;
                continue;
            }

            if (line.startsWith("N: Name=")) {
                currentDeviceName = line.mid(9).trimmed().remove('"');
            } else if (line.startsWith("H: Handlers=")) {
                currentHandlers = line.mid(12).trimmed();
            } else if (line.startsWith("B: EV=")) {
                QString evBitmap = line.mid(6).trimmed();
                if (evBitmap.contains("120013") || evBitmap.contains("12000f"))
                    hasKeyboardEV = true;
            } else if (line.startsWith("B: KEY=") && hasKeyboardEV) {
                QString keyBitmap = line.mid(7).trimmed();
                if (keyBitmap.length() <= 40)
                    hasKeyboardEV = false;
            }
        }

        if (!currentDeviceName.isEmpty() && hasKeyboardEV &&
            currentHandlers.contains("kbd", Qt::CaseInsensitive)) {
            qInfo() << "[Platform] Hardware keyboard detected:" << currentDeviceName;
            return true;
        }

        qInfo() << "[Platform] No hardware keyboard detected";
        return false;
    }

}

#endif
