#include "audiomanagercpp.h"
#include "audiodclient.h"
#include "sinkvolume.h"
#include <QJSEngine>
#include <QQmlEngine>
#include "platform.h"
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusMetaType>

AudioManagerCpp *AudioManagerCpp::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new AudioManagerCpp(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}

AudioStreamModel::AudioStreamModel(QObject *parent)
    : QAbstractListModel(parent) {}

int AudioStreamModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid())
        return 0;
    return m_streams.count();
}

QVariant AudioStreamModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_streams.count())
        return QVariant();

    const AudioStream &stream = m_streams.at(index.row());

    switch (role) {
        case IdRole: return stream.id;
        case NameRole: return stream.name;
        case AppNameRole: return stream.appName;
        case VolumeRole: return stream.volume;
        case MutedRole: return stream.muted;
        case MediaClassRole: return stream.mediaClass;
        default: return QVariant();
    }
}

QHash<int, QByteArray> AudioStreamModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole]         = "streamId";
    roles[NameRole]       = "name";
    roles[AppNameRole]    = "appName";
    roles[VolumeRole]     = "volume";
    roles[MutedRole]      = "muted";
    roles[MediaClassRole] = "mediaClass";
    return roles;
}

void AudioStreamModel::updateStreams(const QList<AudioStream> &streams) {
    beginResetModel();
    m_streams = streams;
    endResetModel();
}

AudioStream *AudioStreamModel::getStream(int streamId) {
    for (int i = 0; i < m_streams.size(); ++i) {
        if (m_streams[i].id == streamId) {
            return &m_streams[i];
        }
    }
    return nullptr;
}

AudioManagerCpp::AudioManagerCpp(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_isPlaying(false)
    , m_streamModel(new AudioStreamModel(this))
    , m_audiod(new AudiodClient(QDBusConnection::sessionBus(), this))
    , m_sinkVolume(new SinkVolume(m_audiod, this)) {
    connect(m_sinkVolume, &SinkVolume::volumeChanged, this, &AudioManagerCpp::volumeChanged);
    connect(m_sinkVolume, &SinkVolume::mutedChanged, this, &AudioManagerCpp::mutedChanged);
    connect(m_audiod, &AudiodClient::streamsChanged, this, &AudioManagerCpp::updateStreams);
    connect(m_audiod, &AudiodClient::availableChanged, this, [this] {
        m_available = m_audiod->available();
        qInfo() << "[AudioManagerCpp] marathon-audiod" << (m_available ? "up" : "down");
        emit availableChanged();
    });
    m_audiod->refresh();
}

double AudioManagerCpp::volume() const {
    return m_sinkVolume->volume();
}

bool AudioManagerCpp::muted() const {
    return m_sinkVolume->muted();
}

void AudioManagerCpp::setVolume(double volume) {
    m_sinkVolume->setVolume(volume);
}

void AudioManagerCpp::setMuted(bool muted) {
    m_sinkVolume->setMuted(muted);
}

void AudioManagerCpp::setStreamVolume(int streamId, double volume) {
    m_audiod->setStreamVolume(static_cast<uint>(streamId), qBound(0.0, volume, 1.0));
}

void AudioManagerCpp::setStreamMuted(int streamId, bool muted) {
    m_audiod->setStreamMuted(static_cast<uint>(streamId), muted);
}

// The service pushes stream changes; this only re-reads after it restarts.
void AudioManagerCpp::refreshStreams() {
    m_audiod->refresh();
}

void AudioManagerCpp::setInputMuted(bool muted) {
    m_audiod->setInputMuted(muted);
}

void AudioManagerCpp::setSpeakerphone(bool on) {
    m_audiod->setSpeakerphone(on);
}

void AudioManagerCpp::updateStreams() {
    QList<AudioStream> streams;
    for (const AudiodStream &s : m_audiod->streams())
        streams.append({static_cast<int>(s.id), s.name, s.name, s.volume, s.muted,
                        QStringLiteral("Stream/Output/Audio")});
    m_streamModel->updateStreams(streams);
    emit       streamsChanged();

    const bool playing = !streams.isEmpty();
    if (playing != m_isPlaying) {
        m_isPlaying = playing;
        qInfo() << "[AudioManagerCpp] Playback state changed:" << (playing ? "PLAYING" : "STOPPED");
        emit isPlayingChanged();
    }
}
