#include "audiomanagercpp.h"
#include "pulsesinkbackend.h"
#include "sinkvolume.h"
#include <QJSEngine>
#include <QQmlEngine>
#include "platform.h"
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QProcess>
#include <QRegularExpression>
#include <utility>   // std::as_const

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
    , m_isPipeWire(false)
    , m_isPlaying(false)
    , m_streamModel(new AudioStreamModel(this)) {
    qDebug() << "[AudioManagerCpp] Initializing";

    QProcess checkPipewire;
    checkPipewire.start("wpctl", {"status"});
    checkPipewire.waitForFinished(1000);
    m_isPipeWire = checkPipewire.exitCode() == 0;

    // The default sink is followed through libpulse (pipewire-pulse on
    // PipeWire): the default can change at any time, e.g. to a headset.
    auto *backend = new PulseSinkBackend(this);
    m_sinkVolume  = new SinkVolume(backend, this);
    connect(m_sinkVolume, &SinkVolume::volumeChanged, this, &AudioManagerCpp::volumeChanged);
    connect(m_sinkVolume, &SinkVolume::mutedChanged, this, &AudioManagerCpp::mutedChanged);
    const bool pulse = backend->start();
    m_available      = m_isPipeWire || pulse;

    if (m_isPipeWire) {
        qInfo() << "[AudioManagerCpp] PipeWire/WirePlumber available with per-app volume support";
        refreshStreams();
    } else if (pulse) {
        qInfo() << "[AudioManagerCpp] PulseAudio available (per-app volume not supported)";
    } else {
        qInfo() << "[AudioManagerCpp] Neither PipeWire nor PulseAudio available, using mock mode";
    }
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
    if (!m_isPipeWire) {
        qWarning() << "[AudioManagerCpp] Per-stream volume requires PipeWire";
        return;
    }

    volume = qBound(0.0, volume, 1.0);

    runWpctl({"set-volume", QString::number(streamId), QString::number(volume)},
             [this, streamId, volume](bool ok) {
                 if (ok) {
                     qDebug() << "[AudioManagerCpp] Set stream" << streamId
                              << "volume to:" << qRound(volume * 100) << "%";
                     refreshStreams();
                 } else {
                     qWarning() << "[AudioManagerCpp] Failed to set stream volume";
                 }
             });
}

void AudioManagerCpp::setStreamMuted(int streamId, bool muted) {
    if (!m_isPipeWire) {
        qWarning() << "[AudioManagerCpp] Per-stream mute requires PipeWire";
        return;
    }

    runWpctl({"set-mute", QString::number(streamId), muted ? "1" : "0"},
             [this, streamId, muted](bool ok) {
                 if (ok) {
                     qDebug() << "[AudioManagerCpp] Set stream" << streamId << "muted to:" << muted;
                     refreshStreams();
                 } else {
                     qWarning() << "[AudioManagerCpp] Failed to set stream mute";
                 }
             });
}

// Called when PipeWire adds or removes a playback stream, and after this
// manager changes a stream; nothing polls.
void AudioManagerCpp::refreshStreams() {
    if (!m_isPipeWire)
        return;
    if (m_statusRunning) {
        m_statusPending = true;
        return;
    }
    m_statusRunning = true;

    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this,
            [this, process](int exitCode, QProcess::ExitStatus status) {
                process->deleteLater();
                m_statusRunning = false;
                if (status == QProcess::NormalExit && exitCode == 0)
                    parseWpctlStatus(QString::fromUtf8(process->readAllStandardOutput()));
                if (std::exchange(m_statusPending, false))
                    refreshStreams();
            });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_statusRunning = false;
        m_statusPending = false;
    });
    process->start("wpctl", {"status"});
}

void AudioManagerCpp::runWpctl(const QStringList &args, const std::function<void(bool ok)> &done) {
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this,
            [process, done](int exitCode, QProcess::ExitStatus status) {
                process->deleteLater();
                if (done)
                    done(status == QProcess::NormalExit && exitCode == 0);
            });
    connect(process, &QProcess::errorOccurred, this, [process, done](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        process->deleteLater();
        if (done)
            done(false);
    });
    process->start("wpctl", args);
}

void AudioManagerCpp::parseWpctlStatus(const QString &output) {
    QList<AudioStream>              streams;

    static const QRegularExpression streamRe(
        "^\\s+[│├─]+\\s+(\\d+)\\.\\s+(.+?)\\s+\\[vol:\\s+([0-9.]+)(?:\\s+MUTED)?\\]",
        QRegularExpression::MultilineOption);

    bool        inSinksSection   = false;
    bool        inStreamsSection = false;

    QStringList lines = output.split('\n');
    for (const QString &line : std::as_const(lines)) {
        if (line.contains("Sinks:", Qt::CaseInsensitive)) {
            inSinksSection   = true;
            inStreamsSection = false;
            continue;
        }
        if (line.contains("Sink endpoints:", Qt::CaseInsensitive) ||
            line.contains("Sources:", Qt::CaseInsensitive)) {
            inSinksSection = false;
            continue;
        }
        if (line.contains("Streams:", Qt::CaseInsensitive)) {
            inStreamsSection = true;
            continue;
        }

        if (!inSinksSection && !inStreamsSection) {
            continue;
        }

        QRegularExpressionMatch match = streamRe.match(line);
        if (match.hasMatch()) {
            AudioStream stream;
            stream.id         = match.captured(1).toInt();
            stream.name       = match.captured(2).trimmed();
            stream.appName    = stream.name;
            stream.volume     = match.captured(3).toDouble();
            stream.muted      = line.contains("MUTED");
            stream.mediaClass = inStreamsSection ? "Stream/Output/Audio" : "Audio/Sink";

            if (inStreamsSection && stream.id > 0) {
                streams.append(stream);
            }
        }
    }

    qDebug() << "[AudioManagerCpp] Found" << streams.size() << "audio streams";
    m_streamModel->updateStreams(streams);
    emit streamsChanged();

    updatePlaybackState();
}

void AudioManagerCpp::updatePlaybackState() {

    bool wasPlaying   = m_isPlaying;
    bool isNowPlaying = false;

    if (m_streamModel->rowCount() > 0) {
        isNowPlaying = true;
    }

    if (wasPlaying != isNowPlaying) {
        m_isPlaying = isNowPlaying;
        qInfo() << "[AudioManagerCpp] Playback state changed:"
                << (isNowPlaying ? "PLAYING" : "STOPPED");
        emit isPlayingChanged();
    }
}
