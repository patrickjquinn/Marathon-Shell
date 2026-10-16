#include "mpris2controller.h"
#include <QDebug>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <utility>   // std::as_const

namespace {
    const QString kPrefix     = QStringLiteral("org.mpris.MediaPlayer2.");
    const QString kPath       = QStringLiteral("/org/mpris/MediaPlayer2");
    const QString kRoot       = QStringLiteral("org.mpris.MediaPlayer2");
    const QString kPlayer     = QStringLiteral("org.mpris.MediaPlayer2.Player");
    const QString kProperties = QStringLiteral("org.freedesktop.DBus.Properties");
    const QString kBus        = QStringLiteral("org.freedesktop.DBus");
    const QString kBusPath    = QStringLiteral("/org/freedesktop/DBus");

    QVariant unwrap(const QVariant &v) {
        if (v.userType() == qMetaTypeId<QDBusVariant>())
            return v.value<QDBusVariant>().variant();
        return v;
    }

    QVariantMap toMap(const QVariant &value) {
        const QVariant v = unwrap(value);
        if (v.userType() == qMetaTypeId<QDBusArgument>())
            return qdbus_cast<QVariantMap>(v.value<QDBusArgument>());
        return v.toMap();
    }

    QStringList toStringList(const QVariant &value) {
        const QVariant v = unwrap(value);
        if (v.userType() == qMetaTypeId<QDBusArgument>())
            return qdbus_cast<QStringList>(v.value<QDBusArgument>());
        if (v.canConvert<QStringList>())
            return v.toStringList();
        return {v.toString()};
    }

    QString toPath(const QVariant &value) {
        const QVariant v = unwrap(value);
        if (v.userType() == qMetaTypeId<QDBusObjectPath>())
            return v.value<QDBusObjectPath>().path();
        return v.toString();
    }
}

MPRIS2Controller::MPRIS2Controller(QObject *parent)
    : QObject(parent)
    , m_positionTimer(new QTimer(this))
    , m_hasActivePlayer(false)
    , m_playbackStatus("Stopped")
    , m_trackLength(0)
    , m_position(0)
    , m_canPlay(false)
    , m_canPause(false)
    , m_canGoNext(false)
    , m_canGoPrevious(false)
    , m_canSeek(false) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kBus, kBusPath, kBus, "NameOwnerChanged", this,
                SLOT(onNameOwnerChanged(QString, QString, QString)));
    // Any sender: naming the player's well-known name makes QtDBus resolve
    // its owner synchronously. The slot filters on the current owner.
    bus.connect(QString(), kPath, kProperties, "PropertiesChanged", this,
                SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));

    m_positionTimer->setInterval(1000);
    connect(m_positionTimer, &QTimer::timeout, this, &MPRIS2Controller::pollPosition);

    // Players already on the bus; later ones arrive by NameOwnerChanged.
    scanForPlayers();
}

MPRIS2Controller::~MPRIS2Controller() = default;

void MPRIS2Controller::callAsync(const QDBusMessage                              &call,
                                 const std::function<void(const QDBusMessage &)> &onReply) {
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, onReply] {
        watcher->deleteLater();
        if (watcher->isError()) {
            qDebug() << "[MPRIS2Controller]" << watcher->error().message();
            return;
        }
        onReply(watcher->reply());
    });
}

void MPRIS2Controller::callPlayer(const QString &method, const QVariantList &args) {
    if (!m_hasActivePlayer)
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(m_currentBusName, kPath, kPlayer, method);
    call.setArguments(args);
    QDBusConnection::sessionBus().send(call);
}

void MPRIS2Controller::getAll(const QString &interface) {
    const QString busName = m_currentBusName;
    QDBusMessage  call = QDBusMessage::createMethodCall(busName, kPath, kProperties, "GetAll");
    call << interface;
    callAsync(call, [this, busName, interface](const QDBusMessage &reply) {
        if (busName != m_currentBusName || reply.arguments().isEmpty())
            return;
        const QVariantMap props = toMap(reply.arguments().constFirst());
        if (interface == kRoot) {
            applyRootProperties(props);
            return;
        }
        applyPlayerProperties(props);
        if (!m_hasActivePlayer) {
            m_hasActivePlayer = true;
            m_positionTimer->start();
            qInfo() << "[MPRIS2Controller] Connected to" << m_playerName;
            emit activePlayerChanged();
        }
    });
}

// Players that don't emit PropertiesChanged for a command still settle.
void MPRIS2Controller::refreshSoon() {
    QTimer::singleShot(150, this, [this] {
        if (!m_currentBusName.isEmpty())
            getAll(kPlayer);
    });
}

void MPRIS2Controller::scanForPlayers() {
    callAsync(QDBusMessage::createMethodCall(kBus, kBusPath, kBus, "ListNames"),
              [this](const QDBusMessage &reply) {
                  if (!reply.arguments().isEmpty())
                      onPlayerList(reply.arguments().constFirst().toStringList());
              });
}

void MPRIS2Controller::onPlayerList(const QStringList &names) {
    QStringList players;
    for (const QString &name : names) {
        if (name.startsWith(kPrefix))
            players.append(name);
    }
    if (players != m_availablePlayers) {
        m_availablePlayers = players;
        emit playerListChanged(m_availablePlayers);
    }
    if (!m_currentBusName.isEmpty() && !players.contains(m_currentBusName))
        disconnectFromPlayer();
    if (m_currentBusName.isEmpty() && !players.isEmpty())
        connectToPlayer(players.constFirst());
}

void MPRIS2Controller::onNameOwnerChanged(const QString &name, const QString &oldOwner,
                                          const QString &newOwner) {
    Q_UNUSED(oldOwner);
    if (!name.startsWith(kPrefix))
        return;
    if (name == m_currentBusName)
        disconnectFromPlayer();
    if (m_currentBusName.isEmpty() && !newOwner.isEmpty()) {
        connectToPlayer(name);
        m_currentOwner = newOwner;
    }
    scanForPlayers();
}

void MPRIS2Controller::connectToPlayer(const QString &busName) {
    qInfo() << "[MPRIS2Controller] Connecting to player:" << busName;
    m_currentBusName = busName;
    m_currentOwner.clear();

    QString name = busName.mid(kPrefix.size());
    name         = name.left(name.indexOf('.'));
    m_playerName = name.left(1).toUpper() + name.mid(1);
    m_desktopEntry = name.toLower();

    QDBusMessage owner = QDBusMessage::createMethodCall(kBus, kBusPath, kBus, "GetNameOwner");
    owner << busName;
    callAsync(owner, [this, busName](const QDBusMessage &reply) {
        if (busName == m_currentBusName && !reply.arguments().isEmpty())
            m_currentOwner = reply.arguments().constFirst().toString();
    });
    getAll(kRoot);
    getAll(kPlayer);
}

void MPRIS2Controller::disconnectFromPlayer() {
    const bool wasActive = m_hasActivePlayer;
    m_positionTimer->stop();
    m_currentBusName.clear();
    m_currentOwner.clear();
    m_hasActivePlayer = false;
    m_playerName.clear();
    m_desktopEntry.clear();
    m_playbackStatus = "Stopped";
    if (wasActive) {
        emit activePlayerChanged();
        emit playbackStatusChanged();
    }
}

void MPRIS2Controller::onPropertiesChanged(const QString     &interfaceName,
                                           const QVariantMap &changedProperties,
                                           const QStringList &invalidatedProperties) {
    Q_UNUSED(invalidatedProperties);
    if (m_currentOwner.isEmpty() || (calledFromDBus() && message().service() != m_currentOwner))
        return;
    if (interfaceName == kPlayer)
        applyPlayerProperties(changedProperties);
    else if (interfaceName == kRoot)
        applyRootProperties(changedProperties);
}

void MPRIS2Controller::applyRootProperties(const QVariantMap &props) {
    const QString entry = unwrap(props.value("DesktopEntry")).toString();
    const QString identity = unwrap(props.value("Identity")).toString();
    bool          changed  = false;
    if (!entry.isEmpty() && entry != m_desktopEntry) {
        m_desktopEntry = entry;
        changed        = true;
    }
    if (!identity.isEmpty() && identity != m_playerName) {
        m_playerName = identity;
        changed      = true;
    }
    if (changed && m_hasActivePlayer)
        emit activePlayerChanged();
}

void MPRIS2Controller::applyPlayerProperties(const QVariantMap &props) {
    if (props.contains("PlaybackStatus")) {
        const QString status = unwrap(props.value("PlaybackStatus")).toString();
        if (!status.isEmpty() && status != m_playbackStatus) {
            m_playbackStatus = status;
            emit playbackStatusChanged();
        }
    }

    bool capsChanged = false;
    auto cap         = [&](const char *key, bool &field) {
        if (!props.contains(key))
            return;
        const bool v = unwrap(props.value(key)).toBool();
        if (v != field) {
            field       = v;
            capsChanged = true;
        }
    };
    cap("CanPlay", m_canPlay);
    cap("CanPause", m_canPause);
    cap("CanGoNext", m_canGoNext);
    cap("CanGoPrevious", m_canGoPrevious);
    cap("CanSeek", m_canSeek);
    if (capsChanged)
        emit capabilitiesChanged();

    if (props.contains("Metadata"))
        applyMetadata(toMap(props.value("Metadata")));

    if (props.contains("Position")) {
        const qint64 pos = unwrap(props.value("Position")).toLongLong();
        if (pos != m_position) {
            m_position = pos;
            emit positionChanged();
        }
    }
}

void MPRIS2Controller::applyMetadata(const QVariantMap &metadata) {
    const QStringList artists = toStringList(metadata.value("xesam:artist"));
    const QString     title   = unwrap(metadata.value("xesam:title")).toString();
    const QString     artist  = artists.isEmpty() ? QString() : artists.constFirst();
    const QString album  = unwrap(metadata.value("xesam:album")).toString();
    const QString artUrl = unwrap(metadata.value("mpris:artUrl")).toString();
    const qint64  length = unwrap(metadata.value("mpris:length")).toLongLong();
    m_trackId            = toPath(metadata.value("mpris:trackid"));

    if (title == m_trackTitle && artist == m_trackArtist && album == m_trackAlbum &&
        artUrl == m_albumArtUrl && length == m_trackLength)
        return;
    m_trackTitle  = title;
    m_trackArtist = artist;
    m_trackAlbum  = album;
    m_albumArtUrl = artUrl;
    m_trackLength = length;
    emit metadataChanged();
}

void MPRIS2Controller::pollPosition() {
    if (!m_hasActivePlayer || m_playbackStatus != "Playing" || m_positionInFlight)
        return;
    m_positionInFlight    = true;
    const QString busName = m_currentBusName;
    QDBusMessage  call    = QDBusMessage::createMethodCall(busName, kPath, kProperties, "Get");
    call << kPlayer << QStringLiteral("Position");
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, busName] {
        watcher->deleteLater();
        m_positionInFlight = false;
        const QDBusMessage reply = watcher->reply();
        if (watcher->isError() || busName != m_currentBusName || reply.arguments().isEmpty())
            return;
        applyPlayerProperties({{"Position", unwrap(reply.arguments().constFirst())}});
    });
}

void MPRIS2Controller::play() {
    if (!m_canPlay)
        return;
    callPlayer("Play");
    refreshSoon();
}

void MPRIS2Controller::pause() {
    if (!m_canPause)
        return;
    callPlayer("Pause");
    refreshSoon();
}

void MPRIS2Controller::playPause() {
    callPlayer("PlayPause");
    refreshSoon();
}

void MPRIS2Controller::stop() {
    callPlayer("Stop");
    refreshSoon();
}

void MPRIS2Controller::next() {
    const qint64 podcastThreshold = qint64{20} * 60 * 1000000;
    if (m_canSeek && m_trackLength > podcastThreshold) {
        seek(30000000);
    } else if (m_canGoNext) {
        callPlayer("Next");
        refreshSoon();
    }
}

void MPRIS2Controller::previous() {
    const qint64 podcastThreshold = qint64{20} * 60 * 1000000;
    if (m_canSeek && m_trackLength > podcastThreshold) {
        seek(-10000000);
    } else if (m_canGoPrevious) {
        callPlayer("Previous");
        refreshSoon();
    }
}

void MPRIS2Controller::seek(qint64 offset) {
    if (!m_canSeek)
        return;
    callPlayer("Seek", {offset});
    pollPosition();
}

void MPRIS2Controller::setPosition(qint64 position) {
    if (!m_canSeek || m_trackId.isEmpty())
        return;
    callPlayer("SetPosition", {QVariant::fromValue(QDBusObjectPath(m_trackId)), position});
    pollPosition();
}
