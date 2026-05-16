#pragma once

#include <QMediaPlayer>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTemporaryFile>
#include <QTextToSpeech>
#include <memory>
#include <qqmlregistration.h>

// VoiceClient — speaks turn-by-turn navigation cues.
//
// Two backends, picked at construction time:
//   1. piper-tts (preferred): neural TTS, far better intonation. We
//      shell out to the `piper` binary with the bundled voice model
//      (en_US-amy-low.onnx by default). Output WAV is played through
//      QMediaPlayer. Requires the marathon-image to install
//      `piper-tts` and ship the voice model under
//      /usr/share/marathon/voice/.
//   2. QTextToSpeech fallback: Qt's built-in speech-dispatcher path,
//      which on Fedora/Alpine/postmarketOS routes to espeak-ng. Lower
//      quality but available with no extra packages.
//
// On the dev rig (no Piper), this falls back transparently. On real
// device the user gets natural-sounding nav voice as soon as we ship
// piper-tts in the Marathon image.
class VoiceClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(VoiceClient)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool speaking READ speaking NOTIFY speakingChanged)
    Q_PROPERTY(QString backend READ backend CONSTANT)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)

  public:
    explicit VoiceClient(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool speaking() const {
        return m_speaking;
    }
    bool muted() const {
        return m_muted;
    }
    void setMuted(bool m) {
        if (m != m_muted) {
            m_muted = m;
            if (m_muted)
                stop();
            emit mutedChanged();
        }
    }
    QString backend() const {
        return m_backend;
    }

    Q_INVOKABLE void speak(const QString &text);
    Q_INVOKABLE void stop();

  signals:
    void speakingChanged();
    void mutedChanged();

  private:
    bool                            detectPiper();
    void                            speakViaPiper(const QString &text);
    void                            speakViaQTextToSpeech(const QString &text);
    void                            setSpeaking(bool s);

    bool                            m_available = false;
    bool                            m_speaking  = false;
    bool                            m_muted     = false;
    QString                         m_backend;
    QString                         m_piperBin;
    QString                         m_piperModel; // path to en_US-*.onnx
    std::unique_ptr<QTextToSpeech>  m_tts;
    std::unique_ptr<QProcess>       m_piperProcess;
    std::unique_ptr<QMediaPlayer>   m_player;
    std::unique_ptr<QTemporaryFile> m_wavFile;
};
