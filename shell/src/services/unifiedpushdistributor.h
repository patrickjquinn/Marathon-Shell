#ifndef UNIFIEDPUSHDISTRIBUTOR_H
#define UNIFIEDPUSHDISTRIBUTOR_H

#include <QObject>
#include <QHash>
#include <QString>
#include <QVariantMap>

// UnifiedPush distributor (server side, per spec v2). Apps call Register/
// Unregister on us via D-Bus; when a push backend delivers a message we
// invoke Message/NewEndpoint/Unregistered on the app's Connector2 object.
//
// Spec: https://unifiedpush.org/developers/spec/dbus/
//
// Bus name: org.unifiedpush.Distributor.marathon
// Object path: /org/unifiedpush/Distributor
// Interface: org.unifiedpush.Distributor2
//
// This is the local D-Bus surface only. The backend (WebSocket/HTTP to
// a push gateway like ntfy) plugs in via deliverEndpoint/deliverMessage
// and will arrive in a follow-up commit.
class UnifiedPushDistributor : public QObject {
    Q_OBJECT

  public:
    explicit UnifiedPushDistributor(QObject *parent = nullptr);
    ~UnifiedPushDistributor() override;

    // Acquire org.unifiedpush.Distributor.marathon on the session bus and
    // export this object at /org/unifiedpush/Distributor. Returns false if
    // another distributor already owns the well-known name (in which case
    // we yield -- the user picked a different distributor).
    bool registerService();

  public slots:
    // D-Bus methods exposed under org.unifiedpush.Distributor2.
    // Arg dict per spec: "service" (s), "token" (s), optional "description" (s),
    // optional "vapid" (s). Return dict: "success" (s) = "OK" or
    // "NETWORK"/"INTERNAL_ERROR"/etc; "reason" (s) on failure.
    QVariantMap Register(const QVariantMap &args);
    QVariantMap Unregister(const QVariantMap &args);

  public:
    // Backend wiring. Called by whatever speaks to the upstream push
    // server (ntfy, etc.) once it has an endpoint URL or an inbound
    // message for one of our registered tokens. Not exported on D-Bus.
    void deliverEndpoint(const QString &token, const QString &endpoint);
    void deliverMessage(const QString &token, const QByteArray &payload);

  signals:
    // A token is now expected to have a backend subscription. Emitted for
    // every Register call AND once per persisted registration at startup
    // so backends can resume previously-opened subscriptions without a
    // re-Register round trip. `endpoint` is empty for fresh registrations
    // and populated for resumed ones (the backend should re-use the same
    // endpoint URL rather than minting a new one).
    void registrationActive(const QString &token, const QString &endpoint);

    // The backend should drop the subscription for this token.
    void registrationRemoved(const QString &token);

  private:
    struct AppRegistration {
        QString service;     // app's well-known D-Bus name (e.g. org.example.app)
        QString description; // optional human label
        QString endpoint;    // last endpoint URL delivered, may be empty
    };

    void callConnector(const QString &serviceBus, const QString &method, const QVariantMap &args);
    void persist() const;
    void load();

    QHash<QString, AppRegistration> m_registrations; // token -> reg
    bool                            m_serviceOwned = false;
};

#endif
