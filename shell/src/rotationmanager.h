#ifndef ROTATIONMANAGER_H
#define ROTATIONMANAGER_H

#include <QObject>
#include <QOrientationSensor>
#include <QOrientationReading>
#include <QTimer>

class RotationManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool autoRotateEnabled READ autoRotateEnabled WRITE setAutoRotateEnabled NOTIFY autoRotateEnabledChanged)
    Q_PROPERTY(QString currentOrientation READ currentOrientation NOTIFY orientationChanged)
    Q_PROPERTY(int currentRotation READ currentRotation NOTIFY orientationChanged)

public:
    explicit RotationManager(QObject* parent = nullptr);
    ~RotationManager();

    bool available() const { return m_available; }
    bool autoRotateEnabled() const { return m_autoRotateEnabled; }
    QString currentOrientation() const { return m_currentOrientation; }
    int currentRotation() const { return m_currentRotation; }

    void setAutoRotateEnabled(bool enabled);

    Q_INVOKABLE void lockOrientation(const QString& orientation);
    Q_INVOKABLE void unlockOrientation();

signals:
    void availableChanged();
    void autoRotateEnabledChanged();
    void orientationChanged();

private slots:
    void onOrientationReadingChanged();

private:
    int orientationToRotation(QOrientationReading::Orientation o);
    QString orientationToString(QOrientationReading::Orientation o);

    bool m_available;
    bool m_autoRotateEnabled;

    QString m_currentOrientation;
    int m_currentRotation;

    QOrientationSensor* m_sensor;
};

#endif // ROTATIONMANAGER_H
