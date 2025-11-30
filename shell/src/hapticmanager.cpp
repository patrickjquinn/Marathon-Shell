#include "hapticmanager.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTimer>

HapticManager::HapticManager(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_enabled(true) {
    qDebug() << "[HapticManager] Initializing";

    m_available = detectVibrator();

    if (m_available) {
        qInfo() << "[HapticManager] ✓ Vibrator found at:" << m_vibratorPath;
    } else {
        qInfo() << "[HapticManager] No vibrator hardware detected";
    }
}

bool HapticManager::detectVibrator() {
    // Common vibrator paths
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

    // Activate vibrator
    writeVibrator(duration);

    // Auto-stop after duration (safety fallback)
    QTimer::singleShot(duration + 100, this, &HapticManager::cancelVibration);
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
            // Even indices: vibrate
            QTimer::singleShot(totalTime, this, [this, duration]() { writeVibrator(duration); });
        } else {
            // Odd indices: pause
            QTimer::singleShot(totalTime, this, &HapticManager::cancelVibration);
        }

        totalTime += duration;
    }

    // Ensure stopped at end
    QTimer::singleShot(totalTime + 50, this, &HapticManager::cancelVibration);
}

void HapticManager::cancelVibration() {
    if (!m_available) {
        return;
    }

    writeVibrator(0);
}

void HapticManager::writeVibrator(int value) {
    QFile file(m_vibratorPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[HapticManager] Failed to open vibrator:" << file.errorString();
        return;
    }

    file.write(QByteArray::number(value));
    file.close();
}
