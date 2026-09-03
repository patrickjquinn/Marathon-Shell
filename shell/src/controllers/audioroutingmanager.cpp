#include "audioroutingmanager.h"

#include <pipewire/pipewire.h>
#include <spa/utils/hook.h>

#include <QHash>
#include <QString>

// PipeWire state lives entirely in this translation unit; the .h forward-declares.
struct AudioRoutingManager::PwState {
    pw_thread_loop      *loop     = nullptr;
    pw_context          *context  = nullptr;
    pw_core             *core     = nullptr;
    pw_registry         *registry = nullptr;
    spa_hook             registryListener{};
    AudioRoutingManager *owner = nullptr;

    // id -> registry-event signature so we can clear the right slot on remove.
    // Recording the kind keeps the remove path O(1) and decoupled from PipeWire
    // reordering the globals over a session.
    QHash<quint32, QString> kinds; // "card" | "earpiece" | "speaker" | "bluetooth" | "microphone"
};

namespace {
    QString propsGet(const spa_dict *dict, const char *key) {
        if (!dict || !key)
            return {};
        const char *val = spa_dict_lookup(dict, key);
        return val ? QString::fromUtf8(val) : QString();
    }

    void onPwGlobal(void *data, uint32_t id, uint32_t /*perms*/, const char *type,
                    uint32_t /*version*/, const spa_dict *props) {
        auto *state = static_cast<AudioRoutingManager::PwState *>(data);
        if (!state || !state->owner || !type)
            return;

        const QString typeStr    = QString::fromUtf8(type);
        const QString nodeName   = propsGet(props, PW_KEY_NODE_NAME);
        const QString deviceName = propsGet(props, PW_KEY_DEVICE_NAME);
        const QString mediaClass = propsGet(props, PW_KEY_MEDIA_CLASS);

        QMetaObject::invokeMethod(
            state->owner,
            [owner = state->owner, id, typeStr, nodeName, deviceName, mediaClass] {
                owner->onPwGlobalAdded(id, typeStr, nodeName, deviceName, mediaClass);
            },
            Qt::QueuedConnection);
    }

    void onPwGlobalRemove(void *data, uint32_t id) {
        auto *state = static_cast<AudioRoutingManager::PwState *>(data);
        if (!state || !state->owner)
            return;
        QMetaObject::invokeMethod(
            state->owner, [owner = state->owner, id] { owner->onPwGlobalRemoved(id); },
            Qt::QueuedConnection);
    }

    const pw_registry_events kRegistryEvents = {
        PW_VERSION_REGISTRY_EVENTS,
        onPwGlobal,
        onPwGlobalRemove,
    };
} // namespace

AudioRoutingManager::AudioRoutingManager(QObject *parent)
    : QObject(parent)
    , m_isInCall(false)
    , m_isSpeakerphoneEnabled(false)
    , m_isMuted(false)
    , m_currentAudioDevice("earpiece")
    , m_previousProfile("HiFi")
    , m_wpctlProcess(nullptr)
    , m_pw(std::make_unique<PwState>()) {
    qDebug() << "[AudioRoutingManager] Initializing";

    pw_init(nullptr, nullptr);

    m_pw->owner = this;
    m_pw->loop  = pw_thread_loop_new("marathon-audio-routing", nullptr);
    if (!m_pw->loop) {
        qWarning() << "[AudioRoutingManager] pw_thread_loop_new failed; audio routing inert";
        return;
    }

    pw_thread_loop_lock(m_pw->loop);
    m_pw->context = pw_context_new(pw_thread_loop_get_loop(m_pw->loop), nullptr, 0);
    if (!m_pw->context) {
        pw_thread_loop_unlock(m_pw->loop);
        qWarning() << "[AudioRoutingManager] pw_context_new failed";
        return;
    }
    m_pw->core = pw_context_connect(m_pw->context, nullptr, 0);
    if (!m_pw->core) {
        pw_thread_loop_unlock(m_pw->loop);
        qWarning() << "[AudioRoutingManager] pw_context_connect failed (is pipewire running?)";
        return;
    }
    m_pw->registry = pw_core_get_registry(m_pw->core, PW_VERSION_REGISTRY, 0);
    if (!m_pw->registry) {
        pw_thread_loop_unlock(m_pw->loop);
        qWarning() << "[AudioRoutingManager] pw_core_get_registry failed";
        return;
    }
    pw_registry_add_listener(m_pw->registry, &m_pw->registryListener, &kRegistryEvents, m_pw.get());
    pw_thread_loop_unlock(m_pw->loop);

    if (pw_thread_loop_start(m_pw->loop) != 0) {
        qWarning() << "[AudioRoutingManager] pw_thread_loop_start failed";
    }

    qInfo() << "[AudioRoutingManager] Initialized (libpipewire subscription)";
}

AudioRoutingManager::~AudioRoutingManager() {
    if (m_isInCall) {
        stopCallAudio();
    }

    if (m_wpctlProcess && m_wpctlProcess->state() == QProcess::Running) {
        m_wpctlProcess->kill();
        m_wpctlProcess->waitForFinished();
    }

    if (m_pw && m_pw->loop) {
        pw_thread_loop_lock(m_pw->loop);
        if (m_pw->registry) {
            spa_hook_remove(&m_pw->registryListener);
            pw_proxy_destroy(reinterpret_cast<pw_proxy *>(m_pw->registry));
        }
        if (m_pw->core) {
            pw_core_disconnect(m_pw->core);
        }
        if (m_pw->context) {
            pw_context_destroy(m_pw->context);
        }
        pw_thread_loop_unlock(m_pw->loop);
        pw_thread_loop_stop(m_pw->loop);
        pw_thread_loop_destroy(m_pw->loop);
    }
    pw_deinit();
}

void AudioRoutingManager::startCallAudio() {
    if (m_isInCall) {
        qDebug() << "[AudioRoutingManager] Already in call, ignoring startCallAudio";
        return;
    }

    qInfo() << "[AudioRoutingManager] Starting call audio routing";

    m_isInCall = true;
    emit inCallChanged(true);

    // Direct UCM-profile switch on the L5 wm8962 — no callaudiod indirection.
    // Picks HiFi (Handset1, Handset2) which programs the codec mixer for
    // earpiece-out + modem-PCM-in (the SoC SAI links bm818<->wm8962 at the
    // kernel level so flipping the codec mixer is the whole job).
    switchProfile("VoiceCall");

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

    switchProfile(m_previousProfile.isEmpty() ? "Default" : m_previousProfile);

    if (m_isMuted) {
        setMuted(false);
    }

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
        // Both modes still source the mic from the modem PCM (Handset2);
        // toggle picks earpiece vs loud speaker for the output side.
        switchProfile(enabled ? "Speakerphone" : "VoiceCall");
    }
}

void AudioRoutingManager::setMuted(bool muted) {
    if (m_isMuted == muted) {
        return;
    }

    qInfo() << "[AudioRoutingManager] Microphone:" << (muted ? "MUTED" : "UNMUTED");

    m_isMuted = muted;
    emit mutedChanged(muted);

    runWpctlCommand("wpctl",
                    QStringList() << "set-mute" << "@DEFAULT_SOURCE@" << (muted ? "1" : "0"));
}

void AudioRoutingManager::selectAudioDevice(const QString &device) {
    if (m_currentAudioDevice == device) {
        return;
    }

    qInfo() << "[AudioRoutingManager] Selecting audio device:" << device;

    m_currentAudioDevice = device;
    emit    audioDeviceChanged(device);

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

        if (device == "earpiece" || device == "speaker") {
            switchProfile("VoiceCall");
        }
    }
}

void AudioRoutingManager::switchProfile(const QString &profileName) {
    if (m_audioCardName.isEmpty()) {
        qWarning() << "[AudioRoutingManager] Audio card name not detected, cannot switch profile";
        return;
    }

    // Marathon's logical names → concrete UCM profile strings exposed by the
    // L5 wm8962 card. The legacy mobian model assumed a single "VoiceCall"
    // PulseAudio profile that doesn't exist here; this card exposes per-
    // device combinations (Handset1=earpiece, Handset2=modem mic, Speaker,
    // Mic, Headphones). Fix is platform-aware mapping, not callaudiod.
    QString platformProfile;
    if (profileName == "VoiceCall") {
        platformProfile   = "HiFi (Handset1, Handset2)"; // earpiece + modem mic
        m_previousProfile = "Default";
    } else if (profileName == "Speakerphone") {
        platformProfile = "HiFi (Handset2, Speaker)"; // loud speaker + modem mic
    } else {
        // "Default" / "HiFi" / anything else → media-playback profile
        platformProfile = "HiFi (Mic, Speaker)";
    }

    qInfo() << "[AudioRoutingManager] Switching to profile:" << profileName << "->"
            << platformProfile << "on card" << m_audioCardName;

    runWpctlCommand("pactl",
                    QStringList() << "set-card-profile" << m_audioCardName << platformProfile);
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

void AudioRoutingManager::onPwGlobalAdded(quint32 id, const QString &type, const QString &nodeName,
                                          const QString &deviceName, const QString &mediaClass) {
    if (type.contains(QStringLiteral("Interface:Device"))) {
        // Prefer the on-board codec (platform-sound) over HDMI/USB cards;
        // pactl set-card-profile keys off device.name so cache that too.
        if (deviceName.contains(QStringLiteral("alsa_card.platform-sound")) &&
            !deviceName.contains(QStringLiteral("hdmi")) && m_audioCardId.isEmpty()) {
            m_audioCardId   = QString::number(id);
            m_audioCardName = deviceName;
            m_pw->kinds[id] = QStringLiteral("card");
            qInfo() << "[AudioRoutingManager] Found audio card:" << id << deviceName;

            // Card boots to profile=off on this platform — no audio at all
            // until something selects a profile. Default to media (speaker +
            // built-in mic); switchProfile will flip to voice on call start.
            QMetaObject::invokeMethod(
                this, [this] { switchProfile(QStringLiteral("Default")); }, Qt::QueuedConnection);
        }
        return;
    }
    if (!type.contains(QStringLiteral("Interface:Node")))
        return;

    if (mediaClass == QStringLiteral("Audio/Sink")) {
        if (nodeName.contains("earpiece", Qt::CaseInsensitive) && m_earpieceSinkId.isEmpty()) {
            m_earpieceSinkId = QString::number(id);
            m_pw->kinds[id]  = QStringLiteral("earpiece");
            qDebug() << "[AudioRoutingManager] Found earpiece:" << id << nodeName;
        } else if ((nodeName.contains("speaker", Qt::CaseInsensitive) ||
                    nodeName.contains("stereo", Qt::CaseInsensitive)) &&
                   m_speakerSinkId.isEmpty()) {
            m_speakerSinkId = QString::number(id);
            m_pw->kinds[id] = QStringLiteral("speaker");
            qDebug() << "[AudioRoutingManager] Found speaker:" << id << nodeName;
        } else if ((nodeName.contains("bluetooth", Qt::CaseInsensitive) ||
                    nodeName.contains("bluez", Qt::CaseInsensitive)) &&
                   m_bluetoothSinkId.isEmpty()) {
            m_bluetoothSinkId = QString::number(id);
            m_pw->kinds[id]   = QStringLiteral("bluetooth");
            qDebug() << "[AudioRoutingManager] Found Bluetooth:" << id << nodeName;
        } else if (m_speakerSinkId.isEmpty()) {
            m_speakerSinkId = QString::number(id);
            m_pw->kinds[id] = QStringLiteral("speaker");
        }
    } else if (mediaClass == QStringLiteral("Audio/Source")) {
        if (!nodeName.contains("monitor", Qt::CaseInsensitive) && m_microphoneSourceId.isEmpty()) {
            m_microphoneSourceId = QString::number(id);
            m_pw->kinds[id]      = QStringLiteral("microphone");
            qDebug() << "[AudioRoutingManager] Found microphone:" << id << nodeName;
        }
    }
}

void AudioRoutingManager::onPwGlobalRemoved(quint32 id) {
    const QString kind = m_pw->kinds.take(id);
    if (kind.isEmpty())
        return;

    if (kind == QStringLiteral("card")) {
        m_audioCardId.clear();
    } else if (kind == QStringLiteral("earpiece")) {
        m_earpieceSinkId.clear();
    } else if (kind == QStringLiteral("speaker")) {
        m_speakerSinkId.clear();
    } else if (kind == QStringLiteral("bluetooth")) {
        m_bluetoothSinkId.clear();
    } else if (kind == QStringLiteral("microphone")) {
        m_microphoneSourceId.clear();
    }
    qDebug() << "[AudioRoutingManager] Lost" << kind << "id" << id;
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
