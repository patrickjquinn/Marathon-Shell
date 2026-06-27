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

    m_proximityBackend = m_proximity->connectToBackend();
    m_lightBackend     = m_light->connectToBackend();

    m_available = m_proximityBackend || m_lightBackend;
    emit availableChanged();

    if (m_proximityBackend) {
        connect(m_proximity, &QProximitySensor::readingChanged, this,
                &SensorManagerCpp::onProximityChanged);
        // proximityAvailable advertises "we *can* report" even when
        // we're not currently polling — TelephonyIntegrationCpp gates
        // its screen-off-during-call behaviour on this flag, and that
        // gating logic doesn't care whether the sensor happens to be
        // running right now. Reflect "backend wired" here; runtime
        // activation is decoupled via setProximityActive().
        m_proximityAvailable = true;
        emit proximityAvailableChanged();
        qInfo() << "[SensorManagerCpp] Proximity sensor backend connected (idle)";
    } else {
        qInfo() << "[SensorManagerCpp] No proximity sensor backend";
    }

    if (m_lightBackend) {
        connect(m_light, &QLightSensor::readingChanged, this, &SensorManagerCpp::onLightChanged);
        qInfo() << "[SensorManagerCpp] Ambient light sensor backend connected (idle)";
    } else {
        qInfo() << "[SensorManagerCpp] No ambient light backend";
    }
}

void SensorManagerCpp::setProximityActive(bool active) {
    if (m_proximityActive == active)
        return;
    m_proximityActive = active;
    if (!m_proximityBackend)
        return;
    if (active && !m_proximityRunning) {
        if (m_proximity->start()) {
            m_proximityRunning = true;
            qInfo() << "[SensorManagerCpp] Proximity sensor started (in-call)";
        } else {
            qWarning() << "[SensorManagerCpp] Proximity sensor refused to start";
        }
    } else if (!active && m_proximityRunning) {
        m_proximity->stop();
        m_proximityRunning = false;
        // Stale "near" reading must not stick around past the call —
        // callers read proximityNear == false to mean "OK to wake".
        if (m_proximityNear) {
            m_proximityNear = false;
            emit proximityNearChanged();
        }
        qInfo() << "[SensorManagerCpp] Proximity sensor stopped (call ended)";
    }
}

void SensorManagerCpp::setLightActive(bool active) {
    if (m_lightActive == active)
        return;
    m_lightActive = active;
    if (!m_lightBackend)
        return;
    if (active && !m_lightRunning) {
        if (m_light->start()) {
            m_lightRunning = true;
            qInfo() << "[SensorManagerCpp] Ambient light sensor started (auto-brightness on)";
        } else {
            qWarning() << "[SensorManagerCpp] Ambient light sensor refused to start";
        }
    } else if (!active && m_lightRunning) {
        m_light->stop();
        m_lightRunning = false;
        qInfo() << "[SensorManagerCpp] Ambient light sensor stopped (auto-brightness off)";
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
