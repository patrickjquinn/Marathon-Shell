#include "audiomanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>

AudioManagerCpp::AudioManagerCpp(QObject* parent)
    : QObject(parent)
    , m_available(false)
    , m_currentVolume(0.6)
    , m_muted(false)
{
    qDebug() << "[AudioManagerCpp] Initializing";
    
    if (Platform::hasPulseAudio()) {
        m_available = true;
        qInfo() << "[AudioManagerCpp] PulseAudio available";
        
        // Query initial volume
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
        qInfo() << "[AudioManagerCpp] PulseAudio not available, using mock mode";
    }
}

void AudioManagerCpp::setVolume(double volume)
{
    if (!m_available) return;
    
    // Clamp volume to 0.0-1.0
    volume = qBound(0.0, volume, 1.0);
    
    int percent = qRound(volume * 100);
    QProcess::execute("pactl", {"set-sink-volume", "@DEFAULT_SINK@", QString::number(percent) + "%"});
    
    m_currentVolume = volume;
    emit volumeChanged();
    qDebug() << "[AudioManagerCpp] Set volume to:" << percent << "%";
}

void AudioManagerCpp::setMuted(bool muted)
{
    if (!m_available) return;
    
    QProcess::execute("pactl", {"set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"});
    
    m_muted = muted;
    emit mutedChanged();
    qDebug() << "[AudioManagerCpp] Set muted to:" << muted;
}

