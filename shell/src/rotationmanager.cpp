#include "rotationmanager.h"
#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusPendingCallWatcher>
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
    m_sensorProxy = new QDBusInterface(
        "net.hadess.SensorProxy",
        "/net/hadess/SensorProxy",
        "net.hadess.SensorProxy",
        QDBusConnection::systemBus(),
        this
    );
    
    if (!m_sensorProxy->isValid()) {
        m_available = false;
        emit availableChanged();
        return;
    }
    
    qInfo() << "[RotationManager] ✓ Connected to iio-sensor-proxy";
    
    // Check if accelerometer is available asynchronously
    QDBusPendingCall asyncCall = m_sensorProxy->asyncCall("HasAccelerometer");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(asyncCall, this);
    
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        QDBusPendingReply<bool> reply = *call;
        if (reply.isValid() && reply.value()) {
            qInfo() << "[RotationManager] Accelerometer detected";
            m_available = true;
            emit availableChanged();
            
            if (m_autoRotateEnabled) {
                claimAccelerometer();
                queryOrientation();
            }
        } else {
            qDebug() << "[RotationManager] No accelerometer available (yet)";
        }
        call->deleteLater();
    });
    
    // Monitor property changes
    QDBusConnection::systemBus().connect(
        "net.hadess.SensorProxy",
        "/net/hadess/SensorProxy",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        this,
        SLOT(onPropertiesChanged(QString,QVariantMap,QStringList))
    );
    
    qInfo() << "[RotationManager] Initialized with accelerometer support";
}

void RotationManager::claimAccelerometer()
{
    if (!m_sensorProxy || !m_sensorProxy->isValid() || m_claimed) {
        return;
    }
    
    QDBusPendingCall asyncCall = m_sensorProxy->asyncCall("ClaimAccelerometer");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(asyncCall, this);
    
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        QDBusPendingReply<void> reply = *call;
        if (reply.isError()) {
            qWarning() << "[RotationManager] Failed to claim accelerometer:" << reply.error().message();
        } else {
            m_claimed = true;
            qDebug() << "[RotationManager] Accelerometer claimed";
        }
        call->deleteLater();
    });
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
    } else if (changed.contains("HasAccelerometer")) {
        bool hasAccel = changed.value("HasAccelerometer").toBool();
        qInfo() << "[RotationManager] HasAccelerometer changed to:" << hasAccel;
        if (hasAccel) {
            m_available = true;
            emit availableChanged();
            if (m_autoRotateEnabled) {
                claimAccelerometer();
                queryOrientation();
            }
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

