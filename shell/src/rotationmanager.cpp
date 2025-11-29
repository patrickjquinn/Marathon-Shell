#include "rotationmanager.h"
#include <QDebug>

RotationManager::RotationManager(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_autoRotateEnabled(true)
    , m_currentOrientation("normal")
    , m_currentRotation(0)
{
    m_sensor = new QOrientationSensor(this);

    if (m_sensor->connectToBackend()) {
        m_available = true;
        emit availableChanged();

        connect(m_sensor, &QOrientationSensor::readingChanged,
                this, &RotationManager::onOrientationReadingChanged);

        m_sensor->start();
        qInfo() << "[RotationManager] Using QtSensors orientation backend";
    } else {
        qWarning() << "[RotationManager] No orientation sensor backend available";
    }
}

RotationManager::~RotationManager() {}

void RotationManager::setAutoRotateEnabled(bool enabled)
{
    if (m_autoRotateEnabled == enabled)
        return;

    m_autoRotateEnabled = enabled;
    emit autoRotateEnabledChanged();

    if (enabled)
        m_sensor->start();
    else
        m_sensor->stop();

    qInfo() << "[RotationManager] Auto-rotate" << (enabled ? "enabled" : "disabled");
}

QString RotationManager::orientationToString(QOrientationReading::Orientation o)
{
    switch (o) {
    case QOrientationReading::TopUp:
        return "portrait";
    case QOrientationReading::RightUp:
        return "landscape";
    case QOrientationReading::TopDown:
        return "portrait-inverted";
    case QOrientationReading::LeftUp:
        return "landscape-inverted";
    default:
        return "portrait";
    }
}


int RotationManager::orientationToRotation(QOrientationReading::Orientation o)
{
    switch (o) {
    case QOrientationReading::TopUp: // portrait
        return 0;
    case QOrientationReading::RightUp: // landscape
        return 90;
    case QOrientationReading::TopDown: // portrait-inverted
        return 180;
    case QOrientationReading::LeftUp: // landscape-inverted
        return 270;
    default:
        return 0;
    }
}

void RotationManager::onOrientationReadingChanged()
{
    if (!m_autoRotateEnabled)
        return;

    QOrientationReading* r = m_sensor->reading();
    auto o = r->orientation();

    QString oriString = orientationToString(o);
    int angle = orientationToRotation(o);

    if (oriString != m_currentOrientation) {
        m_currentOrientation = oriString;
        m_currentRotation = angle;
        emit orientationChanged();

        qInfo() << "[RotationManager] Orientation:" << oriString << "(" << angle << "° )";
    }
}

void RotationManager::lockOrientation(const QString& orientation)
{
    m_sensor->stop();
    m_autoRotateEnabled = false;

    m_currentOrientation = orientation;

    if (orientation == "portrait")           m_currentRotation = 0;
    else if (orientation == "landscape")     m_currentRotation = 90;
    else if (orientation == "portrait-inverted") m_currentRotation = 180;
    else if (orientation == "landscape-inverted") m_currentRotation = 270;

    emit orientationChanged();
}

void RotationManager::unlockOrientation()
{
    m_autoRotateEnabled = true;
    m_sensor->start();
    emit autoRotateEnabledChanged();
}
