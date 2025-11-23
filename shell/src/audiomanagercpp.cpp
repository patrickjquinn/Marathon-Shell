#include "audiomanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QProcess>
#include <QRegularExpression>

// AudioStreamModel implementation
AudioStreamModel::AudioStreamModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int AudioStreamModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_streams.count();
}

QVariant AudioStreamModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() >= m_streams.count())
        return QVariant();
    
    const AudioStream& stream = m_streams.at(index.row());
    
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

QHash<int, QByteArray> AudioStreamModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "streamId";
    roles[NameRole] = "name";
    roles[AppNameRole] = "appName";
    roles[VolumeRole] = "volume";
    roles[MutedRole] = "muted";
    roles[MediaClassRole] = "mediaClass";
    return roles;
}

void AudioStreamModel::updateStreams(const QList<AudioStream>& streams)
{
    beginResetModel();
    m_streams = streams;
    endResetModel();
}

AudioStream* AudioStreamModel::getStream(int streamId)
{
    for (int i = 0; i < m_streams.size(); ++i) {
        if (m_streams[i].id == streamId) {
            return &m_streams[i];
        }
    }
    return nullptr;
}

// AudioManagerCpp implementation
AudioManagerCpp::AudioManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_isPipeWire(false)
    , m_currentVolume(0.6)
    , m_muted(false)
    , m_isPlaying(false)
    , m_streamModel(new AudioStreamModel(this))
    , m_streamRefreshTimer(new QTimer(this))
{
    qDebug() << "[AudioManagerCpp] Initializing";
    
    // Try PipeWire first via wpctl
    QProcess checkPipewire;
    checkPipewire.start("wpctl", {"status"});
    checkPipewire.waitForFinished(1000);
    
    if (checkPipewire.exitCode() == 0) {
        m_available = true;
        m_isPipeWire = true;
        qInfo() << "[AudioManagerCpp] PipeWire/WirePlumber available with per-app volume support";
        
        // Get initial volume
        QProcess process;
        process.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
        process.waitForFinished();
        QString output = process.readAllStandardOutput();
        
        // Parse "Volume: 0.60" or "Volume: 0.60 [MUTED]"
        QRegularExpression re("Volume: ([0-9.]+)");
        QRegularExpressionMatch match = re.match(output);
        if (match.hasMatch()) {
            m_currentVolume = match.captured(1).toDouble();
            emit volumeChanged();
        }
        
        if (output.contains("[MUTED]")) {
            m_muted = true;
            emit mutedChanged();
        }
        
        // Parse streams and start monitoring
        parseWpctlStatus();
        
        // Check if we actually found any streams/sinks. If not, and we are on Droidian, 
        // wpctl might report success but not actually work for audio control if PulseAudio is the real backend.
        if (m_streamModel->rowCount() == 0) {
             // Double check with pactl if we didn't find anything useful with wpctl
             QProcess checkPulse;
             checkPulse.start("pactl", {"info"});
             checkPulse.waitForFinished(1000);
             if (checkPulse.exitCode() == 0) {
                 qInfo() << "[AudioManagerCpp] PipeWire found but no streams - falling back to PulseAudio";
                 m_isPipeWire = false;
                 // Re-run initialization for PulseAudio
                 QProcess process;
                 process.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
                 process.waitForFinished();
                 QString output = process.readAllStandardOutput();
                 
                 QRegularExpression re("Volume: .*? (\\d+)%");
                 QRegularExpressionMatch match = re.match(output);
                 if (match.hasMatch()) {
                     m_currentVolume = match.captured(1).toDouble() / 100.0;
                     emit volumeChanged();
                 }
             } else {
                 startStreamMonitoring();
             }
        } else {
            startStreamMonitoring();
        }
        
    } else {
        // Fallback to PulseAudio
        QProcess checkPulse;
        checkPulse.start("pactl", {"info"});
        checkPulse.waitForFinished(1000);
        
        if (checkPulse.exitCode() == 0) {
            m_available = true;
            m_isPipeWire = false;
            qInfo() << "[AudioManagerCpp] PulseAudio available (per-app volume not supported)";
            
            QProcess process;
            process.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
            process.waitForFinished();
            QString output = process.readAllStandardOutput();
            
            QRegularExpression re("Volume: .*? (\\d+)%");
            QRegularExpressionMatch match = re.match(output);
            if (match.hasMatch()) {
                m_currentVolume = match.captured(1).toDouble() / 100.0;
                emit volumeChanged();
            }
        } else {
            qInfo() << "[AudioManagerCpp] Neither PipeWire nor PulseAudio available, using mock mode";
        }
    }
    
    // Start monitoring for external volume changes (hardware keys)
    startVolumeMonitoring();
}

void AudioManagerCpp::setVolume(double volume)
{
    if (!m_available) {
        m_currentVolume = qBound(0.0, volume, 1.0);
        emit volumeChanged();
        return;
    }
    
    // Clamp volume to 0.0-1.0
    volume = qBound(0.0, volume, 1.0);
    
    // Try PipeWire first
    QProcess wpctl;
    wpctl.start("wpctl", {"set-volume", "@DEFAULT_AUDIO_SINK@", QString::number(volume)});
    wpctl.waitForFinished(500);
    
    if (wpctl.exitCode() == 0) {
        m_currentVolume = volume;
        emit volumeChanged();
        qDebug() << "[AudioManagerCpp] Set volume to:" << qRound(volume * 100) << "% (PipeWire)";
        return;
    }
    
    // Fallback to PulseAudio
    int percent = qRound(volume * 100);
    QProcess::execute("pactl", {"set-sink-volume", "@DEFAULT_SINK@", QString::number(percent) + "%"});
    
    m_currentVolume = volume;
    emit volumeChanged();
    qDebug() << "[AudioManagerCpp] Set volume to:" << percent << "% (PulseAudio)";
}

void AudioManagerCpp::setMuted(bool muted)
{
    if (!m_available) {
        m_muted = muted;
        emit mutedChanged();
        return;
    }
    
    // Try PipeWire first
    QProcess wpctl;
    wpctl.start("wpctl", {"set-mute", "@DEFAULT_AUDIO_SINK@", muted ? "1" : "0"});
    wpctl.waitForFinished(500);
    
    if (wpctl.exitCode() == 0) {
        m_muted = muted;
        emit mutedChanged();
        qDebug() << "[AudioManagerCpp] Set muted to:" << muted << "(PipeWire)";
        return;
    }
    
    // Fallback to PulseAudio
    QProcess::execute("pactl", {"set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"});
    
    m_muted = muted;
    emit mutedChanged();
    qDebug() << "[AudioManagerCpp] Set muted to:" << muted << "(PulseAudio)";
}

void AudioManagerCpp::setStreamVolume(int streamId, double volume)
{
    if (!m_isPipeWire) {
        qWarning() << "[AudioManagerCpp] Per-stream volume requires PipeWire";
        return;
    }
    
    volume = qBound(0.0, volume, 1.0);
    
    QProcess wpctl;
    wpctl.start("wpctl", {"set-volume", QString::number(streamId), QString::number(volume)});
    wpctl.waitForFinished(500);
    
    if (wpctl.exitCode() == 0) {
        qDebug() << "[AudioManagerCpp] Set stream" << streamId << "volume to:" << qRound(volume * 100) << "%";
        refreshStreams();
    } else {
        qWarning() << "[AudioManagerCpp] Failed to set stream volume:" << wpctl.errorString();
    }
}

void AudioManagerCpp::setStreamMuted(int streamId, bool muted)
{
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

void AudioManagerCpp::refreshStreams()
{
    if (m_isPipeWire) {
        parseWpctlStatus();
    }
}

void AudioManagerCpp::parseWpctlStatus()
{
    QProcess process;
    process.start("wpctl", {"status"});
    process.waitForFinished(2000);
    
    if (process.exitCode() != 0) {
        return;
    }
    
    QString output = process.readAllStandardOutput();
    QList<AudioStream> streams;
    
    // Parse wpctl status output to find audio streams
    // Format: " │  ├─ 47. Firefox                      [vol: 0.65]"
    //        or " │  ├─ 47. Firefox                      [vol: 0.65 MUTED]"
    QRegularExpression streamRe("^\\s+[│├─]+\\s+(\\d+)\\.\\s+(.+?)\\s+\\[vol:\\s+([0-9.]+)(?:\\s+MUTED)?\\]", QRegularExpression::MultilineOption);
    
    bool inSinksSection = false;
    bool inStreamsSection = false;
    
    QStringList lines = output.split('\n');
    for (const QString& line : lines) {
        if (line.contains("Sinks:", Qt::CaseInsensitive)) {
            inSinksSection = true;
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
        
        // Only parse streams in the Sinks section or Streams section
        if (!inSinksSection && !inStreamsSection) {
            continue;
        }
        
        QRegularExpressionMatch match = streamRe.match(line);
        if (match.hasMatch()) {
            AudioStream stream;
            stream.id = match.captured(1).toInt();
            stream.name = match.captured(2).trimmed();
            stream.appName = stream.name; // Use name as appName for now
            stream.volume = match.captured(3).toDouble();
            stream.muted = line.contains("MUTED");
            stream.mediaClass = inStreamsSection ? "Stream/Output/Audio" : "Audio/Sink";
            
            // Only add output streams (not sinks themselves)
            if (inStreamsSection && stream.id > 0) {
                streams.append(stream);
            }
        }
    }
    
    qDebug() << "[AudioManagerCpp] Found" << streams.size() << "audio streams";
    m_streamModel->updateStreams(streams);
    emit streamsChanged();
    
    // Update playback state based on active streams
    updatePlaybackState();
}

void AudioManagerCpp::startStreamMonitoring()
{
    // Refresh streams every 5 seconds
    connect(m_streamRefreshTimer, &QTimer::timeout, this, &AudioManagerCpp::refreshStreams);
    m_streamRefreshTimer->start(5000);
    qDebug() << "[AudioManagerCpp] Started stream monitoring (5s interval)";
}

void AudioManagerCpp::startVolumeMonitoring()
{
    // Poll volume every 500ms to detect external changes (hardware keys)
    QTimer* volumeMonitor = new QTimer(this);
    connect(volumeMonitor, &QTimer::timeout, this, &AudioManagerCpp::checkExternalVolumeChange);
    volumeMonitor->start(500);
    qDebug() << "[AudioManagerCpp] Started volume monitoring (500ms polling)";
}

void AudioManagerCpp::checkExternalVolumeChange()
{
    if (!m_available) return;
    
    double externalVolume = 0.0;
    
    // Try PipeWire first
    QProcess wpctl;
    wpctl.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
    wpctl.waitForFinished(200);
    
    if (wpctl.exitCode() == 0) {
        QString output = wpctl.readAllStandardOutput();
        QRegularExpression re("Volume: ([0-9.]+)");
        QRegularExpressionMatch match = re.match(output);
        if (match.hasMatch()) {
            externalVolume = match.captured(1).toDouble();
            
            // Check if volume changed externally
            if (qAbs(externalVolume - m_currentVolume) > 0.01) {
                qDebug() << "[AudioManagerCpp] Volume changed externally:" << qRound(externalVolume * 100) << "%";
                m_currentVolume = externalVolume;
                emit volumeChanged();
            }
        }
        return;
    }
    
    // Fallback to PulseAudio
    QProcess pactl;
    pactl.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
    pactl.waitForFinished(200);
    
    if (pactl.exitCode() == 0) {
        QString output = pactl.readAllStandardOutput();
        QRegularExpression re("Volume: .*? (\\d+)%");
        QRegularExpressionMatch match = re.match(output);
        if (match.hasMatch()) {
            externalVolume = match.captured(1).toDouble() / 100.0;
            
            // Check if volume changed externally
            if (qAbs(externalVolume - m_currentVolume) > 0.01) {
                qDebug() << "[AudioManagerCpp] Volume changed externally:" << qRound(externalVolume * 100) << "%";
                m_currentVolume = externalVolume;
                emit volumeChanged();
            }
        }
    }
}

void AudioManagerCpp::updatePlaybackState()
{
    // Check if any streams are currently playing
    // A stream is considered "playing" if it exists and is not muted
    // (wpctl doesn't provide explicit playback state, so we use stream existence as a proxy)
    
    bool wasPlaying = m_isPlaying;
    bool isNowPlaying = false;
    
    // If we have any active streams in the model, consider audio as playing
    if (m_streamModel->rowCount() > 0) {
        isNowPlaying = true;
    }
    
    if (wasPlaying != isNowPlaying) {
        m_isPlaying = isNowPlaying;
        qInfo() << "[AudioManagerCpp] Playback state changed:" << (isNowPlaying ? "PLAYING" : "STOPPED");
        emit isPlayingChanged();
    }
}

