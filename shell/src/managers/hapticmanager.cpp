#include "hapticmanager.h"
#include <QJSEngine>
#include <QQmlEngine>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTimer>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

HapticManager *HapticManager::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new HapticManager(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}
void HapticManager::vibratePatternVariant(const QVariantList &pattern) {
    QList<int> ints;
    ints.reserve(pattern.size());
    for (const QVariant &v : pattern) {
        bool      ok = false;
        const int i  = v.toInt(&ok);
        if (ok)
            ints.append(i);
    }
    vibratePattern(ints);
}

HapticManager::HapticManager(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_enabled(true) {
    qDebug() << "[HapticManager] Initializing";

    m_available = detectVibrator();

    if (m_available) {
        qInfo() << "[HapticManager] Vibrator found at:" << m_vibratorPath;
    } else {
        qInfo() << "[HapticManager] No vibrator hardware detected";
    }
}

bool HapticManager::detectVibrator() {
    // Prefer the evdev force-feedback path. Modern mainline mobile-Linux
    // vibrators (the L5's pwm-vibrator, and most Android-derived boards) expose
    // FF_RUMBLE on an /dev/input/event* node and create NO sysfs LED/
    // timed_output entry — so the legacy sysfs probe below finds nothing and
    // every vibrate() is a silent no-op. Detect FF first.
    if (detectEvdevRumble()) {
        m_useEvdevFf = true;
        return true;
    }

    // Legacy sysfs fallback (Android timed_output / LED-style vibrators).
    QStringList paths = {"/sys/class/leds/vibrator/brightness", "/sys/class/leds/vibrator/activate",
                         "/sys/class/timed_output/vibrator/enable",
                         "/sys/devices/virtual/timed_output/vibrator/enable"};

    for (const QString &path : paths) {
        QFile file(path);
        if (file.exists()) {
            m_vibratorPath = path;
            return true;
        }
    }

    return false;
}

// Scan /dev/input/event* for a device advertising EV_FF / FF_RUMBLE, open it
// R/W, and upload a rumble effect slot we can re-arm per vibrate() call.
bool HapticManager::detectEvdevRumble() {
    QDir inputDir(QStringLiteral("/dev/input"));
    const QStringList events =
        inputDir.entryList(QStringList{QStringLiteral("event*")}, QDir::System);

    for (const QString &ev : events) {
        const QString path = inputDir.absoluteFilePath(ev);
        const int     fd   = ::open(path.toLocal8Bit().constData(), O_RDWR | O_CLOEXEC);
        if (fd < 0)
            continue;

        unsigned long evbits[(EV_MAX + 8 * sizeof(long) - 1) / (8 * sizeof(long))] = {0};
        unsigned long ffbits[(FF_MAX + 8 * sizeof(long) - 1) / (8 * sizeof(long))] = {0};
        auto          testBit = [](int bit, const unsigned long *arr) {
            return (arr[bit / (8 * sizeof(long))] >> (bit % (8 * sizeof(long)))) & 1UL;
        };

        if (::ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits) < 0 || !testBit(EV_FF, evbits) ||
            ::ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ffbits)), ffbits) < 0 ||
            !testBit(FF_RUMBLE, ffbits)) {
            ::close(fd);
            continue;
        }

        // Upload an initial rumble effect; the id is reused/re-armed later.
        struct ff_effect effect;
        std::memset(&effect, 0, sizeof(effect));
        effect.type                      = FF_RUMBLE;
        effect.id                        = -1;
        effect.u.rumble.strong_magnitude = 0xFFFF;
        effect.u.rumble.weak_magnitude   = 0xFFFF;
        effect.replay.length             = 25;
        effect.replay.delay              = 0;
        if (::ioctl(fd, EVIOCSFF, &effect) < 0) {
            ::close(fd);
            continue;
        }

        m_ffFd         = fd;
        m_ffEffectId   = effect.id;
        m_vibratorPath = path;
        qInfo() << "[HapticManager] evdev FF_RUMBLE vibrator at" << path << "effectId"
                << m_ffEffectId;
        return true;
    }

    return false;
}

void HapticManager::setEnabled(bool enabled) {
    if (m_enabled == enabled) {
        return;
    }

    m_enabled = enabled;
    emit enabledChanged();

    qDebug() << "[HapticManager] Haptic feedback:" << (enabled ? "enabled" : "disabled");
}

void HapticManager::vibrate(int duration) {
    if (!m_available || !m_enabled) {
        return;
    }

    qDebug() << "[HapticManager] Vibrating for" << duration << "ms";

    writeVibrator(duration);

    QTimer::singleShot(duration + 100, this, &HapticManager::cancelVibration);
}

void HapticManager::light() {
    vibrate(10);
}

void HapticManager::medium() {
    vibrate(25);
}

void HapticManager::heavy() {
    vibrate(50);
}

void HapticManager::pattern(const QVariantList &durations) {
    vibratePatternVariant(durations);
}

void HapticManager::vibratePattern(const QVariantList &durations, int repeat) {
    Q_UNUSED(repeat);
    vibratePatternVariant(durations);
}

void HapticManager::stopVibration() {
    cancelVibration();
}

void HapticManager::vibratePattern(const QList<int> &pattern) {
    if (!m_available || !m_enabled || pattern.isEmpty()) {
        return;
    }

    qDebug() << "[HapticManager] Vibrating pattern with" << pattern.size() << "steps";

    int totalTime = 0;
    for (int i = 0; i < pattern.size(); ++i) {
        int duration = pattern[i];

        if (i % 2 == 0) {

            QTimer::singleShot(totalTime, this, [this, duration]() { writeVibrator(duration); });
        } else {

            QTimer::singleShot(totalTime, this, &HapticManager::cancelVibration);
        }

        totalTime += duration;
    }

    QTimer::singleShot(totalTime + 50, this, &HapticManager::cancelVibration);
}

void HapticManager::cancelVibration() {
    if (!m_available) {
        return;
    }

    writeVibrator(0);
}

void HapticManager::writeVibrator(int value) {
    if (m_useEvdevFf) {
        if (value > 0)
            playEvdevRumble(value);
        else
            stopEvdevRumble();
        return;
    }

    // Legacy sysfs path: write the duration (ms) or 0 to stop.
    QFile file(m_vibratorPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[HapticManager] Failed to open vibrator:" << file.errorString();
        return;
    }

    file.write(QByteArray::number(value));
    file.close();
}

void HapticManager::playEvdevRumble(int durationMs) {
    if (m_ffFd < 0)
        return;

    // Re-arm the existing effect slot with the requested duration (keeping the
    // same id updates the effect in place rather than leaking slots).
    struct ff_effect effect;
    std::memset(&effect, 0, sizeof(effect));
    effect.type                      = FF_RUMBLE;
    effect.id                        = m_ffEffectId;
    effect.u.rumble.strong_magnitude = 0xFFFF;
    effect.u.rumble.weak_magnitude   = 0xFFFF;
    effect.replay.length             = static_cast<__u16>(qMax(1, durationMs));
    effect.replay.delay              = 0;
    if (::ioctl(m_ffFd, EVIOCSFF, &effect) < 0) {
        qWarning() << "[HapticManager] EVIOCSFF failed:" << ::strerror(errno);
        return;
    }
    m_ffEffectId = effect.id;

    struct input_event play;
    std::memset(&play, 0, sizeof(play));
    play.type  = EV_FF;
    play.code  = static_cast<__u16>(m_ffEffectId);
    play.value = 1; // play once
    if (::write(m_ffFd, &play, sizeof(play)) != (ssize_t)sizeof(play))
        qWarning() << "[HapticManager] FF play write failed:" << ::strerror(errno);
}

void HapticManager::stopEvdevRumble() {
    if (m_ffFd < 0 || m_ffEffectId < 0)
        return;

    struct input_event stop;
    std::memset(&stop, 0, sizeof(stop));
    stop.type  = EV_FF;
    stop.code  = static_cast<__u16>(m_ffEffectId);
    stop.value = 0; // stop
    if (::write(m_ffFd, &stop, sizeof(stop)) != (ssize_t)sizeof(stop))
        qWarning() << "[HapticManager] FF stop write failed:" << ::strerror(errno);
}
