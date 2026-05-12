#ifndef MARATHONNTFYCLIENT_H
#define MARATHONNTFYCLIENT_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QUrl>

class QWebSocket;
class QTimer;
class UnifiedPushDistributor;

// UnifiedPush backend that bridges our distributor to an ntfy server (default
// https://ntfy.sh, overridable for self-hosted). One WebSocket per registered
// token, subscribed to that token's randomly-assigned ntfy topic.
//
// Endpoint contract (what an app's server sees as the URL to POST to):
//   https://<server>/<topic>
// Subscription contract (what we connect to receive inbound messages):
//   wss://<server>/<topic>/ws
//
// Topic strings are generated locally per token and persisted as part of the
// endpoint URL the distributor already records; on restart we parse the topic
// back out of the endpoint and resume the same subscription without minting
// a new one (so the app's server keeps pushing to the same URL).
class MarathonNtfyClient : public QObject {
    Q_OBJECT

  public:
    explicit MarathonNtfyClient(UnifiedPushDistributor *distributor, QObject *parent = nullptr);
    ~MarathonNtfyClient() override;

    // Override at construction time via env var MARATHON_NTFY_SERVER or
    // before any registrations land. Default: https://ntfy.sh.
    void setServer(const QUrl &serverUrl);

  private slots:
    void onRegistrationActive(const QString &token, const QString &endpoint);
    void onRegistrationRemoved(const QString &token);

  private:
    struct Subscription {
        QString     topic;
        QWebSocket *socket            = nullptr;
        QTimer     *backoff           = nullptr;
        int         retryMs           = 1000;
        bool        endpointDelivered = false;
    };

    QString                      endpointFor(const QString &topic) const;
    QString                      topicFromEndpoint(const QString &endpoint) const;
    QString                      mintTopic() const;

    void                         openSocket(const QString &token);
    void                         onSocketConnected(const QString &token);
    void                         onSocketTextMessage(const QString &token, const QString &json);
    void                         onSocketDisconnected(const QString &token);

    UnifiedPushDistributor      *m_distributor;
    QUrl                         m_server;
    QHash<QString, Subscription> m_subs; // token -> sub
};

#endif
