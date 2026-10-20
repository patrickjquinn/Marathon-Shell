#ifndef AUDIOROUTINGMANAGER_H
#define AUDIOROUTINGMANAGER_H

#include <QObject>

namespace marathon {
    class Audio;
}

// The call's speakerphone and microphone mute. Which card profile and route
// carry the call is WirePlumber's policy (marathon/call-routing.lua): it
// follows ModemManager's call and the speakerphone setting written here.
class AudioRoutingManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isInCall READ isInCall NOTIFY inCallChanged)
    Q_PROPERTY(bool isSpeakerphoneEnabled READ isSpeakerphoneEnabled NOTIFY speakerphoneChanged)
    Q_PROPERTY(bool isMuted READ isMuted NOTIFY mutedChanged)

  public:
    explicit AudioRoutingManager(marathon::Audio *audio, QObject *parent = nullptr);

    bool isInCall() const {
        return m_isInCall;
    }
    bool isSpeakerphoneEnabled() const {
        return m_isSpeakerphoneEnabled;
    }
    bool isMuted() const {
        return m_isMuted;
    }

  public slots:
    void startCallAudio();
    void stopCallAudio();
    void setSpeakerphone(bool enabled);
    void setMuted(bool muted);

  signals:
    void inCallChanged(bool isInCall);
    void speakerphoneChanged(bool enabled);
    void mutedChanged(bool muted);

  private:
    marathon::Audio *m_audio;
    bool             m_isInCall              = false;
    bool             m_isSpeakerphoneEnabled = false;
    bool             m_isMuted               = false;
};

#endif
