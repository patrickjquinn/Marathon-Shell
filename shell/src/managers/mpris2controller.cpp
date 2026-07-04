#include "mpris2controller.h"
#include <QDebug>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QUrl>

MPRIS2Controller::MPRIS2Controller(QObject *parent)
    : QObject(parent)
    , m_playerInterface(nullptr)
    , m_positionTimer(nullptr)
    , m_hasActivePlayer(false)
    , m_playerName("")
    , m_desktopEntry("")
    , m_playbackStatus("Stopped")
    , m_trackTitle("")
    , m_trackArtist("")
    , m_trackAlbum("")
    , m_albumArtUrl("")
    , m_trackLength(0)
    , m_position(0)
    , m_canPlay(false)
    , m_canPause(false)
    , m_canGoNext(false)
    , m_canGoPrevious(false)
    , m_canSeek(false) {
    qDebug() << "[MPRIS2Controller] Initializing";

    setupDBusMonitoring();

    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(1000);
    connect(m_positionTimer, &QTimer::timeout, this, &MPRIS2Controller::updatePosition);

    // scanForPlayers() at startup catches players already on the bus when
    // the shell starts; setupDBusMonitoring() above subscribes to
    // NameOwnerChanged so new players are detected the moment they
    // register. A periodic poll on top was pure overhead — wake up every
    // 10s, scan the entire D-Bus session-bus name list, find nothing new.
    // Removed 2026-06-25 after observing ~2 D-Bus round-trips/s at idle.
    scanForPlayers();

    qInfo() << "[MPRIS2Controller] Initialized and monitoring for media players";
}

MPRIS2Controller::~MPRIS2Controller() {
    disconnectFromPlayer();
}

void MPRIS2Controller::setupDBusMonitoring() {

    QDBusConnection::sessionBus().connect("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                          "org.freedesktop.DBus", "NameOwnerChanged", this,
                                          SLOT(onNameOwnerChanged(QString, QString, QString)));

    qDebug() << "[MPRIS2Controller] D-Bus monitoring enabled";
}

void MPRIS2Controller::onNameOwnerChanged(const QString &name, const QString &oldOwner,
                                          const QString &newOwner) {
    Q_UNUSED(oldOwner);

    if (!name.startsWith("org.mpris.MediaPlayer2."))
        return;

    if (newOwner.isEmpty()) {
        qDebug() << "[MPRIS2Controller] Media player removed:" << name;
    } else {
        qDebug() << "[MPRIS2Controller] New media player detected:" << name;
    }

    // Defer the rescan to a fresh event-loop turn. scanForPlayers() ->
    // connectToPlayer() constructs a QDBusInterface, whose ctor makes a
    // BLOCKING introspection call on the session bus. Running that
    // reentrantly from inside this NameOwnerChanged dispatch fails
    // (QDBusInterface::isValid() comes back false) and the player is
    // dropped with no retry -- so a player that registers while the shell
    // is already running is seen but never adopted, and the NowBar stays
    // "Nothing playing". Only players present at startup were picked up,
    // because that scan runs from the ctor (not reentrant). The queued
    // singleShot(0) breaks the reentrancy: the scan runs after this
    // dispatch unwinds, when a blocking introspection call is safe.
    // (Removal needs no introspection, so it worked either way.)
    QTimer::singleShot(0, this, &MPRIS2Controller::scanForPlayers);
}

void MPRIS2Controller::scanForPlayers() {

    QDBusMessage call = QDBusMessage::createMethodCall(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames");

    QDBusReply<QStringList> reply = QDBusConnection::sessionBus().call(call);

    if (!reply.isValid()) {
        return;
    }

    QStringList services = reply.value();
    QStringList mprisPlayers;

    for (const QString &service : services) {
        if (service.startsWith("org.mpris.MediaPlayer2.")) {
            mprisPlayers.append(service);
        }
    }

    if (mprisPlayers != m_availablePlayers) {
        m_availablePlayers = mprisPlayers;
        emit playerListChanged(m_availablePlayers);

        qDebug() << "[MPRIS2Controller] Found" << mprisPlayers.size()
                 << "media players:" << mprisPlayers;
    }

    if (!m_hasActivePlayer && !mprisPlayers.isEmpty()) {
        connectToPlayer(mprisPlayers.first());
    }

    if (m_hasActivePlayer && !mprisPlayers.contains(m_currentBusName)) {
        qInfo() << "[MPRIS2Controller] Current player" << m_currentBusName << "disappeared";
        disconnectFromPlayer();

        if (!mprisPlayers.isEmpty()) {
            connectToPlayer(mprisPlayers.first());
        }
    }
}

void MPRIS2Controller::connectToPlayer(const QString &busName) {
    qInfo() << "[MPRIS2Controller] Connecting to player:" << busName;

    disconnectFromPlayer();

    m_playerInterface =
        new QDBusInterface(busName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player",
                           QDBusConnection::sessionBus(), this);

    if (!m_playerInterface->isValid()) {
        qWarning() << "[MPRIS2Controller] Failed to connect to" << busName << ":"
                   << m_playerInterface->lastError().message();
        // m_playerInterface is parented to this; Qt will delete it on destruction
        m_playerInterface = nullptr;
        return;
    }

    m_currentBusName  = busName;
    m_hasActivePlayer = true;

    QString name = busName;
    name.remove("org.mpris.MediaPlayer2.");
    int dotIndex = name.indexOf('.');
    if (dotIndex != -1) {
        name = name.left(dotIndex);
    }
    m_playerName = name.at(0).toUpper() + name.mid(1);

    QDBusInterface rootInterface(busName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2",
                                 QDBusConnection::sessionBus());
    if (rootInterface.isValid()) {
        m_desktopEntry = rootInterface.property("DesktopEntry").toString();
    } else {
        m_desktopEntry.clear();
    }

    if (m_desktopEntry.isEmpty()) {

        m_desktopEntry = name.toLower();
    }

    qInfo() << "[MPRIS2Controller] App ID (DesktopEntry):" << m_desktopEntry;

    qInfo() << "[MPRIS2Controller] Connected to" << m_playerName;

    QDBusConnection::sessionBus().connect(
        busName, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged",
        this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));

    updatePlaybackStatus();
    updateMetadata();
    updateCapabilities();
    updatePosition();

    m_positionTimer->start();

    // No metadata-refresh timer. The PropertiesChanged subscription set
    // up at the top of this function delivers every title / artist /
    // album / artwork change push-style (mandated by the MPRIS2 spec).
    // The previous 2-second poll was burning ~43200 D-Bus calls/day per
    // player for a property set that, in steady state, doesn't change
    // for the duration of the track. If a player ships a broken
    // PropertiesChanged emitter, that's an upstream bug to fix in the
    // player — not a justification to poll forever in every host.

    emit activePlayerChanged();
}

void MPRIS2Controller::disconnectFromPlayer() {
    if (m_playerInterface) {

        if (!m_currentBusName.isEmpty()) {
            QDBusConnection::sessionBus().disconnect(
                m_currentBusName, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties",
                "PropertiesChanged", this,
                SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        }

        m_positionTimer->stop();
        // m_playerInterface is parented to this; Qt will delete it on destruction
        m_playerInterface = nullptr;
        m_currentBusName.clear();
        m_hasActivePlayer = false;
        m_playerName.clear();
        m_desktopEntry.clear();
        m_playbackStatus = "Stopped";

        emit activePlayerChanged();
        emit playbackStatusChanged();

        qDebug() << "[MPRIS2Controller] Disconnected from player";
    }
}

void MPRIS2Controller::onPropertiesChanged(const QString     &interfaceName,
                                           const QVariantMap &changedProperties,
                                           const QStringList &invalidatedProperties) {
    Q_UNUSED(invalidatedProperties);

    if (interfaceName != "org.mpris.MediaPlayer2.Player")
        return;

    if (changedProperties.contains("PlaybackStatus")) {
        const QString status = changedProperties.value("PlaybackStatus").toString();
        if (!status.isEmpty() && status != m_playbackStatus) {
            m_playbackStatus = status;
            emit playbackStatusChanged();
            qDebug() << "[MPRIS2Controller] Playback status:" << status;
        }
    }

    if (changedProperties.contains("CanPlay") || changedProperties.contains("CanPause") ||
        changedProperties.contains("CanGoNext") || changedProperties.contains("CanGoPrevious") ||
        changedProperties.contains("CanSeek")) {
        updateCapabilities();
    }

    if (changedProperties.contains("Metadata")) {
        updateMetadata();
    }
}

void MPRIS2Controller::updatePlaybackStatus() {
    if (!m_playerInterface)
        return;

    QDBusMessage call = QDBusMessage::createMethodCall(m_currentBusName, "/org/mpris/MediaPlayer2",
                                                       "org.freedesktop.DBus.Properties", "Get");
    call << "org.mpris.MediaPlayer2.Player" << "PlaybackStatus";

    QDBusReply<QDBusVariant> reply = QDBusConnection::sessionBus().call(call);
    QString                  status;
    if (reply.isValid()) {
        status = reply.value().variant().toString();
    } else {

        status = m_playerInterface->property("PlaybackStatus").toString();
    }

    if (!status.isEmpty() && status != m_playbackStatus) {
        m_playbackStatus = status;
        emit playbackStatusChanged();
        qDebug() << "[MPRIS2Controller] Playback status:" << status;
    }
}

void MPRIS2Controller::updateMetadata() {
    if (!m_playerInterface)
        return;

    QDBusMessage call = QDBusMessage::createMethodCall(m_currentBusName, "/org/mpris/MediaPlayer2",
                                                       "org.freedesktop.DBus.Properties", "Get");
    call << "org.mpris.MediaPlayer2.Player" << "Metadata";

    QDBusReply<QDBusVariant> reply = QDBusConnection::sessionBus().call(call);
    QVariantMap              metadata;

    if (reply.isValid()) {

        QVariant innerValue = reply.value().variant();

        if (innerValue.canConvert<QVariantMap>()) {
            metadata = innerValue.value<QVariantMap>();
        } else if (innerValue.canConvert<QDBusArgument>()) {

            QDBusArgument arg = innerValue.value<QDBusArgument>();
            if (arg.currentType() == QDBusArgument::MapType) {
                arg >> metadata;
            }
        }
    } else {

        QVariant val = m_playerInterface->property("Metadata");
        if (val.canConvert<QVariantMap>()) {
            metadata = val.value<QVariantMap>();
        } else if (val.canConvert<QDBusArgument>()) {
            const QDBusArgument arg = val.value<QDBusArgument>();
            arg >> metadata;
        }
    }

    QString     title   = extractMetadataString(metadata, "xesam:title");
    QStringList artists = extractMetadataStringList(metadata, "xesam:artist");
    QString     artist  = artists.isEmpty() ? "" : artists.first();
    QString     album   = extractMetadataString(metadata, "xesam:album");
    QString     artUrl  = extractMetadataString(metadata, "mpris:artUrl");
    qint64      length  = extractMetadataInt64(metadata, "mpris:length");

    bool        changed = false;

    if (title != m_trackTitle) {
        m_trackTitle = title;
        changed      = true;
    }

    if (artist != m_trackArtist) {
        m_trackArtist = artist;
        changed       = true;
    }

    if (album != m_trackAlbum) {
        m_trackAlbum = album;
        changed      = true;
    }

    if (artUrl != m_albumArtUrl) {
        m_albumArtUrl = artUrl;
        changed       = true;
    }

    if (length != m_trackLength) {
        m_trackLength = length;
        changed       = true;
    }

    if (changed) {
        emit metadataChanged();
        qDebug() << "[MPRIS2Controller] Now playing:" << m_trackArtist << "-" << m_trackTitle;
    }
}

void MPRIS2Controller::updatePosition() {
    if (!m_playerInterface || m_playbackStatus != "Playing") {
        return;
    }

    QDBusMessage call = QDBusMessage::createMethodCall(m_currentBusName, "/org/mpris/MediaPlayer2",
                                                       "org.freedesktop.DBus.Properties", "Get");
    call << "org.mpris.MediaPlayer2.Player" << "Position";

    QDBusReply<QDBusVariant> reply = QDBusConnection::sessionBus().call(call);
    if (!reply.isValid())
        return;

    const qint64 pos = reply.value().variant().toLongLong();
    if (pos != m_position) {
        m_position = pos;
        emit positionChanged();
    }
}

void MPRIS2Controller::updateCapabilities() {
    if (!m_playerInterface)
        return;

    bool canPlay       = m_playerInterface->property("CanPlay").toBool();
    bool canPause      = m_playerInterface->property("CanPause").toBool();
    bool canGoNext     = m_playerInterface->property("CanGoNext").toBool();
    bool canGoPrevious = m_playerInterface->property("CanGoPrevious").toBool();
    bool canSeek       = m_playerInterface->property("CanSeek").toBool();

    bool changed = false;

    if (canPlay != m_canPlay) {
        m_canPlay = canPlay;
        changed   = true;
    }
    if (canPause != m_canPause) {
        m_canPause = canPause;
        changed    = true;
    }
    if (canGoNext != m_canGoNext) {
        m_canGoNext = canGoNext;
        changed     = true;
    }
    if (canGoPrevious != m_canGoPrevious) {
        m_canGoPrevious = canGoPrevious;
        changed         = true;
    }
    if (canSeek != m_canSeek) {
        m_canSeek = canSeek;
        changed   = true;
    }

    if (changed) {
        emit capabilitiesChanged();
        qDebug() << "[MPRIS2Controller] Capabilities - Play:" << canPlay << "Pause:" << canPause
                 << "Next:" << canGoNext << "Prev:" << canGoPrevious;
    }
}

void MPRIS2Controller::onDBusServiceRegistered(const QString &serviceName) {

    if (serviceName.startsWith("org.mpris.MediaPlayer2.")) {
        qDebug() << "[MPRIS2Controller] New media player detected:" << serviceName;
        scanForPlayers();
    }
}

void MPRIS2Controller::onDBusServiceUnregistered(const QString &serviceName) {

    if (serviceName.startsWith("org.mpris.MediaPlayer2.")) {
        qDebug() << "[MPRIS2Controller] Media player removed:" << serviceName;
        scanForPlayers();
    }
}

void MPRIS2Controller::play() {
    if (!m_playerInterface || !m_canPlay)
        return;

    qDebug() << "[MPRIS2Controller] Calling Play()";
    m_playerInterface->asyncCall("Play");
    updatePlaybackStatus();
}

void MPRIS2Controller::pause() {
    if (!m_playerInterface || !m_canPause)
        return;

    qDebug() << "[MPRIS2Controller] Calling Pause()";
    m_playerInterface->asyncCall("Pause");
    updatePlaybackStatus();
}

void MPRIS2Controller::playPause() {
    if (!m_playerInterface)
        return;

    qDebug() << "[MPRIS2Controller] Calling PlayPause()";
    m_playerInterface->asyncCall("PlayPause");

    QTimer::singleShot(150, this, &MPRIS2Controller::updatePlaybackStatus);
}

void MPRIS2Controller::stop() {
    if (!m_playerInterface)
        return;

    qDebug() << "[MPRIS2Controller] Calling Stop()";
    m_playerInterface->asyncCall("Stop");
    updatePlaybackStatus();
}

void MPRIS2Controller::next() {
    if (!m_playerInterface)
        return;

    const qint64 podcastThreshold = qint64{20} * 60 * 1000000;

    if (m_canSeek && m_trackLength > podcastThreshold) {
        qInfo() << "[MPRIS2Controller] Smart Skip: Long track detected (" << m_trackLength
                << "us), seeking +30s";
        seek(30000000);
    } else if (m_canGoNext) {
        qDebug() << "[MPRIS2Controller] Calling Next()";
        m_playerInterface->asyncCall("Next");

        QTimer::singleShot(500, this, &MPRIS2Controller::updateMetadata);
    }
}

void MPRIS2Controller::previous() {
    if (!m_playerInterface)
        return;

    const qint64 podcastThreshold = qint64{20} * 60 * 1000000;

    if (m_canSeek && m_trackLength > podcastThreshold) {
        qInfo() << "[MPRIS2Controller] Smart Skip: Long track detected (" << m_trackLength
                << "us), seeking -10s";
        seek(-10000000);
    } else if (m_canGoPrevious) {
        qDebug() << "[MPRIS2Controller] Calling Previous()";
        m_playerInterface->asyncCall("Previous");

        QTimer::singleShot(500, this, &MPRIS2Controller::updateMetadata);
    }
}

void MPRIS2Controller::seek(qint64 offset) {
    if (!m_playerInterface || !m_canSeek)
        return;

    qDebug() << "[MPRIS2Controller] Seeking by" << offset << "microseconds";
    m_playerInterface->asyncCall("Seek", offset);
    updatePosition();
}

void MPRIS2Controller::setPosition(qint64 position) {
    if (!m_playerInterface || !m_canSeek)
        return;

    qDebug() << "[MPRIS2Controller] Setting position to" << position;

    QVariant        metadataVar = m_playerInterface->property("Metadata");
    QVariantMap     metadata    = qdbus_cast<QVariantMap>(metadataVar);
    QDBusObjectPath trackId     = metadata.value("mpris:trackid").value<QDBusObjectPath>();

    m_playerInterface->asyncCall("SetPosition", QVariant::fromValue(trackId), position);
    updatePosition();
}

void MPRIS2Controller::switchToPlayer(const QString &busName) {
    if (m_availablePlayers.contains(busName)) {
        qInfo() << "[MPRIS2Controller] Switching to player:" << busName;
        connectToPlayer(busName);
    } else {
        qWarning() << "[MPRIS2Controller] Player not found:" << busName;
    }
}

QString MPRIS2Controller::extractMetadataString(const QVariantMap &metadata, const QString &key) {
    if (metadata.contains(key)) {
        return metadata.value(key).toString();
    }
    return QString();
}

qint64 MPRIS2Controller::extractMetadataInt64(const QVariantMap &metadata, const QString &key) {
    if (metadata.contains(key)) {
        return metadata.value(key).toLongLong();
    }
    return 0;
}

QStringList MPRIS2Controller::extractMetadataStringList(const QVariantMap &metadata,
                                                        const QString     &key) {
    if (metadata.contains(key)) {
        QVariant value = metadata.value(key);

        if (value.canConvert<QStringList>()) {
            return value.toStringList();
        }

        if (value.canConvert<QDBusVariant>()) {
            QDBusVariant dbusVar    = value.value<QDBusVariant>();
            QVariant     innerValue = dbusVar.variant();
            if (innerValue.canConvert<QStringList>()) {
                return innerValue.toStringList();
            }
        }

        return QStringList() << value.toString();
    }
    return QStringList();
}
