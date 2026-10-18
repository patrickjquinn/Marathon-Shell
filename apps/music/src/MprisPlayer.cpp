#include "MprisPlayer.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDebug>

namespace {
    // NOLINTBEGIN(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString kService = QStringLiteral("org.mpris.MediaPlayer2.music");
    const QString kPath    = QStringLiteral("/org/mpris/MediaPlayer2");
    const QString kPlayerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
    // NOLINTEND(bugprone-throwing-static-initialization)
}

MprisPlayer::MprisPlayer(QObject *parent)
    : QObject(parent) {
    new MprisRootAdaptor(this);
    m_playerAdaptor = new MprisPlayerAdaptor(this);

    m_flush.setSingleShot(true);
    m_flush.setInterval(0);
    connect(&m_flush, &QTimer::timeout, this, &MprisPlayer::flushChanges);

    connect(this, &MprisPlayer::activeChanged, this, &MprisPlayer::updateRegistration);
    connect(this, &MprisPlayer::statusChanged, this, [this] {
        queueChanged(QStringLiteral("PlaybackStatus"));
        queueChanged(QStringLiteral("LoopStatus"));
        queueChanged(QStringLiteral("Shuffle"));
        queueChanged(QStringLiteral("CanGoNext"));
        queueChanged(QStringLiteral("CanGoPrevious"));
    });
    connect(this, &MprisPlayer::metadataChanged, this, [this] {
        queueChanged(QStringLiteral("Metadata"));
        queueChanged(QStringLiteral("CanPlay"));
        queueChanged(QStringLiteral("CanPause"));
        queueChanged(QStringLiteral("CanSeek"));
    });
}

MprisPlayer::~MprisPlayer() {
    if (m_registered) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.unregisterService(kService);
        bus.unregisterObject(kPath);
    }
}

void MprisPlayer::componentComplete() {
    m_complete = true;
    updateRegistration();
}

void MprisPlayer::updateRegistration() {
    if (!m_complete || m_active == m_registered)
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (m_active) {
        if (!bus.registerObject(kPath, this, QDBusConnection::ExportAdaptors)
            || !bus.registerService(kService)) {
            qWarning() << "[MprisPlayer] Couldn't publish" << kService << ":"
                       << bus.lastError().message();
            bus.unregisterObject(kPath);
            return;
        }
    } else {
        bus.unregisterService(kService);
        bus.unregisterObject(kPath);
    }
    m_registered = m_active;
    emit registeredChanged();
}

void MprisPlayer::queueChanged(const QString &property) {
    m_dirty.insert(property);
    m_flush.start();
}

void MprisPlayer::flushChanges() {
    if (!m_registered) {
        m_dirty.clear();
        return;
    }
    QVariantMap changed;
    for (const QString &name : std::as_const(m_dirty))
        changed.insert(name, m_playerAdaptor->property(name.toLatin1().constData()));
    m_dirty.clear();
    QDBusMessage signal = QDBusMessage::createSignal(
        kPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
    signal << kPlayerInterface << changed << QStringList();
    QDBusConnection::sessionBus().send(signal);
}

QString MprisPlayer::playbackStatus() const {
    if (m_title.isEmpty())
        return QStringLiteral("Stopped");
    return m_playing ? QStringLiteral("Playing") : QStringLiteral("Paused");
}

QString MprisPlayer::loopStatus() const {
    if (m_repeatMode == QLatin1String("one"))
        return QStringLiteral("Track");
    if (m_repeatMode == QLatin1String("all"))
        return QStringLiteral("Playlist");
    return QStringLiteral("None");
}

QDBusObjectPath MprisPlayer::trackPath() const {
    return QDBusObjectPath(m_trackId >= 0
                               ? QStringLiteral("/org/marathonos/music/track/%1").arg(m_trackId)
                               : QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack"));
}

QVariantMap MprisPlayer::metadata() const {
    QVariantMap map;
    if (m_title.isEmpty())
        return map;
    map.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(trackPath()));
    map.insert(QStringLiteral("mpris:length"), qlonglong(m_length) * 1000);
    map.insert(QStringLiteral("xesam:title"), m_title);
    map.insert(QStringLiteral("xesam:artist"), QStringList{m_artist});
    map.insert(QStringLiteral("xesam:album"), m_album);
    if (!m_artUrl.isEmpty())
        map.insert(QStringLiteral("mpris:artUrl"), m_artUrl);
    return map;
}

MprisRootAdaptor::MprisRootAdaptor(MprisPlayer *player)
    : QDBusAbstractAdaptor(player)
    , m_player(player) {}

QString MprisRootAdaptor::identity() const {
    return m_player->m_identity;
}

QString MprisRootAdaptor::desktopEntry() const {
    return m_player->m_desktopEntry;
}

void MprisRootAdaptor::Raise() {
    emit m_player->raiseRequested();
}

MprisPlayerAdaptor::MprisPlayerAdaptor(MprisPlayer *player)
    : QDBusAbstractAdaptor(player)
    , m_player(player) {}

QString MprisPlayerAdaptor::playbackStatus() const {
    return m_player->playbackStatus();
}

QString MprisPlayerAdaptor::loopStatus() const {
    return m_player->loopStatus();
}

void MprisPlayerAdaptor::setLoopStatus(const QString &status) {
    emit m_player->repeatModeRequested(status == QLatin1String("Track")      ? QStringLiteral("one")
                                       : status == QLatin1String("Playlist") ? QStringLiteral("all")
                                                                             : QStringLiteral("off"));
}

bool MprisPlayerAdaptor::shuffle() const {
    return m_player->m_shuffle;
}

void MprisPlayerAdaptor::setShuffle(bool shuffle) {
    emit m_player->shuffleRequested(shuffle);
}

QVariantMap MprisPlayerAdaptor::metadata() const {
    return m_player->metadata();
}

qlonglong MprisPlayerAdaptor::position() const {
    return qlonglong(m_player->m_position) * 1000;
}

bool MprisPlayerAdaptor::canGoNext() const {
    return m_player->m_canGoNext;
}

bool MprisPlayerAdaptor::canGoPrevious() const {
    return m_player->m_canGoPrevious;
}

bool MprisPlayerAdaptor::hasTrack() const {
    return !m_player->m_title.isEmpty();
}

void MprisPlayerAdaptor::Next() {
    emit m_player->nextRequested();
}

void MprisPlayerAdaptor::Previous() {
    emit m_player->previousRequested();
}

void MprisPlayerAdaptor::Pause() {
    emit m_player->pauseRequested();
}

void MprisPlayerAdaptor::PlayPause() {
    emit m_player->playPauseRequested();
}

void MprisPlayerAdaptor::Stop() {
    emit m_player->stopRequested();
}

void MprisPlayerAdaptor::Play() {
    emit m_player->playRequested();
}

void MprisPlayerAdaptor::Seek(qlonglong offset) {
    const qint64 target = qMax<qint64>(0, m_player->m_position + offset / 1000);
    if (m_player->m_length > 0 && target > m_player->m_length) {
        emit m_player->nextRequested();
        return;
    }
    emit m_player->seekRequested(target);
    emit Seeked(qlonglong(target) * 1000);
}

void MprisPlayerAdaptor::SetPosition(const QDBusObjectPath &trackId, qlonglong position) {
    if (trackId != m_player->trackPath() || position < 0
        || (m_player->m_length > 0 && position / 1000 > m_player->m_length))
        return;
    emit m_player->seekRequested(position / 1000);
    emit Seeked(position);
}
