#ifndef PLATFORM_H
#define PLATFORM_H

#include <QString>
#include <QProcess>
#include <QFile>

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
    if (!isLinux()) return false;
    return QFile::exists("/run/systemd/system");
}

inline bool hasLogind() {
    return hasSystemd() && QFile::exists("/run/systemd/seats");
}

inline bool hasPulseAudio() {
    if (!isLinux()) return false;
    QProcess process;
    process.start("pactl", {"--version"});
    process.waitForFinished(1000);
    return process.exitCode() == 0;
}

inline bool hasBacklightControl() {
    if (!isLinux()) return false;
    return QFile::exists("/sys/class/backlight");
}

inline bool hasIIOSensors() {
    if (!isLinux()) return false;
    return QFile::exists("/sys/bus/iio/devices");
}

} // namespace Platform

#endif // PLATFORM_H

