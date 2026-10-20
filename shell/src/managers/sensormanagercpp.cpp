#include "sensormanagercpp.h"
#include "marathon-shell-native/src/iio.cxxqt.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QTextStream>

#include <cmath>

// Locate the vcnl4000/4040 iio device and cache its light + proximity
// sysfs paths, the lux scale, and the near threshold. Returns true if a
// usable ambient-light channel was found.
bool SensorManagerCpp::detectIioSensors() {
    QDir       base(m_iioDir);
    const auto entries = base.entryList(QStringList() << "iio:device*", QDir::Dirs);
    for (const QString &e : entries) {
        const QString dir  = base.absoluteFilePath(e);
        const QString lraw = dir + "/in_illuminance_raw";
        const QString praw = dir + "/in_proximity_raw";
        if (!QFile::exists(lraw))
            continue;

        m_iioLightPath = lraw;

        QFile sc(dir + "/in_illuminance_scale");
        if (sc.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const double s = QTextStream(&sc).readAll().trimmed().toDouble();
            if (s > 0.0)
                m_iioLuxScale = s;
        }
        if (QFile::exists(praw)) {
            m_iioProxPath = praw;
            QFile nl(dir + "/in_proximity_nearlevel");
            if (nl.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const int lvl = QTextStream(&nl).readAll().trimmed().toInt();
                if (lvl > 0)
                    m_iioProxNearLevel = lvl;
            }
        }
        qInfo() << "[SensorManagerCpp] Using direct-iio backend:" << dir
                << "luxScale=" << m_iioLuxScale << "proxNear=" << m_iioProxNearLevel;
        return true;
    }
    return false;
}

static bool sensorProxyHasAmbientLight() {
    QDBusMessage get = QDBusMessage::createMethodCall(
        QStringLiteral("net.hadess.SensorProxy"), QStringLiteral("/net/hadess/SensorProxy"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    get.setArguments({QStringLiteral("net.hadess.SensorProxy"), QStringLiteral("HasAmbientLight")});
    const QDBusReply<QDBusVariant> reply =
        QDBusConnection::systemBus().call(get, QDBus::Block, 2000);
    return reply.isValid() && reply.value().variant().toBool();
}

SensorManagerCpp::SensorManagerCpp(QObject *parent, const QString &iioDir)
    : QObject(parent)
    , m_available(false)
    , m_proximityAvailable(false)
    , m_proximityNear(false)
    , m_ambientLight(500)
    , m_iioDir(iioDir) {

    m_proximity = new QProximitySensor(this);
    m_light     = new QLightSensor(this);

    // Prefer the reliable direct-iio path; fall back to QtSensors only if
    // no iio ambient-light device is present (e.g. QEMU).
    m_useIio = detectIioSensors();
    if (m_useIio) {
        m_iio = new IioPoller();
        m_iio->setParent(this);
        m_iio->setChannels(m_iioLightPath, m_iioLuxScale, m_iioProxPath, m_iioProxNearLevel);
        connect(m_iio, &IioPoller::lightRead, this, [this](int lux) {
            if (m_lightRunning && lux != m_ambientLight) {
                m_ambientLight = lux;
                emit ambientLightChanged();
            }
        });
        connect(m_iio, &IioPoller::proximityRead, this, [this](bool near) {
            if (m_proximityRunning && near != m_proximityNear) {
                m_proximityNear = near;
                emit proximityNearChanged();
            }
        });
        m_lightBackend     = true;
        m_proximityBackend = !m_iioProxPath.isEmpty();
        m_available        = true;
        if (m_proximityBackend) {
            m_proximityAvailable = true;
        }
        return;
    }

    qInfo() << "[SensorManagerCpp] No iio sensors — using QtSensors backend";
    m_proximityBackend = m_proximity->connectToBackend();
    // QtSensors' iio-sensor-proxy backend connects whether or not there is a
    // light sensor; only the proxy knows.
    m_lightBackend = sensorProxyHasAmbientLight() && m_light->connectToBackend();

    m_available = m_proximityBackend || m_lightBackend;

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

    if (m_useIio) {
        if (!m_proximityBackend)
            return;
        if (active && !m_proximityRunning) {
            m_proximityRunning = true;
            m_iio->setActive(m_lightRunning, true);
            qInfo() << "[SensorManagerCpp] Proximity (iio) started (in-call)";
        } else if (!active && m_proximityRunning) {
            m_proximityRunning = false;
            m_iio->setActive(m_lightRunning, false);
            if (m_proximityNear) {
                m_proximityNear = false;
                emit proximityNearChanged();
            }
            qInfo() << "[SensorManagerCpp] Proximity (iio) stopped (call ended)";
        }
        return;
    }

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

    if (m_useIio) {
        if (active && !m_lightRunning) {
            m_lightRunning = true;
            m_iio->setActive(true, m_proximityRunning);
            qInfo() << "[SensorManagerCpp] Ambient light (iio) started";
        } else if (!active && m_lightRunning) {
            m_lightRunning = false;
            m_iio->setActive(false, m_proximityRunning);
            qInfo() << "[SensorManagerCpp] Ambient light (iio) stopped (auto-brightness off)";
        }
        return;
    }

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

