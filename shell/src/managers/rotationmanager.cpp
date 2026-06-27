#include "rotationmanager.h"
#include <QDebug>

RotationManager::RotationManager(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_autoRotateEnabled(true)
    , m_currentOrientation("portrait")
    , m_currentRotation(0) {
    m_sensor = new QOrientationSensor(this);

    if (m_sensor->connectToBackend()) {
        m_available = true;
        emit availableChanged();

        connect(m_sensor, &QOrientationSensor::readingChanged, this,
                &RotationManager::onOrientationReadingChanged);

        // Don't unconditionally start the sensor here. main.cpp wires
        // displayManager->screenStateChanged to setScreenOn(); the
        // sensor only runs while (autoRotate && screenOn). Until then
        // the lsm6dsx (or whatever backend) stays unclaimed.
        qInfo() << "[RotationManager] Using QtSensors orientation backend (idle)";
        _evaluateSensorState();
    } else {
        qWarning() << "[RotationManager] No orientation sensor backend available";
    }
}

RotationManager::~RotationManager() = default;

void RotationManager::setAutoRotateEnabled(bool enabled) {
    if (m_autoRotateEnabled == enabled)
        return;

    m_autoRotateEnabled = enabled;
    emit autoRotateEnabledChanged();

    _evaluateSensorState();

    qInfo() << "[RotationManager] Auto-rotate" << (enabled ? "enabled" : "disabled");
}

void RotationManager::setScreenOn(bool on) {
    if (m_screenOn == on)
        return;
    m_screenOn = on;
    _evaluateSensorState();
}

void RotationManager::_evaluateSensorState() {
    if (!m_available)
        return;

    const bool shouldRun = m_autoRotateEnabled && m_screenOn;
    if (shouldRun == m_sensorRunning)
        return;

    if (shouldRun) {
        m_sensor->start();
        m_sensorRunning = true;
        qInfo() << "[RotationManager] sensor started (autoRotate + screenOn)";
    } else {
        m_sensor->stop();
        m_sensorRunning = false;
        qInfo() << "[RotationManager] sensor stopped (autoRotate=" << m_autoRotateEnabled
                << " screenOn=" << m_screenOn << ")";
    }
}

QString RotationManager::orientationToString(QOrientationReading::Orientation o) {
    switch (o) {
        case QOrientationReading::TopUp: return "portrait";
        case QOrientationReading::RightUp: return "landscape";
        case QOrientationReading::TopDown: return "portrait-inverted";
        case QOrientationReading::LeftUp: return "landscape-inverted";
        default: return "portrait";
    }
}

int RotationManager::orientationToRotation(QOrientationReading::Orientation o) {
    switch (o) {
        case QOrientationReading::TopUp: return 0;
        case QOrientationReading::RightUp: return 90;
        case QOrientationReading::TopDown: return 180;
        case QOrientationReading::LeftUp: return 270;
        default: return 0;
    }
}

void RotationManager::onOrientationReadingChanged() {
    if (!m_autoRotateEnabled)
        return;

    QOrientationReading *r = m_sensor->reading();
    auto                 o = r->orientation();

    QString              oriString = orientationToString(o);
    int                  angle     = orientationToRotation(o);

    if (oriString != m_currentOrientation) {
        m_currentOrientation = oriString;
        m_currentRotation    = angle;
        emit orientationChanged();

        qInfo() << "[RotationManager] Orientation:" << oriString << "(" << angle << "° )";
    }
}

void RotationManager::lockOrientation(const QString &orientation) {
    m_autoRotateEnabled = false;
    _evaluateSensorState();

    m_currentOrientation = orientation;

    if (orientation == "portrait")
        m_currentRotation = 0;
    else if (orientation == "landscape")
        m_currentRotation = 90;
    else if (orientation == "portrait-inverted")
        m_currentRotation = 180;
    else if (orientation == "landscape-inverted")
        m_currentRotation = 270;

    emit orientationChanged();
}

void RotationManager::unlockOrientation() {
    m_autoRotateEnabled = true;
    emit autoRotateEnabledChanged();
    _evaluateSensorState();
}
