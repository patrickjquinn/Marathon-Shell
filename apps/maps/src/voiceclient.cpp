#include "voiceclient.h"

#include <QAudioOutput>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

VoiceClient::VoiceClient(QObject *parent)
    : QObject(parent) {
    if (detectPiper()) {
        m_available = true;
        m_backend   = QStringLiteral("piper");
    } else {
        m_tts.reset(new QTextToSpeech(this));
        if (m_tts->state() != QTextToSpeech::Error) {
            m_available = true;
            m_backend   = QStringLiteral("qtexttospeech");
            connect(m_tts.get(), &QTextToSpeech::stateChanged, this,
                    [this](QTextToSpeech::State state) {
                        setSpeaking(state == QTextToSpeech::Speaking);
                    });
        } else {
            m_available = false;
            m_backend   = QStringLiteral("none");
            qWarning() << "[VoiceClient] No TTS backend available";
        }
    }
}

bool VoiceClient::detectPiper() {
    // Standard install paths the Marathon image lays down. Piper is
    // typically in /usr/bin and the voice model lives under
    // /usr/share/marathon/voice/. We don't bundle these in the repo
    // (50 MB) — the image build pulls them.
    const QStringList binCandidates   = {QStringLiteral("/usr/bin/piper"),
                                         QStringLiteral("/usr/local/bin/piper"),
                                         QDir::homePath() + QStringLiteral("/.local/bin/piper")};
    const QStringList modelCandidates = {
        QStringLiteral("/usr/share/marathon/voice/en_US-amy-low.onnx"),
        QStringLiteral("/usr/share/piper-voices/en_US-amy-low.onnx"),
        QDir::homePath() +
            QStringLiteral("/.local/share/marathon-apps/maps/voice/en_US-amy-low.onnx")};

    for (const QString &p : binCandidates) {
        if (QFileInfo::exists(p) && QFileInfo(p).isExecutable()) {
            m_piperBin = p;
            break;
        }
    }
    if (m_piperBin.isEmpty())
        return false;

    for (const QString &p : modelCandidates) {
        if (QFileInfo::exists(p)) {
            m_piperModel = p;
            break;
        }
    }
    if (m_piperModel.isEmpty()) {
        qWarning() << "[VoiceClient] Piper binary found at" << m_piperBin
                   << "but no voice model — skipping Piper backend";
        m_piperBin.clear();
        return false;
    }

    m_player.reset(new QMediaPlayer(this));
    auto *audioOut = new QAudioOutput(this);
    m_player->setAudioOutput(audioOut);
    connect(
        m_player.get(), &QMediaPlayer::playbackStateChanged, this,
        [this](QMediaPlayer::PlaybackState s) { setSpeaking(s == QMediaPlayer::PlayingState); });
    return true;
}

void VoiceClient::speak(const QString &text) {
    if (m_muted || !m_available || text.isEmpty())
        return;
    if (m_backend == QLatin1String("piper"))
        speakViaPiper(text);
    else
        speakViaQTextToSpeech(text);
}

void VoiceClient::stop() {
    if (m_backend == QLatin1String("piper")) {
        if (m_player)
            m_player->stop();
        if (m_piperProcess && m_piperProcess->state() != QProcess::NotRunning) {
            m_piperProcess->terminate();
            m_piperProcess->waitForFinished(200);
            if (m_piperProcess->state() != QProcess::NotRunning)
                m_piperProcess->kill();
        }
    } else if (m_tts) {
        m_tts->stop();
    }
    setSpeaking(false);
}

void VoiceClient::speakViaPiper(const QString &text) {
    // Cancel any in-flight synthesis so the latest maneuver wins
    // (re-routing or rapid turns).
    stop();

    // Stream the WAV out to a tempfile so QMediaPlayer can play it
    // without buffering the whole thing in memory.
    m_wavFile.reset(
        new QTemporaryFile(QDir::tempPath() + QStringLiteral("/marathon-nav-XXXXXX.wav"), this));
    if (!m_wavFile->open()) {
        qWarning() << "[VoiceClient] Failed to open temp WAV file";
        return;
    }
    const QString wavPath = m_wavFile->fileName();
    m_wavFile->close();

    m_piperProcess.reset(new QProcess(this));
    m_piperProcess->setProgram(m_piperBin);
    m_piperProcess->setArguments(
        {QStringLiteral("--model"), m_piperModel, QStringLiteral("--output_file"), wavPath});
    connect(m_piperProcess.get(),
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished), this,
            [this, wavPath](int code, QProcess::ExitStatus) {
                if (code != 0) {
                    qWarning() << "[VoiceClient] Piper exited" << code;
                    return;
                }
                m_player->setSource(QUrl::fromLocalFile(wavPath));
                m_player->play();
            });
    m_piperProcess->start();
    if (!m_piperProcess->waitForStarted(500)) {
        qWarning() << "[VoiceClient] Piper failed to start";
        return;
    }
    m_piperProcess->write(text.toUtf8());
    m_piperProcess->closeWriteChannel();
    setSpeaking(true);
}

void VoiceClient::speakViaQTextToSpeech(const QString &text) {
    if (!m_tts)
        return;
    m_tts->stop();
    m_tts->say(text);
}

void VoiceClient::setSpeaking(bool s) {
    if (s != m_speaking) {
        m_speaking = s;
        emit speakingChanged();
    }
}
