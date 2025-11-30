#include "audioroutingmanager.h"
#include <QRegularExpression>

AudioRoutingManager::AudioRoutingManager(QObject *parent)
    : QObject(parent)
    , m_isInCall(false)
    , m_isSpeakerphoneEnabled(false)
    , m_isMuted(false)
    , m_currentAudioDevice("earpiece")
    , m_previousProfile("HiFi")
    , m_wpctlProcess(nullptr)
    , m_deviceDetectionTimer(new QTimer(this))
{
    qDebug() << "[AudioRoutingManager] Initializing";
    
    // Detect audio devices on startup
    detectAudioDevices();
    
    // Periodic device detection (in case devices are hotplugged)
    m_deviceDetectionTimer->setInterval(5000); // Every 5 seconds
    connect(m_deviceDetectionTimer, &QTimer::timeout, this, &AudioRoutingManager::detectAudioDevices);
    m_deviceDetectionTimer->start();
    
    qInfo() << "[AudioRoutingManager] Initialized";
}

AudioRoutingManager::~AudioRoutingManager()
{
    if (m_isInCall) {
        stopCallAudio();
    }
    
    if (m_wpctlProcess && m_wpctlProcess->state() == QProcess::Running) {
        m_wpctlProcess->kill();
        m_wpctlProcess->waitForFinished();
    }
}

void AudioRoutingManager::startCallAudio()
{
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

void AudioRoutingManager::stopCallAudio()
{
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

void AudioRoutingManager::setSpeakerphone(bool enabled)
{
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

void AudioRoutingManager::setMuted(bool muted)
{
    if (m_isMuted == muted) {
        return;
    }
    
    qInfo() << "[AudioRoutingManager] Microphone:" << (muted ? "MUTED" : "UNMUTED");
    
    m_isMuted = muted;
    emit mutedChanged(muted);
    
    // Mute/unmute the default microphone source
    runWpctlCommand("wpctl", QStringList() << "set-mute" << "@DEFAULT_SOURCE@" << (muted ? "1" : "0"));
}

void AudioRoutingManager::selectAudioDevice(const QString& device)
{
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

void AudioRoutingManager::switchProfile(const QString& profileName)
{
    if (m_audioCardId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] Audio card ID not detected, cannot switch profile";
        detectAudioDevices(); // Retry detection
        return;
    }
    
    qInfo() << "[AudioRoutingManager] Switching to profile:" << profileName << "on card" << m_audioCardId;
    
    // Save current profile if switching away from HiFi
    if (profileName == "VoiceCall") {
        m_previousProfile = "HiFi"; // Assume HiFi was active
    }
    
    runWpctlCommand("wpctl", QStringList() << "set-profile" << m_audioCardId << profileName);
}

void AudioRoutingManager::setDefaultSink(const QString& sinkId)
{
    if (sinkId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] Cannot set default sink: empty ID";
        return;
    }
    
    qInfo() << "[AudioRoutingManager] Setting default sink:" << sinkId;
    runWpctlCommand("wpctl", QStringList() << "set-default" << sinkId);
}

void AudioRoutingManager::runWpctlCommand(const QString& command, const QStringList& args)
{
    // Kill any existing process
    if (m_wpctlProcess && m_wpctlProcess->state() == QProcess::Running) {
        m_wpctlProcess->kill();
        m_wpctlProcess->waitForFinished(1000);
    }
    
    if (!m_wpctlProcess) {
        m_wpctlProcess = new QProcess(this);
        connect(m_wpctlProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &AudioRoutingManager::onWpctlFinished);
    }
    
    qDebug() << "[AudioRoutingManager] Running:" << command << args.join(" ");
    
    m_wpctlProcess->start(command, args);
}

void AudioRoutingManager::onWpctlFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        QString error = m_wpctlProcess->readAllStandardError();
        qWarning() << "[AudioRoutingManager] wpctl command failed:" << exitCode << error;
        emit audioRoutingFailed(error);
    } else {
        qDebug() << "[AudioRoutingManager] wpctl command succeeded";
    }
}

void AudioRoutingManager::detectAudioDevices()
{
    // Run wpctl status to discover audio devices
    QProcess wpctl;
    wpctl.start("wpctl", QStringList() << "status");
    
    if (!wpctl.waitForFinished(5000)) {
        qWarning() << "[AudioRoutingManager] wpctl command timed out or failed";
        QString error = wpctl.readAllStandardError();
        qWarning() << "[AudioRoutingManager] wpctl error:" << error;
        m_deviceDetectionTimer->stop();
        return;
    }
    
    QString output = wpctl.readAllStandardOutput();
    QString error = wpctl.readAllStandardError();
    
    if (!error.isEmpty()) {
        qWarning() << "[AudioRoutingManager] wpctl stderr:" << error;
    }
    if (output.isEmpty()) {
        qWarning() << "[AudioRoutingManager] wpctl returned empty output!";
        return;
    }
    parseWpctlStatus(output);
}

void AudioRoutingManager::parseWpctlStatus(const QString& output)
{
    // Parse wpctl status output to find:
    // - Audio card ID
    // - Earpiece sink ID
    // - Speaker sink ID
    // - Bluetooth sink ID (if available)
    // - Microphone source ID
    
    // Example output format:
    // Audio
    //  ├─ Devices:
    //  │      53. Built-in Audio                   [alsa]
    //  │  
    //  ├─ Sinks:
    //  │      54. Built-in Audio Analog Stereo    [vol: 0.65]
    //  │  
    //  ├─ Sources:
    //  │      55. Built-in Audio Analog Stereo    [vol: 0.80]
    
    QStringList lines = output.split('\n');
    bool inDevices = false;
    bool inSinks = false;
    bool inSources = false;
    
    for (const QString& line : lines) {
        // Section detection
        if (line.contains("Devices:")) {
            inDevices = true;
            inSinks = false;
            inSources = false;
            continue;
        } else if (line.contains("Sinks:")) {
            inDevices = false;
            inSinks = true;
            inSources = false;
            continue;
        } else if (line.contains("Sources:")) {
            inDevices = false;
            inSinks = false;
            inSources = true;
            continue;
        }
        
        // Extract device/sink/source IDs
        // Match lines like: " │      42. Virtio 1.0 sound                    [alsa]"
        // or: " *   51. Virtio 1.0 sound Stereo             [vol: 0.47]"
        // Note: wpctl uses box-drawing characters, so match any non-digit chars before the number
        QRegularExpression idRegex(R"((\d+)\.\s+(.+?)(?:\s+\[|$))");
        QRegularExpressionMatch match = idRegex.match(line);
        
        if (match.hasMatch()) {
            QString id = match.captured(1);
            QString name = match.captured(2).trimmed();
            
            if (inDevices) {
                if (name.contains("Built-in", Qt::CaseInsensitive) || 
                    name.contains("Audio", Qt::CaseInsensitive) ||
                    name.contains("sound", Qt::CaseInsensitive) ||
                    name.contains("Sound", Qt::CaseInsensitive)) {
                    // Use first matching audio device as card ID
                    if (m_audioCardId.isEmpty()) {
                m_audioCardId = id;
                        qInfo() << "[AudioRoutingManager] ✓ Found audio card:" << id << name;
                    }
                }
            } else if (inSinks) {
                // Heuristic: detect earpiece vs speaker by name
                if (name.contains("Earpiece", Qt::CaseInsensitive)) {
                    if (m_earpieceSinkId.isEmpty()) {
                    m_earpieceSinkId = id;
                    qDebug() << "[AudioRoutingManager] Found earpiece:" << id << name;
                    }
                } else if (name.contains("Speaker", Qt::CaseInsensitive) || name.contains("Stereo", Qt::CaseInsensitive)) {
                    if (m_speakerSinkId.isEmpty()) {
                    m_speakerSinkId = id;
                    qDebug() << "[AudioRoutingManager] Found speaker:" << id << name;
                    }
                } else if (name.contains("Bluetooth", Qt::CaseInsensitive) || name.contains("bluez", Qt::CaseInsensitive)) {
                    if (m_bluetoothSinkId.isEmpty()) {
                    m_bluetoothSinkId = id;
                    qDebug() << "[AudioRoutingManager] Found Bluetooth:" << id << name;
                    }
                }
                
                // Fallback: use first sink as default
                if (m_earpieceSinkId.isEmpty() && m_speakerSinkId.isEmpty()) {
                    m_earpieceSinkId = id; // Assume first sink is earpiece
                }
            } else if (inSources) {
                if (m_microphoneSourceId.isEmpty()) {
                    m_microphoneSourceId = id;
                    qDebug() << "[AudioRoutingManager] Found microphone:" << id << name;
                }
            }
        }
    }
    
    if (m_audioCardId.isEmpty()) {
        qWarning() << "[AudioRoutingManager] No audio card detected!";
    }
}

QString AudioRoutingManager::findAudioCard()
{
    QProcess wpctl;
    wpctl.start("wpctl", QStringList() << "status");
    
    if (!wpctl.waitForFinished(5000)) {
        return QString();
    }
    
    QString output = wpctl.readAllStandardOutput();
    
    // Find first audio device
    QRegularExpression regex(R"((\d+)\.\s+.*Built-in.*Audio)");
    QRegularExpressionMatch match = regex.match(output);
    
    if (match.hasMatch()) {
        return match.captured(1);
    }
    
    return QString();
}

QString AudioRoutingManager::findSinkByName(const QString& name)
{
    QProcess wpctl;
    wpctl.start("wpctl", QStringList() << "status");
    
    if (!wpctl.waitForFinished(5000)) {
        return QString();
    }
    
    QString output = wpctl.readAllStandardOutput();
    
    // Find sink matching name
    QRegularExpression regex(QString(R"((\d+)\.\s+.*%1)").arg(QRegularExpression::escape(name)));
    QRegularExpressionMatch match = regex.match(output);
    
    if (match.hasMatch()) {
        return match.captured(1);
    }
    
    return QString();
}

