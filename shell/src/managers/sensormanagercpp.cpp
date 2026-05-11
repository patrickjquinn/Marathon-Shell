#include "sensormanagercpp.h"
#include <QDebug>

SensorManagerCpp::SensorManagerCpp(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_proximityAvailable(false)
    , m_proximityNear(false)
    , m_ambientLight(500) {
    qDebug() << "[SensorManagerCpp] Using QtSensors backend";

    m_proximity = new QProximitySensor(this);
    m_light     = new QLightSensor(this);

    bool ok1 = m_proximity->connectToBackend();
    bool ok2 = m_light->connectToBackend();

    m_available = ok1 || ok2;
    emit availableChanged();

    if (ok1 && m_proximity->start()) {
        connect(m_proximity, &QProximitySensor::readingChanged, this,
                &SensorManagerCpp::onProximityChanged);
        m_proximityAvailable = true;
        emit proximityAvailableChanged();
        qInfo() << "[SensorManagerCpp] Proximity sensor active";
    } else {
        // Either no backend, or backend won't actually start a measurement.
        // Without a working sensor we MUST NOT report any proximity events --
        // callers (e.g. TelephonyIntegrationCpp) gate screen-off on this and
        // will leave the user with a dark screen they can't recover from if
        // we lie about "near".
        if (ok1)
            m_proximity->stop();
        qInfo() << "[SensorManagerCpp] No working proximity sensor backend";
    }

    if (ok2 && m_light->start()) {
        connect(m_light, &QLightSensor::readingChanged, this, &SensorManagerCpp::onLightChanged);
        qInfo() << "[SensorManagerCpp] Ambient light sensor active";
    } else {
        if (ok2)
            m_light->stop();
        qInfo() << "[SensorManagerCpp] No working ambient light backend";
    }
}

void SensorManagerCpp::onProximityChanged() {
    bool near = m_proximity->reading()->close();
    if (near != m_proximityNear) {
        m_proximityNear = near;
        emit proximityNearChanged();
    }
}

void SensorManagerCpp::onLightChanged() {
    int lux = int(m_light->reading()->lux());
    if (lux != m_ambientLight) {
        m_ambientLight = lux;
        emit ambientLightChanged();
    }
}
