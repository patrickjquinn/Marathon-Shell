#ifndef SENSORMANAGERCPP_H
#define SENSORMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QTimer>

class SensorManagerCpp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool proximityNear READ proximityNear NOTIFY proximityNearChanged)
    Q_PROPERTY(int ambientLight READ ambientLight NOTIFY ambientLightChanged)

public:
    explicit SensorManagerCpp(QObject* parent = nullptr);
    
    bool available() const { return m_available; }
    bool proximityNear() const { return m_proximityNear; }
    int ambientLight() const { return m_ambientLight; }

signals:
    void availableChanged();
    void proximityNearChanged();
    void ambientLightChanged();

private slots:
    void pollSensors();

private:
    bool detectSensors();
    bool readProximitySensor();
    int readAmbientLightSensor();
    
    bool m_available;
    bool m_proximityNear;
    int m_ambientLight; // In lux
    QTimer* m_pollTimer;
    
    QString m_proximitySensorPath;
    QString m_ambientLightSensorPath;
};

#endif // SENSORMANAGERCPP_H

