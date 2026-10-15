#ifndef PILOTCLIENT_H
#define PILOTCLIENT_H

#include <QDBusConnection>
#include <QObject>
#include <QTimer>

#include <qqml.h>

// Shipwright Pilot's session service, org.shipwright.Pilot (pilotd).
class PilotClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // Pilot can be asked: its service is activatable or on the bus.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // Re-check availability every 30 s while true (unlocked).
    Q_PROPERTY(bool watching READ watching WRITE setWatching NOTIFY watchingChanged)

  public:
    static const QString &serviceName();
    static PilotClient   *create(QQmlEngine *engine, QJSEngine *);

    explicit PilotClient(const QDBusConnection &bus, QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool watching() const {
        return m_poll.isActive();
    }
    void             setWatching(bool watching);

    Q_INVOKABLE void check();
    // The sheet over the app whose process is `pid` (0: the home screen);
    // an older pilotd without ShowSheetFor gets ShowSheet.
    Q_INVOKABLE void showSheetFor(uint pid);

  signals:
    void availableChanged();
    void watchingChanged();

  private:
    void            setAvailable(bool available);

    QDBusConnection m_bus;
    QTimer          m_poll;
    bool            m_available = false;
};

#endif
