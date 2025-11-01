#include "rotationmanager.h"
#include <QDBusConnection>
#include <QDBusReply>
#include <QDebug>

RotationManager::RotationManager(QObject* parent)
    : QObject(parent)
    , m_sensorProxy(nullptr)
    , m_reconnectTimer(new QTimer(this))
    , m_available(false)
    , m_autoRotateEnabled(true)
    , m_claimed(false)
    , m_currentOrientation("normal")
    , m_currentRotation(0)
{
    qDebug() << "[RotationManager] Initializing";
    
    connectToSensorProxy();
    
    m_reconnectTimer->setInterval(10000);
    connect(m_reconnectTimer, &QTimer::timeout, this, &RotationManager::checkSensorProxy);
    m_reconnectTimer->start();
}

RotationManager::~RotationManager()
{
    if (m_claimed) {
        releaseAccelerometer();
    }
    if (m_sensorProxy) {
        delete m_sensorProxy;
    }
}

void RotationManager::connectToSensorProxy()
{
    qDebug() << "[RotationManager] Connecting to iio-sensor-proxy";
    
    m_sensorProxy = new QDBusInterface(
        "net.hadess.SensorProxy",
        "/net/hadess/SensorProxy",
        "net.hadess.SensorProxy",
        QDBusConnection::systemBus(),
        this
    );
    
    if (!m_sensorProxy->isValid()) {
        qDebug() << "[RotationManager] iio-sensor-proxy not available:" << m_sensorProxy->lastError().message();
        m_available = false;
        emit availableChanged();
        return;
    }
    
    qInfo() << "[RotationManager] ✓ Connected to iio-sensor-proxy";
    
    // Check if accelerometer is available
    QDBusReply<bool> hasAccel = m_sensorProxy->call("HasAccelerometer");
    if (!hasAccel.isValid() || !hasAccel.value()) {
        qDebug() << "[RotationManager] No accelerometer available";
        m_available = false;
        emit availableChanged();
        return;
    }
    
    m_available = true;
    emit availableChanged();
    
    // Monitor property changes
    QDBusConnection::systemBus().connect(
        "net.hadess.SensorProxy",
        "/net/hadess/SensorProxy",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        this,
        SLOT(onPropertiesChanged(QString,QVariantMap,QStringList))
    );
    
    // Claim accelerometer and start monitoring
    if (m_autoRotateEnabled) {
        claimAccelerometer();
        queryOrientation();
    }
    
    qInfo() << "[RotationManager] Initialized with accelerometer support";
}

void RotationManager::claimAccelerometer()
{
    if (!m_sensorProxy || !m_sensorProxy->isValid() || m_claimed) {
        return;
    }
    
    QDBusReply<void> reply = m_sensorProxy->call("ClaimAccelerometer");
    if (!reply.isValid()) {
        qWarning() << "[RotationManager] Failed to claim accelerometer:" << reply.error().message();
        return;
    }
    
    m_claimed = true;
    qDebug() << "[RotationManager] Accelerometer claimed";
}

void RotationManager::releaseAccelerometer()
{
    if (!m_sensorProxy || !m_sensorProxy->isValid() || !m_claimed) {
        return;
    }
    
    m_sensorProxy->call("ReleaseAccelerometer");
    m_claimed = false;
    qDebug() << "[RotationManager] Accelerometer released";
}

void RotationManager::setAutoRotateEnabled(bool enabled)
{
    if (m_autoRotateEnabled == enabled) {
        return;
    }
    
    m_autoRotateEnabled = enabled;
    emit autoRotateEnabledChanged();
    
    if (enabled) {
        claimAccelerometer();
        queryOrientation();
    } else {
        releaseAccelerometer();
    }
    
    qInfo() << "[RotationManager] Auto-rotate:" << (enabled ? "enabled" : "disabled");
}

void RotationManager::queryOrientation()
{
    if (!m_sensorProxy || !m_sensorProxy->isValid()) {
        return;
    }
    
    QDBusReply<QString> reply = m_sensorProxy->call("AccelerometerOrientation");
    if (!reply.isValid()) {
        return;
    }
    
    QString orientation = reply.value();
    if (orientation != m_currentOrientation) {
        m_currentOrientation = orientation;
        m_currentRotation = orientationToRotation(orientation);
        emit orientationChanged();
        qInfo() << "[RotationManager] Orientation changed to:" << orientation << "(" << m_currentRotation << "°)";
    }
}

void RotationManager::onPropertiesChanged(const QString& interface, const QVariantMap& changed, const QStringList& invalidated)
{
    Q_UNUSED(invalidated)
    
    if (interface != "net.hadess.SensorProxy") {
        return;
    }
    
    if (changed.contains("AccelerometerOrientation")) {
        QString orientation = changed.value("AccelerometerOrientation").toString();
        if (orientation != m_currentOrientation && m_autoRotateEnabled) {
            m_currentOrientation = orientation;
            m_currentRotation = orientationToRotation(orientation);
            emit orientationChanged();
            qInfo() << "[RotationManager] Orientation changed to:" << orientation << "(" << m_currentRotation << "°)";
        }
    }
}

void RotationManager::checkSensorProxy()
{
    if (!m_available) {
        connectToSensorProxy();
    }
}

void RotationManager::lockOrientation(const QString& orientation)
{
    qInfo() << "[RotationManager] Locking orientation to:" << orientation;
    setAutoRotateEnabled(false);
    m_currentOrientation = orientation;
    m_currentRotation = orientationToRotation(orientation);
    emit orientationChanged();
}

void RotationManager::unlockOrientation()
{
    qInfo() << "[RotationManager] Unlocking orientation";
    setAutoRotateEnabled(true);
}

int RotationManager::orientationToRotation(const QString& orientation)
{
    if (orientation == "normal") return 0;
    if (orientation == "bottom-up") return 180;
    if (orientation == "left-up") return 270;
    if (orientation == "right-up") return 90;
    return 0;
}

