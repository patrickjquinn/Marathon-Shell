#ifndef ROTATIONMANAGER_H
#define ROTATIONMANAGER_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
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
    void onPropertiesChanged(const QString& interface, const QVariantMap& changed, const QStringList& invalidated);
    void checkSensorProxy();

private:
    void connectToSensorProxy();
    void claimAccelerometer();
    void releaseAccelerometer();
    void queryOrientation();
    int orientationToRotation(const QString& orientation);
    
    QDBusInterface* m_sensorProxy;
    QTimer* m_reconnectTimer;
    bool m_available;
    bool m_autoRotateEnabled;
    bool m_claimed;
    QString m_currentOrientation;  // "normal", "bottom-up", "left-up", "right-up"
    int m_currentRotation;  // 0, 90, 180, 270
};

#endif // ROTATIONMANAGER_H

