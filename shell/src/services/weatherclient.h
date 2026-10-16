#ifndef WEATHERCLIENT_H
#define WEATHERCLIENT_H

#include <QDBusConnection>
#include <QObject>
#include <QVariantMap>

#include <qqml.h>

// marathon-weatherd's session service, org.marathonos.Weather.
class WeatherClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // The service's Forecast, parsed; empty until the first one.
    Q_PROPERTY(QVariantMap forecast READ forecast NOTIFY forecastChanged)
    // "idle", "updating", "offline", "no-location" or "error: …".
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    // °F and mph for the US locale, mph for the UK, metric otherwise.
    Q_PROPERTY(bool fahrenheit READ fahrenheit CONSTANT)
    Q_PROPERTY(bool milesPerHour READ milesPerHour CONSTANT)

  public:
    static const QString &serviceName();
    static WeatherClient *create(QQmlEngine *engine, QJSEngine *);

    explicit WeatherClient(const QDBusConnection &bus, QObject *parent = nullptr);

    QVariantMap forecast() const {
        return m_forecast;
    }
    QString state() const {
        return m_state;
    }
    bool fahrenheit() const;
    bool milesPerHour() const;

    // Reads the current values, then asks for newer ones; starts the service.
    Q_INVOKABLE void refresh();
    // Answers with searchFinished.
    Q_INVOKABLE void search(const QString &query);
    // A place from search(): {name, region, latitude, longitude}.
    Q_INVOKABLE void setLocation(const QVariantMap &place);
    Q_INVOKABLE void setAutomatic();

  signals:
    void forecastChanged();
    void stateChanged();
    void searchFinished(const QVariantList &places, const QString &error);

  private slots:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);

  private:
    void            apply(const QVariantMap &properties);
    void            call(const QString &method, const QVariantList &args = {});

    QDBusConnection m_bus;
    QVariantMap     m_forecast;
    QString         m_forecastJson;
    QString         m_state;
};

#endif
