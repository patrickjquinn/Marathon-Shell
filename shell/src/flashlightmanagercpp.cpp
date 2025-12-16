#include "flashlightmanagercpp.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QTimer>

static bool isCandidateLedName(const QString &name) {
    const QString n = name.toLower();
    // Common naming conventions on mobile Linux devices.
    return n.contains("torch") || n.contains("flash") || n.contains("flashlight") ||
        n.contains("camera") && n.contains("led");
}

FlashlightManagerCpp::FlashlightManagerCpp(QObject *parent)
    : QObject(parent) {
    m_pulseTimer = new QTimer(this);
    m_pulseTimer->setSingleShot(true);
    QObject::connect(m_pulseTimer, &QTimer::timeout, this, [this] { setEnabled(false); });

    refresh();
}

void FlashlightManagerCpp::refresh() {
    const bool    prevAvail = m_available;
    const QString prevPath  = m_ledPath;
    const int     prevMax   = m_maxBrightness;

    m_available = discoverLed();

    if (!m_available) {
        // If hardware vanished, force-off.
        if (m_enabled) {
            m_enabled = false;
            emit enabledChanged();
        }
    }

    if (m_available != prevAvail)
        emit availableChanged();
    if (m_ledPath != prevPath)
        emit ledPathChanged();
    if (m_maxBrightness != prevMax)
        emit maxBrightnessChanged();
}

bool FlashlightManagerCpp::discoverLed() {
    QDir ledsDir("/sys/class/leds");
    if (!ledsDir.exists()) {
        m_ledPath.clear();
        m_maxBrightness = 255;
        return false;
    }

    const QStringList entries = ledsDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

    // Prefer obvious candidates first.
    QString best;
    for (const QString &e : entries) {
        if (isCandidateLedName(e)) {
            best = e;
            break;
        }
    }
    if (best.isEmpty() && !entries.isEmpty()) {
        // No obvious candidates; do not guess in production (avoid writing to random LEDs).
        m_ledPath.clear();
        m_maxBrightness = 255;
        return false;
    }

    const QString ledDir = ledsDir.absoluteFilePath(best);
    QFile         brightFile(ledDir + "/brightness");
    if (!brightFile.exists()) {
        m_ledPath.clear();
        m_maxBrightness = 255;
        return false;
    }

    m_ledPath       = ledDir;
    m_maxBrightness = qMax(1, readMaxBrightness(ledDir));
    m_brightness    = qBound(0, m_brightness, m_maxBrightness);
    return true;
}

int FlashlightManagerCpp::readMaxBrightness(const QString &ledDir) const {
    QFile f(ledDir + "/max_brightness");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return 255;
    }
    const QByteArray raw = f.readAll().trimmed();
    bool             ok  = false;
    const int        v   = raw.toInt(&ok);
    return ok ? v : 255;
}

bool FlashlightManagerCpp::writeBrightness(int value) const {
    if (m_ledPath.isEmpty()) {
        return false;
    }

    QFile f(m_ledPath + "/brightness");
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }
    f.write(QByteArray::number(value));
    f.close();
    return true;
}

void FlashlightManagerCpp::setEnabled(bool enabled) {
    if (!m_available) {
        if (enabled)
            emit errorOccurred(QStringLiteral("No flashlight hardware detected"));
        return;
    }

    if (m_enabled == enabled)
        return;

    if (enabled) {
        const int v = qBound(0, m_brightness, m_maxBrightness);
        if (!writeBrightness(v)) {
            emit errorOccurred(QStringLiteral("Failed to enable flashlight (sysfs write failed)"));
            return;
        }
    } else {
        // Stop pulse timer and turn off.
        if (m_pulseTimer->isActive())
            m_pulseTimer->stop();
        (void)writeBrightness(0);
    }

    m_enabled = enabled;
    emit enabledChanged();
}

void FlashlightManagerCpp::setBrightness(int value) {
    const int clamped = qBound(0, value, m_maxBrightness);
    if (clamped == m_brightness)
        return;

    m_brightness = clamped;
    emit brightnessChanged();

    if (m_enabled && m_available) {
        if (!writeBrightness(m_brightness)) {
            emit errorOccurred(
                QStringLiteral("Failed to set flashlight brightness (sysfs write failed)"));
        }
    }
}

bool FlashlightManagerCpp::toggle() {
    if (!m_available) {
        emit errorOccurred(QStringLiteral("No flashlight hardware detected"));
        return false;
    }
    setEnabled(!m_enabled);
    return m_enabled;
}

void FlashlightManagerCpp::pulse(int durationMs) {
    if (!m_available) {
        emit errorOccurred(QStringLiteral("No flashlight hardware detected"));
        return;
    }
    durationMs = qBound(1, durationMs, 60 * 1000);
    setEnabled(true);
    m_pulseTimer->start(durationMs);
}
