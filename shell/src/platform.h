#ifndef PLATFORM_H
#define PLATFORM_H

#include <QString>
#include <QProcess>
#include <QFile>
#include <QDebug>

/**
 * Platform detection and service availability utilities
 */
namespace Platform {

    // Operating System Detection
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

    // Service Availability Detection
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

    // Hardware Keyboard Detection
    // Uses /proc/bus/input/devices on Linux - most reliable method for kernel-level device detection
    // Reference: Linux Input Subsystem documentation
    inline bool hasHardwareKeyboard() {
        if (!isLinux()) {
            // On macOS, assume desktop setup has keyboard
            // Could be enhanced with IOKit APIs in the future
            return isMacOS();
        }

        // Read /proc/bus/input/devices - contains all input devices registered with kernel
        QFile devicesFile("/proc/bus/input/devices");
        if (!devicesFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            qWarning() << "[Platform] Could not open /proc/bus/input/devices - assuming no "
                          "hardware keyboard";
            return false;
        }

        QString content = QString::fromUtf8(devicesFile.readAll());
        devicesFile.close();

        // Parse device entries
        // Format: I: (Bus info), N: (Name), P: (Physical path), S: (Sysfs path),
        //         U: (Unique identifier), H: (Handlers), B: (Bitmaps for capabilities)
        QStringList lines = content.split('\n');
        QString     currentDeviceName;
        QString     currentHandlers;
        bool        hasKeyboardEV = false;

        for (const QString &line : lines) {
            // Empty line = end of device section
            if (line.trimmed().isEmpty()) {
                // Check if this was a keyboard device
                if (!currentDeviceName.isEmpty() && hasKeyboardEV) {
                    // Verify handlers include kbd (keyboard)
                    if (currentHandlers.contains("kbd", Qt::CaseInsensitive)) {
                        qInfo() << "[Platform] Hardware keyboard detected:" << currentDeviceName;
                        qInfo() << "[Platform] Handlers:" << currentHandlers;
                        return true;
                    }
                }

                // Reset for next device
                currentDeviceName.clear();
                currentHandlers.clear();
                hasKeyboardEV = false;
                continue;
            }

            // Device name
            if (line.startsWith("N: Name=")) {
                currentDeviceName = line.mid(9).trimmed().remove('"');
            }

            // Handlers (e.g., "H: Handlers=kbd event3")
            else if (line.startsWith("H: Handlers=")) {
                currentHandlers = line.mid(12).trimmed();
            }

            // Event capabilities (EV= bitmap)
            // EV=120013 means: EV_KEY(bit 0), EV_REP(bit 1), EV_MSC(bit 4), EV_LED(bit 17)
            // This is the signature of a full keyboard
            else if (line.startsWith("B: EV=")) {
                QString evBitmap = line.mid(6).trimmed();
                // Check for keyboard event capabilities
                // 0x120013 = 1179667 decimal = full keyboard
                // 0x120001 = 1179649 decimal = minimal keyboard
                // 0x12000f = 1179663 decimal = keyboard variant
                if (evBitmap.contains("120013") || evBitmap.contains("12000f")) {
                    hasKeyboardEV = true;
                }
            }

            // Additional validation: KEY bitmap
            // Real keyboards have extensive key ranges (a-z, 0-9, etc.)
            else if (line.startsWith("B: KEY=") && hasKeyboardEV) {
                QString keyBitmap = line.mid(7).trimmed();
                // Keyboards have long key bitmaps (>40 hex chars typically)
                // Power buttons and media keys have short bitmaps
                if (keyBitmap.length() > 40) {
                    // This is likely a full keyboard, not just power/volume buttons
                    continue; // Keep hasKeyboardEV = true
                } else {
                    // Too short - probably not a full keyboard
                    hasKeyboardEV = false;
                }
            }
        }

        // Check last device if file doesn't end with empty line
        if (!currentDeviceName.isEmpty() && hasKeyboardEV &&
            currentHandlers.contains("kbd", Qt::CaseInsensitive)) {
            qInfo() << "[Platform] Hardware keyboard detected:" << currentDeviceName;
            return true;
        }

        qInfo() << "[Platform] No hardware keyboard detected";
        return false;
    }

} // namespace Platform

#endif // PLATFORM_H
