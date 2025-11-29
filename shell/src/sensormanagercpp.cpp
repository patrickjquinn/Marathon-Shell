#include "sensormanagercpp.h"
#include <QDebug>

SensorManagerCpp::SensorManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_proximityNear(false)
    , m_ambientLight(500) // Default to moderate light
{
    qDebug() << "[SensorManagerCpp] Using QtSensors backend";

    m_proximity = new QProximitySensor(this);
    m_light     = new QLightSensor(this);

    bool ok1 = m_proximity->connectToBackend();
    bool ok2 = m_light->connectToBackend();

    m_available = ok1 || ok2;
    emit availableChanged();

    // Proximity
    if (ok1) {
        connect(m_proximity, &QProximitySensor::readingChanged,
                this, &SensorManagerCpp::onProximityChanged);
        m_proximity->start();
        qInfo() << "[SensorManagerCpp] Proximity sensor active";
    } else {
        qInfo() << "[SensorManagerCpp] No proximity sensor backend";
    }

    // Ambient light
    if (ok2) {
        connect(m_light, &QLightSensor::readingChanged,
                this, &SensorManagerCpp::onLightChanged);
        m_light->start();
        qInfo() << "[SensorManagerCpp] Ambient light sensor active";
    } else {
        qInfo() << "[SensorManagerCpp] No ambient light backend";
    }
}

void SensorManagerCpp::onProximityChanged()
{
    bool near = m_proximity->reading()->close();
    if (near != m_proximityNear) {
        m_proximityNear = near;
        emit proximityNearChanged();
    }
}

void SensorManagerCpp::onLightChanged()
{
    int lux = int(m_light->reading()->lux());
    if (lux != m_ambientLight) {
        m_ambientLight = lux;
        emit ambientLightChanged();
    }
}
