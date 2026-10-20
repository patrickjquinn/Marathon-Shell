#include "audioroutingmanager.h"
#include "marathon-shell-native/src/audio.cxxqt.h"

#include <QDebug>

AudioRoutingManager::AudioRoutingManager(marathon::Audio *audio, QObject *parent)
    : QObject(parent)
    , m_audio(audio) {}

void AudioRoutingManager::startCallAudio() {
    if (m_isInCall)
        return;
    qInfo() << "[AudioRoutingManager] Call audio on";
    m_isInCall = true;
    emit inCallChanged(true);
}

// The next call starts on the earpiece with the microphone open.
void AudioRoutingManager::stopCallAudio() {
    if (!m_isInCall)
        return;
    qInfo() << "[AudioRoutingManager] Call audio off";
    m_isInCall = false;
    emit inCallChanged(false);
    setMuted(false);
    setSpeakerphone(false);
}

void AudioRoutingManager::setSpeakerphone(bool enabled) {
    if (m_isSpeakerphoneEnabled == enabled)
        return;
    qInfo() << "[AudioRoutingManager] Speakerphone:" << (enabled ? "ON" : "OFF");
    m_isSpeakerphoneEnabled = enabled;
    emit speakerphoneChanged(enabled);
    m_audio->setSpeakerphone(enabled);
}

void AudioRoutingManager::setMuted(bool muted) {
    if (m_isMuted == muted)
        return;
    qInfo() << "[AudioRoutingManager] Microphone:" << (muted ? "MUTED" : "UNMUTED");
    m_isMuted = muted;
    emit mutedChanged(muted);
    m_audio->setInputMuted(muted);
}
