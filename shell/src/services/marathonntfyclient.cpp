#include "marathonntfyclient.h"
#include "unifiedpushdistributor.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QTimer>
#include <QWebSocket>

namespace {
    constexpr int kBackoffMaxMs = 60'000;

    QUrl          defaultServer() {
        const QByteArray override = qgetenv("MARATHON_NTFY_SERVER");
        if (!override.isEmpty()) {
            return QUrl(QString::fromUtf8(override));
        }
        return QUrl(QStringLiteral("https://ntfy.sh"));
    }
} // namespace

MarathonNtfyClient::MarathonNtfyClient(UnifiedPushDistributor *distributor, QObject *parent)
    : QObject(parent)
    , m_distributor(distributor)
    , m_server(defaultServer()) {
    connect(distributor, &UnifiedPushDistributor::registrationActive, this,
            &MarathonNtfyClient::onRegistrationActive);
    connect(distributor, &UnifiedPushDistributor::registrationRemoved, this,
            &MarathonNtfyClient::onRegistrationRemoved);
    qInfo() << "[MarathonNtfyClient] server" << m_server.toString();
}

MarathonNtfyClient::~MarathonNtfyClient() {
    for (auto &sub : m_subs) {
        if (sub.socket)
            sub.socket->abort();
    }
}

void MarathonNtfyClient::setServer(const QUrl &serverUrl) {
    m_server = serverUrl;
}

QString MarathonNtfyClient::mintTopic() const {
    // 16 lowercase alphanumeric chars: collision-resistant on ntfy's global
    // topic namespace and short enough to be visible in the endpoint URL.
    static const char kAlphabet[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    QString           s;
    s.reserve(16);
    for (int i = 0; i < 16; ++i) {
        s.append(QLatin1Char(kAlphabet[QRandomGenerator::global()->bounded(36)]));
    }
    return s;
}

QString MarathonNtfyClient::endpointFor(const QString &topic) const {
    QUrl u = m_server;
    u.setScheme(QStringLiteral("https"));
    u.setPath(QStringLiteral("/") + topic);
    return u.toString();
}

QString MarathonNtfyClient::topicFromEndpoint(const QString &endpoint) const {
    const QUrl u(endpoint);
    QString    path = u.path();
    if (path.startsWith(QLatin1Char('/')))
        path.remove(0, 1);
    return path;
}

void MarathonNtfyClient::onRegistrationActive(const QString &token, const QString &endpoint) {
    if (m_subs.contains(token))
        return;

    Subscription sub;
    if (endpoint.isEmpty()) {
        sub.topic             = mintTopic();
        sub.endpointDelivered = false;
    } else {
        sub.topic             = topicFromEndpoint(endpoint);
        sub.endpointDelivered = true;
    }
    if (sub.topic.isEmpty()) {
        qWarning() << "[MarathonNtfyClient] empty topic for token" << token;
        return;
    }
    m_subs.insert(token, sub);
    openSocket(token);
}

void MarathonNtfyClient::onRegistrationRemoved(const QString &token) {
    const auto it = m_subs.find(token);
    if (it == m_subs.end())
        return;

    // Detach the socket/timer pointers and remove the entry FIRST, because
    // QWebSocket::abort() emits `disconnected` synchronously, which fires
    // onSocketDisconnected on this same token. If the entry still exists at
    // that moment, the disconnect handler dereferences the socket field we
    // just nulled and corrupts the backoff timer we just deleted.
    QWebSocket *sock = it->socket;
    QTimer     *bo   = it->backoff;
    m_subs.erase(it);

    if (bo) {
        bo->stop();
        bo->deleteLater();
    }
    if (sock) {
        sock->abort();
        sock->deleteLater();
    }
}

void MarathonNtfyClient::openSocket(const QString &token) {
    auto it = m_subs.find(token);
    if (it == m_subs.end())
        return;

    QUrl ws = m_server;
    ws.setScheme(m_server.scheme() == QStringLiteral("http") ? QStringLiteral("ws") :
                                                               QStringLiteral("wss"));
    ws.setPath(QStringLiteral("/") + it->topic + QStringLiteral("/ws"));

    auto *socket = new QWebSocket();
    it->socket   = socket;

    connect(socket, &QWebSocket::connected, this, [this, token] { onSocketConnected(token); });
    connect(socket, &QWebSocket::textMessageReceived, this,
            [this, token](const QString &m) { onSocketTextMessage(token, m); });
    connect(socket, &QWebSocket::disconnected, this,
            [this, token] { onSocketDisconnected(token); });
    connect(socket, &QWebSocket::errorOccurred, this, [token](QAbstractSocket::SocketError e) {
        qWarning() << "[MarathonNtfyClient] socket error" << token << e;
    });

    qInfo() << "[MarathonNtfyClient] opening" << ws.toString();
    socket->open(ws);
}

void MarathonNtfyClient::onSocketConnected(const QString &token) {
    auto it = m_subs.find(token);
    if (it == m_subs.end())
        return;
    it->retryMs = 1000; // reset backoff on successful connect

    if (!it->endpointDelivered) {
        m_distributor->deliverEndpoint(token, endpointFor(it->topic));
        it->endpointDelivered = true;
    }
    qInfo() << "[MarathonNtfyClient] subscribed" << token << "->" << it->topic;
}

void MarathonNtfyClient::onSocketTextMessage(const QString &token, const QString &json) {
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject())
        return;
    const QJsonObject obj = doc.object();
    const QString     ev  = obj.value(QStringLiteral("event")).toString();
    // ntfy emits "open" / "keepalive" / "message" / "poll_request". We only
    // care about "message"; the others keep the WS warm and are dropped.
    if (ev != QStringLiteral("message"))
        return;

    const QByteArray payload = obj.value(QStringLiteral("message")).toString().toUtf8();
    m_distributor->deliverMessage(token, payload);
}

void MarathonNtfyClient::onSocketDisconnected(const QString &token) {
    auto it = m_subs.find(token);
    if (it == m_subs.end())
        return;
    if (it->socket) {
        it->socket->deleteLater();
        it->socket = nullptr;
    }
    if (!it->backoff) {
        it->backoff = new QTimer(this);
        it->backoff->setSingleShot(true);
        connect(it->backoff, &QTimer::timeout, this, [this, token] { openSocket(token); });
    }
    const int delay = it->retryMs;
    it->retryMs     = std::min(it->retryMs * 2, kBackoffMaxMs);
    it->backoff->start(delay);
    qInfo() << "[MarathonNtfyClient] retry" << token << "in" << delay << "ms";
}
