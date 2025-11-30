#include "audiomanagercpp.h"
#include "platform.h"
#include <QDebug>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QProcess>
#include <QRegularExpression>

AudioManagerCpp::AudioManagerCpp(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_currentVolume(0.6)
    , m_muted(false) {
    qDebug() << "[AudioManagerCpp] Initializing";

    // Try PipeWire first via wpctl
    QProcess checkPipewire;
    checkPipewire.start("wpctl", {"status"});
    checkPipewire.waitForFinished(1000);

    if (checkPipewire.exitCode() == 0) {
        m_available = true;
        qInfo() << "[AudioManagerCpp] PipeWire/WirePlumber available";

        // Get initial volume
        QProcess process;
        process.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
        process.waitForFinished();
        QString output = process.readAllStandardOutput();

        // Parse "Volume: 0.60" or "Volume: 0.60 [MUTED]"
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
    } else {
        // Fallback to PulseAudio
        QProcess checkPulse;
        checkPulse.start("pactl", {"info"});
        checkPulse.waitForFinished(1000);

        if (checkPulse.exitCode() == 0) {
            m_available = true;
            qInfo() << "[AudioManagerCpp] PulseAudio available";

            QProcess process;
            process.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
            process.waitForFinished();
            QString                 output = process.readAllStandardOutput();

            QRegularExpression      re("Volume: .*? (\\d+)%");
            QRegularExpressionMatch match = re.match(output);
            if (match.hasMatch()) {
                m_currentVolume = match.captured(1).toDouble() / 100.0;
                emit volumeChanged();
            }
        } else {
            qInfo()
                << "[AudioManagerCpp] Neither PipeWire nor PulseAudio available, using mock mode";
        }
    }
}

void AudioManagerCpp::setVolume(double volume) {
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
    QProcess::execute("pactl",
                      {"set-sink-volume", "@DEFAULT_SINK@", QString::number(percent) + "%"});

    m_currentVolume = volume;
    emit volumeChanged();
    qDebug() << "[AudioManagerCpp] Set volume to:" << percent << "% (PulseAudio)";
}

void AudioManagerCpp::setMuted(bool muted) {
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
