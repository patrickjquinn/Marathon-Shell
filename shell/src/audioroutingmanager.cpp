#include "audioroutingmanager.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

AudioRoutingManager::AudioRoutingManager(QObject *parent)
    : QObject(parent)
    , m_isInCall(false)
    , m_isSpeakerphoneEnabled(false)
    , m_isMuted(false)
    , m_currentAudioDevice("earpiece")
    , m_previousProfile("HiFi")
    , m_wpctlProcess(nullptr)
    , m_deviceDetectionTimer(new QTimer(this)) {
    qDebug() << "[AudioRoutingManager] Initializing";

    // Detect audio devices on startup
    detectAudioDevices();

    // Periodic device detection (in case devices are hotplugged)
    m_deviceDetectionTimer->setInterval(5000); // Every 5 seconds
    connect(m_deviceDetectionTimer, &QTimer::timeout, this,
            &AudioRoutingManager::detectAudioDevices);
    m_deviceDetectionTimer->start();

    qInfo() << "[AudioRoutingManager] Initialized";
}

AudioRoutingManager::~AudioRoutingManager() {
    if (m_isInCall) {
        stopCallAudio();
    }

    if (m_wpctlProcess && m_wpctlProcess->state() == QProcess::Running) {
        m_wpctlProcess->kill();
        m_wpctlProcess->waitForFinished();
    }
}

void AudioRoutingManager::startCallAudio() {
    if (m_isInCall) {
        qDebug() << "[AudioRoutingManager] Already in call, ignoring startCallAudio";
        return;
    }

    qInfo() << "[AudioRoutingManager] Starting call audio routing";

    m_isInCall = true;
    emit inCallChanged(true);

    // Switch to VoiceCall UCM profile (optimized for phone calls)
    // This routes audio to the earpiece and configures microphone for voice
    switchProfile("VoiceCall");

    // Default to earpiece unless speakerphone was enabled
    if (!m_isSpeakerphoneEnabled) {
        selectAudioDevice("earpiece");
    }
}

void AudioRoutingManager::stopCallAudio() {
    if (!m_isInCall) {
        qDebug() << "[AudioRoutingManager] Not in call, ignoring stopCallAudio";
        return;
    }

    qInfo() << "[AudioRoutingManager] Stopping call audio routing";

    m_isInCall = false;
    emit inCallChanged(false);

    // Restore normal audio profile (HiFi for music/media)
    switchProfile(m_previousProfile.isEmpty() ? "HiFi" : m_previousProfile);

    // Unmute if muted
    if (m_isMuted) {
        setMuted(false);
    }

    // Reset speakerphone
    m_isSpeakerphoneEnabled = false;
    emit speakerphoneChanged(false);
}

void AudioRoutingManager::setSpeakerphone(bool enabled) {
    if (m_isSpeakerphoneEnabled == enabled) {
        return;
    }

    qInfo() << "[AudioRoutingManager] Speakerphone:" << (enabled ? "ON" : "OFF");

    m_isSpeakerphoneEnabled = enabled;
    emit speakerphoneChanged(enabled);

    if (m_isInCall) {
        selectAudioDevice(enabled ? "speaker" : "earpiece");
    }
}

void AudioRoutingManager::setMuted(bool muted) {
    if (m_isMuted == muted) {
        return;
    }

    qInfo() << "[AudioRoutingManager] Microphone:" << (muted ? "MUTED" : "UNMUTED");

    m_isMuted = muted;
    emit mutedChanged(muted);

    // Mute/unmute the default microphone source
    runWpctlCommand("wpctl",
                    QStringList() << "set-mute" << "@DEFAULT_SOURCE@" << (muted ? "1" : "0"));
}

void AudioRoutingManager::selectAudioDevice(const QString &device) {
    if (m_currentAudioDevice == device) {
        return;
    }

    qInfo() << "[AudioRoutingManager] Selecting audio device:" << device;

    m_currentAudioDevice = device;
    emit audioDeviceChanged(device);

    // Map device names to sink IDs
    QString sinkId;

    if (device == "earpiece") {
        sinkId = m_earpieceSinkId;
    } else if (device == "speaker") {
        sinkId = m_speakerSinkId;
    } else if (device == "bluetooth") {
        sinkId = m_bluetoothSinkId;
    }

    if (!sinkId.isEmpty()) {
        setDefaultSink(sinkId);
    } else {
        qWarning() << "[AudioRoutingManager] Device sink ID not found:" << device;
        // Fallback: try to switch profile directly
        if (device == "earpiece" || device == "speaker") {
            switchProfile("VoiceCall");
        }
    }
}

void AudioRoutingManager::switchProfile(const QString &profileName) {
    if (m_audioCardId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] Audio card ID not detected, cannot switch profile";
        detectAudioDevices(); // Retry detection
        return;
    }

    qInfo() << "[AudioRoutingManager] Switching to profile:" << profileName << "on card"
            << m_audioCardId;

    // Save current profile if switching away from HiFi
    if (profileName == "VoiceCall") {
        m_previousProfile = "HiFi"; // Assume HiFi was active
    }

    runWpctlCommand("wpctl", QStringList() << "set-profile" << m_audioCardId << profileName);
}

void AudioRoutingManager::setDefaultSink(const QString &sinkId) {
    if (sinkId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] Cannot set default sink: empty ID";
        return;
    }

    qInfo() << "[AudioRoutingManager] Setting default sink:" << sinkId;
    runWpctlCommand("wpctl", QStringList() << "set-default" << sinkId);
}

void AudioRoutingManager::runWpctlCommand(const QString &command, const QStringList &args) {
    // Kill any existing process
    if (m_wpctlProcess && m_wpctlProcess->state() == QProcess::Running) {
        m_wpctlProcess->kill();
        m_wpctlProcess->waitForFinished(1000);
    }

    if (!m_wpctlProcess) {
        m_wpctlProcess = new QProcess(this);
        connect(m_wpctlProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                &AudioRoutingManager::onWpctlFinished);
    }

    qDebug() << "[AudioRoutingManager] Running:" << command << args.join(" ");

    m_wpctlProcess->start(command, args);
}

void AudioRoutingManager::onWpctlFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        QString error = m_wpctlProcess->readAllStandardError();
        qWarning() << "[AudioRoutingManager] wpctl command failed:" << exitCode << error;
        emit audioRoutingFailed(error);
    } else {
        qDebug() << "[AudioRoutingManager] wpctl command succeeded";
    }
}

void AudioRoutingManager::detectAudioDevices() {
    QProcess pwDump;
    pwDump.start("pw-dump", QStringList());

    if (!pwDump.waitForFinished(5000)) {
        qWarning() << "[AudioRoutingManager] pw-dump command timed out or failed";
        return;
    }

    QByteArray output = pwDump.readAllStandardOutput();
    if (output.isEmpty()) {
        qWarning() << "[AudioRoutingManager] pw-dump returned empty output!";
        return;
    }

    QJsonParseError parseError;
    QJsonDocument   doc = QJsonDocument::fromJson(output, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        qWarning() << "[AudioRoutingManager] Failed to parse pw-dump JSON:"
                   << parseError.errorString();
        return;
    }

    if (!doc.isArray()) {
        qWarning() << "[AudioRoutingManager] pw-dump output is not a JSON array";
        return;
    }

    QJsonArray objects = doc.array();
    for (const QJsonValue &val : objects) {
        QJsonObject obj   = val.toObject();
        QString     type  = obj["type"].toString();
        int         id    = obj["id"].toInt();
        QJsonObject info  = obj["info"].toObject();
        QJsonObject props = info["props"].toObject();

        if (type.contains("PipeWire:Interface:Device")) {
            QString deviceName = props["device.name"].toString();
            if (deviceName.contains("alsa_card") && m_audioCardId.isEmpty()) {
                m_audioCardId = QString::number(id);
                qInfo() << "[AudioRoutingManager] Found audio card:" << id << deviceName;
            }
        }

        if (type.contains("PipeWire:Interface:Node")) {
            QString mediaClass = props["media.class"].toString();
            QString nodeName   = props["node.name"].toString();

            if (mediaClass == "Audio/Sink") {
                if (nodeName.contains("earpiece", Qt::CaseInsensitive) &&
                    m_earpieceSinkId.isEmpty()) {
                    m_earpieceSinkId = QString::number(id);
                    qDebug() << "[AudioRoutingManager] Found earpiece:" << id << nodeName;
                } else if ((nodeName.contains("speaker", Qt::CaseInsensitive) ||
                            nodeName.contains("stereo", Qt::CaseInsensitive)) &&
                           m_speakerSinkId.isEmpty()) {
                    m_speakerSinkId = QString::number(id);
                    qDebug() << "[AudioRoutingManager] Found speaker:" << id << nodeName;
                } else if ((nodeName.contains("bluetooth", Qt::CaseInsensitive) ||
                            nodeName.contains("bluez", Qt::CaseInsensitive)) &&
                           m_bluetoothSinkId.isEmpty()) {
                    m_bluetoothSinkId = QString::number(id);
                    qDebug() << "[AudioRoutingManager] Found Bluetooth:" << id << nodeName;
                } else if (m_speakerSinkId.isEmpty()) {
                    m_speakerSinkId = QString::number(id);
                }
            } else if (mediaClass == "Audio/Source") {
                if (!nodeName.contains("monitor", Qt::CaseInsensitive) &&
                    m_microphoneSourceId.isEmpty()) {
                    m_microphoneSourceId = QString::number(id);
                    qDebug() << "[AudioRoutingManager] Found microphone:" << id << nodeName;
                }
            }
        }
    }

    if (m_audioCardId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] No audio card detected!";
    }
}

QString AudioRoutingManager::findAudioCard() {
    return m_audioCardId;
}

QString AudioRoutingManager::findSinkByName(const QString &name) {
    if (name.contains("earpiece", Qt::CaseInsensitive))
        return m_earpieceSinkId;
    if (name.contains("speaker", Qt::CaseInsensitive))
        return m_speakerSinkId;
    if (name.contains("bluetooth", Qt::CaseInsensitive))
        return m_bluetoothSinkId;
    return m_speakerSinkId;
}
