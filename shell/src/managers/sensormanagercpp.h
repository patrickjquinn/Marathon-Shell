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
    Q_PROPERTY(bool proximityAvailable READ proximityAvailable NOTIFY proximityAvailableChanged)
    Q_PROPERTY(bool proximityNear READ proximityNear NOTIFY proximityNearChanged)
    Q_PROPERTY(int ambientLight READ ambientLight NOTIFY ambientLightChanged)

  public:
    explicit SensorManagerCpp(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool proximityAvailable() const {
        return m_proximityAvailable;
    }
    bool proximityNear() const {
        return m_proximityNear;
    }
    int ambientLight() const {
        return m_ambientLight;
    }

    // Phosh-pattern lazy claim. Wired in main.cpp:
    //   - setProximityActive(bool) ← PowerPolicyController::hasActiveCallsChanged
    //   - setLightActive(bool)     ← SettingsManager::autoBrightnessChanged
    // The sensor backends connect at construction but the sensors only
    // start polling while their respective consumer wants them. Without
    // this both run forever, holding the I²C bus and waking the CPU on
    // every reading, with no consumer paying attention.
    void setProximityActive(bool active);
    void setLightActive(bool active);

  private slots:
    void onProximityChanged();
    void onLightChanged();

  signals:
    void availableChanged();
    void proximityAvailableChanged();
    void proximityNearChanged();
    void ambientLightChanged();

  private:
    bool m_available;
    bool m_proximityAvailable;
    bool m_proximityNear;
    int  m_ambientLight;

    // Backend availability (was true at construction in the old code).
    bool m_proximityBackend = false;
    bool m_lightBackend     = false;
    // Requested-active vs actually-running. Idempotency guards.
    bool              m_proximityActive  = false;
    bool              m_lightActive      = false;
    bool              m_proximityRunning = false;
    bool              m_lightRunning     = false;

    QProximitySensor *m_proximity;
    QLightSensor     *m_light;
};

#endif
