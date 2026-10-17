#ifndef GEOCLUEAGENT_H
#define GEOCLUEAGENT_H

#include <QDBusConnection>
#include <QObject>
#include <functional>

// The shell as GeoClue's agent, as GNOME Shell and Phosh are. GeoClue holds
// every client of a user with no agent, so without one nothing on the device
// ever gets a location. GeoClue exits when idle and forgets its agents, so
// the agent registers again each time the service starts.
class GeoClueAgent : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.GeoClue2.Agent")
    Q_PROPERTY(uint MaxAccuracyLevel READ maxAccuracyLevel)

  public:
    using Authorizer = std::function<bool(const QString &desktopId)>;

    GeoClueAgent(const QDBusConnection &bus, Authorizer authorize, QObject *parent = nullptr);

    static const QString &agentId();

    uint maxAccuracyLevel() const;

  public slots:
    bool AuthorizeApp(const QString &desktopId, uint requestedAccuracy, uint &allowedAccuracy);

  signals:
    void registered();

  private:
    void addAgent();

    QDBusConnection m_bus;
    Authorizer      m_authorize;
};

#endif // GEOCLUEAGENT_H
