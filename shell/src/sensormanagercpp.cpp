#include "sensormanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>

SensorManagerCpp::SensorManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_proximityNear(false)
    , m_ambientLight(500) // Default to moderate light
{
    qDebug() << "[SensorManagerCpp] Initializing";
    
    if (Platform::hasIIOSensors()) {
        m_available = detectSensors();
        if (m_available) {
            qInfo() << "[SensorManagerCpp] IIO sensors available";
            
            // Setup polling timer for sensor updates
            m_pollTimer = new QTimer(this);
            m_pollTimer->setInterval(1000); // Poll every second
            connect(m_pollTimer, &QTimer::timeout, this, &SensorManagerCpp::pollSensors);
            m_pollTimer->start();
        } else {
            qInfo() << "[SensorManagerCpp] No IIO sensors detected";
        }
    } else {
        qInfo() << "[SensorManagerCpp] IIO sensors not available on this platform";
    }
}

bool SensorManagerCpp::detectSensors()
{
    QDir iioDir("/sys/bus/iio/devices");
    if (!iioDir.exists()) {
        return false;
    }
    
    QStringList devices = iioDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    bool foundAny = false;
    
    for (const QString& device : devices) {
        QString devicePath = iioDir.absoluteFilePath(device);
        QString namePath = devicePath + "/name";
        
        QFile nameFile(namePath);
        if (!nameFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        
        QString name = nameFile.readAll().trimmed();
        nameFile.close();
        
        // Detect proximity sensor
        if (name.contains("proximity", Qt::CaseInsensitive) || name.contains("prox", Qt::CaseInsensitive)) {
            m_proximitySensorPath = devicePath;
            qInfo() << "[SensorManagerCpp] Found proximity sensor:" << name << "at" << device;
            foundAny = true;
        }
        
        // Detect ambient light sensor
        if (name.contains("light", Qt::CaseInsensitive) || name.contains("als", Qt::CaseInsensitive) || 
            name.contains("illuminance", Qt::CaseInsensitive)) {
            m_ambientLightSensorPath = devicePath;
            qInfo() << "[SensorManagerCpp] Found ambient light sensor:" << name << "at" << device;
            foundAny = true;
        }
    }
    
    return foundAny;
}

void SensorManagerCpp::pollSensors()
{
    if (!m_proximitySensorPath.isEmpty()) {
        bool wasNear = m_proximityNear;
        m_proximityNear = readProximitySensor();
        if (wasNear != m_proximityNear) {
            emit proximityNearChanged();
        }
    }
    
    if (!m_ambientLightSensorPath.isEmpty()) {
        int oldLight = m_ambientLight;
        m_ambientLight = readAmbientLightSensor();
        if (qAbs(oldLight - m_ambientLight) > 50) { // Only emit if significant change
            emit ambientLightChanged();
        }
    }
}

bool SensorManagerCpp::readProximitySensor()
{
    if (m_proximitySensorPath.isEmpty()) return false;
    
    QString valuePath = m_proximitySensorPath + "/in_proximity_raw";
    QFile file(valuePath);
    
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        // Try alternative path
        valuePath = m_proximitySensorPath + "/in_proximity_input";
        file.setFileName(valuePath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return false;
        }
    }
    
    QString value = file.readAll().trimmed();
    file.close();
    
    // Typically: 0 = far, 1 = near (or higher values = near)
    return value.toInt() > 0;
}

int SensorManagerCpp::readAmbientLightSensor()
{
    if (m_ambientLightSensorPath.isEmpty()) return m_ambientLight; // Keep previous value
    
    QString valuePath = m_ambientLightSensorPath + "/in_illuminance_raw";
    QFile file(valuePath);
    
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        // Try alternative paths
        valuePath = m_ambientLightSensorPath + "/in_illuminance_input";
        file.setFileName(valuePath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            valuePath = m_ambientLightSensorPath + "/in_intensity_both_raw";
            file.setFileName(valuePath);
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
                return m_ambientLight; // Keep previous value
            }
        }
    }
    
    QString value = file.readAll().trimmed();
    file.close();
    
    return value.toInt();
}

