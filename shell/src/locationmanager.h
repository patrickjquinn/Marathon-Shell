#ifndef LOCATIONMANAGER_H
#define LOCATIONMANAGER_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QDBusArgument>
#include <QMetaType>

// GeoClue2 Timestamp is (tt) - seconds and microseconds
struct GeoClueTimestamp {
    qulonglong seconds;
    qulonglong microseconds;
};
Q_DECLARE_METATYPE(GeoClueTimestamp)

QDBusArgument       &operator<<(QDBusArgument &argument, const GeoClueTimestamp &ts);
const QDBusArgument &operator>>(const QDBusArgument &argument, GeoClueTimestamp &ts);

class LocationManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(double latitude READ latitude NOTIFY locationChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY locationChanged)
    Q_PROPERTY(double accuracy READ accuracy NOTIFY locationChanged)
    Q_PROPERTY(double altitude READ altitude NOTIFY locationChanged)
    Q_PROPERTY(double speed READ speed NOTIFY locationChanged)
    Q_PROPERTY(double heading READ heading NOTIFY locationChanged)
    Q_PROPERTY(qint64 timestamp READ timestamp NOTIFY locationChanged)

  public:
    explicit LocationManager(QObject *parent = nullptr);
    ~LocationManager();

    bool available() const {
        return m_available;
    }
    bool active() const {
        return m_active;
    }
    double latitude() const {
        return m_latitude;
    }
    double longitude() const {
        return m_longitude;
    }
    double accuracy() const {
        return m_accuracy;
    }
    double altitude() const {
        return m_altitude;
    }
    double speed() const {
        return m_speed;
    }
    double heading() const {
        return m_heading;
    }
    qint64 timestamp() const {
        return m_timestamp;
    }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();

  signals:
    void availableChanged();
    void activeChanged();
    void locationChanged();
    void error(const QString &message);

  private slots:
    void onLocationUpdated(const QDBusObjectPath &oldLocation, const QDBusObjectPath &newLocation);

  private:
    void            connectToGeoclue();
    void            createClient();
    void            updateLocation(const QString &locationPath);

    QDBusInterface *m_manager;
    QDBusInterface *m_client;
    QString         m_clientPath;
    bool            m_available;
    bool            m_active;
    double          m_latitude;
    double          m_longitude;
    double          m_accuracy;
    double          m_altitude;
    double          m_speed;
    double          m_heading;
    qint64          m_timestamp;
};

#endif // LOCATIONMANAGER_H
