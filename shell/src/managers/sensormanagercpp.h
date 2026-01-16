#ifndef SENSORMANAGERCPP_H
#define SENSORMANAGERCPP_H

#include <QObject>
#include <QTimer>
#include <QLightSensor>
#include <QLightReading>
#include <QProximitySensor>
#include <QProximityReading>

class SensorManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool proximityNear READ proximityNear NOTIFY proximityNearChanged)
    Q_PROPERTY(int ambientLight READ ambientLight NOTIFY ambientLightChanged)

  public:
    explicit SensorManagerCpp(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool proximityNear() const {
        return m_proximityNear;
    }
    int ambientLight() const {
        return m_ambientLight;
    }

  private slots:
    void onProximityChanged();
    void onLightChanged();

  signals:
    void availableChanged();
    void proximityNearChanged();
    void ambientLightChanged();

  private:
    bool              m_available;
    bool              m_proximityNear;
    int               m_ambientLight;

    QProximitySensor *m_proximity;
    QLightSensor     *m_light;
};

#endif
