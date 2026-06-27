#ifndef ROTATIONMANAGER_H
#define ROTATIONMANAGER_H

#include <QObject>
#include <QOrientationSensor>
#include <QOrientationReading>
#include <QTimer>

class RotationManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool autoRotateEnabled READ autoRotateEnabled WRITE setAutoRotateEnabled NOTIFY
                   autoRotateEnabledChanged)
    Q_PROPERTY(QString currentOrientation READ currentOrientation NOTIFY orientationChanged)
    Q_PROPERTY(int currentRotation READ currentRotation NOTIFY orientationChanged)

  public:
    explicit RotationManager(QObject *parent = nullptr);
    ~RotationManager() override;

    bool available() const {
        return m_available;
    }
    bool autoRotateEnabled() const {
        return m_autoRotateEnabled;
    }
    QString currentOrientation() const {
        return m_currentOrientation;
    }
    int currentRotation() const {
        return m_currentRotation;
    }

    void setAutoRotateEnabled(bool enabled);

    // Wired in main.cpp to displayManager->screenStateChanged so the
    // accelerometer drops off the power budget the moment the panel
    // goes dark (Phosh-pattern lazy sensor claim). Without this we
    // were holding lsm6dsx live 24/7 — pointless when the screen is
    // off and the device can't rotate anyway.
    void             setScreenOn(bool on);

    Q_INVOKABLE void lockOrientation(const QString &orientation);
    Q_INVOKABLE void unlockOrientation();

  signals:
    void availableChanged();
    void autoRotateEnabledChanged();
    void orientationChanged();

  private slots:
    void onOrientationReadingChanged();

  private:
    int     orientationToRotation(QOrientationReading::Orientation o);
    QString orientationToString(QOrientationReading::Orientation o);

    // Apply the (autoRotate && screenOn) gate: starts the sensor
    // when both are true, stops it otherwise. Idempotent — safe to
    // call on every transition.
    void                _evaluateSensorState();

    bool                m_available;
    bool                m_autoRotateEnabled;
    bool                m_screenOn      = true;
    bool                m_sensorRunning = false;

    QString             m_currentOrientation;
    int                 m_currentRotation;

    QOrientationSensor *m_sensor;
};

#endif
