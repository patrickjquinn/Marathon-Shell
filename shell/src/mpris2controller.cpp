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
    , m_scanTimer(nullptr)
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

    // Setup D-Bus monitoring for new/removed players
    setupDBusMonitoring();

    // Setup position update timer (1 second intervals)
    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(1000);
    connect(m_positionTimer, &QTimer::timeout, this, &MPRIS2Controller::updatePosition);

    // Setup player scan timer (every 10 seconds)
    m_scanTimer = new QTimer(this);
    m_scanTimer->setInterval(10000);
    connect(m_scanTimer, &QTimer::timeout, this, &MPRIS2Controller::scanForPlayers);
    m_scanTimer->start();

    // Initial scan
    scanForPlayers();

    qInfo() << "[MPRIS2Controller] Initialized and monitoring for media players";
}

MPRIS2Controller::~MPRIS2Controller() {
    disconnectFromPlayer();
}

void MPRIS2Controller::setupDBusMonitoring() {
    // Monitor D-Bus for new media players appearing/disappearing
    QDBusConnection::sessionBus().connect("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                          "org.freedesktop.DBus", "NameOwnerChanged", this,
                                          SLOT(onDBusServiceRegistered(QString)));

    qDebug() << "[MPRIS2Controller] D-Bus monitoring enabled";
}

void MPRIS2Controller::scanForPlayers() {
    // Get all service names on session bus
    QDBusMessage call = QDBusMessage::createMethodCall(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames");

    QDBusReply<QStringList> reply = QDBusConnection::sessionBus().call(call);

    if (!reply.isValid()) {
        return;
    }

    QStringList services = reply.value();
    QStringList mprisPlayers;

    // Filter for MPRIS2 players
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

    // If we don't have an active player, connect to the first available
    if (!m_hasActivePlayer && !mprisPlayers.isEmpty()) {
        connectToPlayer(mprisPlayers.first());
    }

    // If our current player disappeared, try to find another
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

    // Disconnect from any existing player
    disconnectFromPlayer();

    // Create interface to the player
    m_playerInterface =
        new QDBusInterface(busName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player",
                           QDBusConnection::sessionBus(), this);

    if (!m_playerInterface->isValid()) {
        qWarning() << "[MPRIS2Controller] Failed to connect to" << busName << ":"
                   << m_playerInterface->lastError().message();
        delete m_playerInterface;
        m_playerInterface = nullptr;
        return;
    }

    m_currentBusName  = busName;
    m_hasActivePlayer = true;

    // Extract player name from bus name (e.g., "org.mpris.MediaPlayer2.spotify" -> "Spotify")
    QString name = busName;
    name.remove("org.mpris.MediaPlayer2.");
    int dotIndex = name.indexOf('.');
    if (dotIndex != -1) {
        name = name.left(dotIndex); // Remove instance IDs
    }
    m_playerName = name.at(0).toUpper() + name.mid(1); // Capitalize

    // Fetch DesktopEntry (app ID) from root interface
    QDBusInterface rootInterface(busName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2",
                                 QDBusConnection::sessionBus());
    if (rootInterface.isValid()) {
        m_desktopEntry = rootInterface.property("DesktopEntry").toString();
        qInfo() << "[MPRIS2Controller] App ID (DesktopEntry):" << m_desktopEntry;
    } else {
        m_desktopEntry = name.toLower(); // Fallback to bus name suffix
    }

    qInfo() << "[MPRIS2Controller] ✓ Connected to" << m_playerName;

    // Connect to property changes
    QDBusConnection::sessionBus().connect(busName, "/org/mpris/MediaPlayer2",
                                          "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                          this, SLOT(updatePlaybackStatus()));

    // Initial state fetch
    updatePlaybackStatus();
    updateMetadata();
    updateCapabilities();
    updatePosition();

    // Start position timer
    m_positionTimer->start();

    // Poll metadata every 2 seconds (some players don't emit PropertiesChanged for metadata)
    QTimer *metadataTimer = new QTimer(this);
    connect(metadataTimer, &QTimer::timeout, this, &MPRIS2Controller::updateMetadata);
    metadataTimer->start(2000);

    emit activePlayerChanged();
}

void MPRIS2Controller::disconnectFromPlayer() {
    if (m_playerInterface) {
        m_positionTimer->stop();
        delete m_playerInterface;
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

void MPRIS2Controller::updatePlaybackStatus() {
    if (!m_playerInterface)
        return;

    QVariant statusVar = m_playerInterface->property("PlaybackStatus");
    QString  status    = statusVar.toString();

    if (status != m_playbackStatus) {
        m_playbackStatus = status;
        emit playbackStatusChanged();
        qDebug() << "[MPRIS2Controller] Playback status:" << status;
    }
}

void MPRIS2Controller::updateMetadata() {
    if (!m_playerInterface)
        return;

    // Use explicit DBus call to Properties.Get to handle the a{sv} type correctly
    QDBusMessage call = QDBusMessage::createMethodCall(m_currentBusName, "/org/mpris/MediaPlayer2",
                                                       "org.freedesktop.DBus.Properties", "Get");
    call << "org.mpris.MediaPlayer2.Player" << "Metadata";

    QDBusReply<QDBusVariant> reply = QDBusConnection::sessionBus().call(call);
    QVariantMap              metadata;

    if (reply.isValid()) {
        // The Get call returns a VARIANT, which contains our a{sv} (QVariantMap)
        QVariant innerValue = reply.value().variant();

        if (innerValue.canConvert<QVariantMap>()) {
            metadata = innerValue.value<QVariantMap>();
        } else if (innerValue.canConvert<QDBusArgument>()) {
            // Fallback: manual extraction if automatic conversion fails
            QDBusArgument arg = innerValue.value<QDBusArgument>();
            if (arg.currentType() == QDBusArgument::MapType) {
                arg >> metadata;
            }
        }
    } else {
        // Try the property getter directly as fallback
        QVariant val = m_playerInterface->property("Metadata");
        if (val.canConvert<QVariantMap>()) {
            metadata = val.value<QVariantMap>();
        } else if (val.canConvert<QDBusArgument>()) {
            const QDBusArgument arg = val.value<QDBusArgument>();
            arg >> metadata;
        }
    }

    // QVariantMap metadata = qdbus_cast<QVariantMap>(metadataVar); // Old broken way

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

    // Query position from player
    QDBusReply<qint64> reply = m_playerInterface->call("Position");

    if (reply.isValid()) {
        qint64 pos = reply.value();
        if (pos != m_position) {
            m_position = pos;
            emit positionChanged();
        }
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
    // Check if a new MPRIS2 player appeared
    if (serviceName.startsWith("org.mpris.MediaPlayer2.")) {
        qDebug() << "[MPRIS2Controller] New media player detected:" << serviceName;
        scanForPlayers();
    }
}

void MPRIS2Controller::onDBusServiceUnregistered(const QString &serviceName) {
    // Check if an MPRIS2 player disappeared
    if (serviceName.startsWith("org.mpris.MediaPlayer2.")) {
        qDebug() << "[MPRIS2Controller] Media player removed:" << serviceName;
        scanForPlayers();
    }
}

// Playback control methods

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
    updatePlaybackStatus();
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

    // Smart Skip Logic:
    // If track is long (> 20 mins) and seekable, skip forward 30 seconds (Podcast mode)
    // Otherwise, go to next track (Music mode)
    const qint64 podcastThreshold = 20 * 60 * 1000000; // 20 minutes in microseconds

    if (m_canSeek && m_trackLength > podcastThreshold) {
        qInfo() << "[MPRIS2Controller] Smart Skip: Long track detected (" << m_trackLength
                << "us), seeking +30s";
        seek(30000000); // +30 seconds
    } else if (m_canGoNext) {
        qDebug() << "[MPRIS2Controller] Calling Next()";
        m_playerInterface->asyncCall("Next");

        // Metadata will change, so update it
        QTimer::singleShot(500, this, &MPRIS2Controller::updateMetadata);
    }
}

void MPRIS2Controller::previous() {
    if (!m_playerInterface)
        return;

    // Smart Skip Logic:
    // If track is long (> 20 mins) and seekable, skip back 10 seconds (Podcast mode)
    // Otherwise, go to previous track (Music mode)
    const qint64 podcastThreshold = 20 * 60 * 1000000; // 20 minutes in microseconds

    if (m_canSeek && m_trackLength > podcastThreshold) {
        qInfo() << "[MPRIS2Controller] Smart Skip: Long track detected (" << m_trackLength
                << "us), seeking -10s";
        seek(-10000000); // -10 seconds
    } else if (m_canGoPrevious) {
        qDebug() << "[MPRIS2Controller] Calling Previous()";
        m_playerInterface->asyncCall("Previous");

        // Metadata will change, so update it
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

    // SetPosition requires track ID, get it from metadata
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

// Helper methods for metadata extraction

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

        // Try to convert to string list
        if (value.canConvert<QStringList>()) {
            return value.toStringList();
        }

        // Try DBus variant
        if (value.canConvert<QDBusVariant>()) {
            QDBusVariant dbusVar    = value.value<QDBusVariant>();
            QVariant     innerValue = dbusVar.variant();
            if (innerValue.canConvert<QStringList>()) {
                return innerValue.toStringList();
            }
        }

        // Fallback: single string
        return QStringList() << value.toString();
    }
    return QStringList();
}
