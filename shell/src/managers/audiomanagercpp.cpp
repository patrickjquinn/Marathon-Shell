#include "audiomanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QProcess>
#include <QRegularExpression>

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
    , m_currentVolume(0.6)
    , m_muted(false)
    , m_isPlaying(false)
    , m_streamModel(new AudioStreamModel(this))
    , m_streamRefreshTimer(new QTimer(this))
    , m_pa_mainloop(nullptr)
    , m_pa_context(nullptr) {
    qDebug() << "[AudioManagerCpp] Initializing";

    QProcess checkPipewire;
    checkPipewire.start("wpctl", {"status"});
    checkPipewire.waitForFinished(1000);

    if (checkPipewire.exitCode() == 0) {
        m_available  = true;
        m_isPipeWire = true;
        qInfo() << "[AudioManagerCpp] PipeWire/WirePlumber available with per-app volume support";

        QProcess process;
        process.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
        process.waitForFinished();
        QString                 output = process.readAllStandardOutput();

        QRegularExpression      re("Volume: ([0-9.]+)");
        QRegularExpressionMatch match = re.match(output);
        if (match.hasMatch()) {
            m_currentVolume = match.captured(1).toDouble();
            emit volumeChanged();
        }

        if (output.contains("[MUTED]")) {
            m_muted = true;
            emit mutedChanged();
        }

        parseWpctlStatus();

        startStreamMonitoring();
    } else {

        if (initPulseAudio()) {
            m_available  = true;
            m_isPipeWire = false;
            qInfo() << "[AudioManagerCpp] PulseAudio available (per-app volume not supported)";
        } else {
            qInfo()
                << "[AudioManagerCpp] Neither PipeWire nor PulseAudio available, using mock mode";
        }
    }
}

AudioManagerCpp::~AudioManagerCpp() {
    cleanupPulseAudio();
}

void AudioManagerCpp::setVolume(double volume) {
    if (!m_available) {
        m_currentVolume = qBound(0.0, volume, 1.0);
        emit volumeChanged();
        return;
    }

    volume = qBound(0.0, volume, 1.0);

    if (m_isPipeWire) {
        QProcess wpctl;
        wpctl.start("wpctl", {"set-volume", "@DEFAULT_AUDIO_SINK@", QString::number(volume)});
        wpctl.waitForFinished(500);

        if (wpctl.exitCode() == 0) {
            m_currentVolume = volume;
            emit volumeChanged();
            qDebug() << "[AudioManagerCpp] Set volume to:" << qRound(volume * 100)
                     << "% (PipeWire)";
            return;
        }
    } else {

        if (m_pa_context && m_pa_mainloop) {
            if (m_defaultSinkName.isEmpty()) {
                qWarning() << "[PulseAudio] Default sink name is empty!";
                return;
            }
            pa_threaded_mainloop_lock(m_pa_mainloop);

            pa_cvolume  cv;
            pa_volume_t paVol = pa_sw_volume_from_linear(volume);
            pa_cvolume_set(&cv, m_sinkChannels, paVol);

            pa_context_set_sink_volume_by_name(m_pa_context, m_defaultSinkName.toUtf8().constData(),
                                               &cv, nullptr, nullptr);

            pa_threaded_mainloop_unlock(m_pa_mainloop);

            m_currentVolume = volume;
            emit volumeChanged();
            qDebug() << "[AudioManagerCpp] Set volume to:" << volume << "(PulseAudio)";
            return;
        }
    }
}

void AudioManagerCpp::setMuted(bool muted) {
    if (!m_available) {
        m_muted = muted;
        emit mutedChanged();
        return;
    }

    if (m_isPipeWire) {
        QProcess wpctl;
        wpctl.start("wpctl", {"set-mute", "@DEFAULT_AUDIO_SINK@", muted ? "1" : "0"});
        wpctl.waitForFinished(500);

        if (wpctl.exitCode() == 0) {
            m_muted = muted;
            emit mutedChanged();
            qDebug() << "[AudioManagerCpp] Set muted to:" << muted << "(PipeWire)";
            return;
        }
    } else {

        if (m_pa_context && m_pa_mainloop) {
            pa_threaded_mainloop_lock(m_pa_mainloop);

            pa_context_set_sink_mute_by_name(m_pa_context, m_defaultSinkName.toUtf8().constData(),
                                             muted, nullptr, nullptr);

            pa_threaded_mainloop_unlock(m_pa_mainloop);

            m_muted = muted;
            emit mutedChanged();
            qDebug() << "[AudioManagerCpp] Set muted to:" << muted << "(PulseAudio)";
        }
    }
}

void AudioManagerCpp::setStreamVolume(int streamId, double volume) {
    if (!m_isPipeWire) {
        qWarning() << "[AudioManagerCpp] Per-stream volume requires PipeWire";
        return;
    }

    volume = qBound(0.0, volume, 1.0);

    QProcess wpctl;
    wpctl.start("wpctl", {"set-volume", QString::number(streamId), QString::number(volume)});
    wpctl.waitForFinished(500);

    if (wpctl.exitCode() == 0) {
        qDebug() << "[AudioManagerCpp] Set stream" << streamId
                 << "volume to:" << qRound(volume * 100) << "%";
        refreshStreams();
    } else {
        qWarning() << "[AudioManagerCpp] Failed to set stream volume:" << wpctl.errorString();
    }
}

void AudioManagerCpp::setStreamMuted(int streamId, bool muted) {
    if (!m_isPipeWire) {
        qWarning() << "[AudioManagerCpp] Per-stream mute requires PipeWire";
        return;
    }

    QProcess wpctl;
    wpctl.start("wpctl", {"set-mute", QString::number(streamId), muted ? "1" : "0"});
    wpctl.waitForFinished(500);

    if (wpctl.exitCode() == 0) {
        qDebug() << "[AudioManagerCpp] Set stream" << streamId << "muted to:" << muted;
        refreshStreams();
    } else {
        qWarning() << "[AudioManagerCpp] Failed to set stream mute:" << wpctl.errorString();
    }
}

void AudioManagerCpp::refreshStreams() {
    if (m_isPipeWire) {
        parseWpctlStatus();
    }
}

void AudioManagerCpp::parseWpctlStatus() {
    QProcess process;
    process.start("wpctl", {"status"});
    process.waitForFinished(2000);

    if (process.exitCode() != 0) {
        return;
    }

    QString            output = process.readAllStandardOutput();
    QList<AudioStream> streams;

    QRegularExpression streamRe(
        "^\\s+[│├─]+\\s+(\\d+)\\.\\s+(.+?)\\s+\\[vol:\\s+([0-9.]+)(?:\\s+MUTED)?\\]",
        QRegularExpression::MultilineOption);

    bool        inSinksSection   = false;
    bool        inStreamsSection = false;

    QStringList lines = output.split('\n');
    for (const QString &line : lines) {
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

void AudioManagerCpp::startStreamMonitoring() {

    connect(m_streamRefreshTimer, &QTimer::timeout, this, &AudioManagerCpp::refreshStreams);
    m_streamRefreshTimer->start(5000);
    qDebug() << "[AudioManagerCpp] Started stream monitoring (5s interval)";
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

bool AudioManagerCpp::initPulseAudio() {
    m_pa_mainloop = pa_threaded_mainloop_new();
    if (!m_pa_mainloop)
        return false;

    m_pa_context = pa_context_new(pa_threaded_mainloop_get_api(m_pa_mainloop), "AudioManagerCpp");

    if (!m_pa_context) {
        cleanupPulseAudio();
        return false;
    }

    pa_context_set_state_callback(m_pa_context, &AudioManagerCpp::paContextStateCallback, this);

    if (pa_context_connect(m_pa_context, NULL, PA_CONTEXT_NOFLAGS, NULL) < 0) {
        cleanupPulseAudio();
        return false;
    }

    if (pa_threaded_mainloop_start(m_pa_mainloop) < 0) {
        cleanupPulseAudio();
        return false;
    }

    return true;
}

void AudioManagerCpp::cleanupPulseAudio() {
    if (m_pa_mainloop)
        pa_threaded_mainloop_stop(m_pa_mainloop);
    if (m_pa_context) {
        pa_context_disconnect(m_pa_context);
        pa_context_unref(m_pa_context);
    }
    if (m_pa_mainloop)
        pa_threaded_mainloop_free(m_pa_mainloop);
}

void AudioManagerCpp::requestDefaultSink() {
    pa_operation *o = pa_context_get_server_info(
        m_pa_context,
        [](pa_context *, const pa_server_info *info, void *userdata) {
            if (!info || !info->default_sink_name)
                return;

            AudioManagerCpp *self = static_cast<AudioManagerCpp *>(userdata);

            self->m_defaultSinkName = info->default_sink_name;
            qInfo() << "[PulseAudio] Default sink:" << self->m_defaultSinkName;

            pa_context_get_sink_info_by_name(self->m_pa_context,
                                             self->m_defaultSinkName.toUtf8().constData(),
                                             &AudioManagerCpp::paSinkInfoCallback, self);
        },
        this);

    if (o)
        pa_operation_unref(o);
}

void AudioManagerCpp::paContextStateCallback(pa_context *c, void *userdata) {
    AudioManagerCpp *self = static_cast<AudioManagerCpp *>(userdata);

    switch (pa_context_get_state(c)) {

        case PA_CONTEXT_READY: self->requestDefaultSink(); break;

        case PA_CONTEXT_FAILED:
        case PA_CONTEXT_TERMINATED:
            qWarning() << "[AudioManagerCpp] PulseAudio context failed/terminated";
            break;

        default: break;
    }
}

void AudioManagerCpp::paSinkInfoCallback(pa_context *, const pa_sink_info *i, int eol,
                                         void *userdata) {
    if (eol < 0 || !i)
        return;

    AudioManagerCpp *self = static_cast<AudioManagerCpp *>(userdata);

    if (QString(i->name) != self->m_defaultSinkName)
        return;

    self->m_sinkChannels = i->channel_map.channels;

    double vol     = (double)pa_cvolume_avg(&i->volume) / PA_VOLUME_NORM;
    bool   isMuted = i->mute;

    QMetaObject::invokeMethod(self, "updateFromPulse", Qt::QueuedConnection, Q_ARG(double, vol),
                              Q_ARG(bool, isMuted));
}

void AudioManagerCpp::updateFromPulse(double vol, bool isMuted) {
    if (!qFuzzyCompare(m_currentVolume, vol)) {
        m_currentVolume = vol;
        emit volumeChanged();
    }
    if (m_muted != isMuted) {
        m_muted = isMuted;
        emit mutedChanged();
    }
}
