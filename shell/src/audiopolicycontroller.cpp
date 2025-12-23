#include "audiopolicycontroller.h"

#include "audiomanagercpp.h"
#include "hapticmanager.h"
#include "settingsmanager.h"

#include <QAudioOutput>
#include <QDebug>
#include <QMediaPlayer>
#include <QtGlobal>

namespace {
    QUrl toUrl(const QString &pathOrUrl) {
        const QUrl url(pathOrUrl);
        if (url.isValid() && !url.scheme().isEmpty()) {
            return url;
        }
        return QUrl::fromLocalFile(pathOrUrl);
    }
} // namespace

AudioPolicyController::AudioPolicyController(AudioManagerCpp *audioManager,
                                             SettingsManager *settings, HapticManager *haptics,
                                             QObject *parent)
    : QObject(parent)
    , m_audioManager(audioManager)
    , m_settings(settings)
    , m_haptics(haptics)
    , m_ringtonePlayer(nullptr)
    , m_ringtoneOutput(nullptr)
    , m_notificationPlayer(nullptr)
    , m_notificationOutput(nullptr)
    , m_alarmPlayer(nullptr)
    , m_alarmOutput(nullptr)
    , m_previewPlayer(nullptr)
    , m_previewOutput(nullptr) {
    // Keep SettingsManager's persisted master volume in sync with runtime changes.
    if (m_audioManager && m_settings) {
        connect(m_audioManager, &AudioManagerCpp::volumeChanged, this, [this]() {
            if (!m_audioManager || !m_settings)
                return;
            const double v = m_audioManager->volume();
            if (!qFuzzyCompare(m_settings->systemVolume(), v)) {
                m_settings->setSystemVolume(v);
            }
        });
    }

    wirePlayerVolumes();

    // IMPORTANT:
    // When running the shell inside another desktop session (dev/testing), we must NOT
    // stomp global system audio state (mute/volume) on startup, or we will "duck" whatever
    // audio is already playing on the host.
    //
    // Only enforce persisted profile side-effects automatically when we are actually the
    // active desktop session.
    if (m_settings) {
        const QString profile           = m_settings->audioProfile();
        const QString desktop           = qEnvironmentVariable("XDG_CURRENT_DESKTOP");
        const QString session           = qEnvironmentVariable("XDG_SESSION_DESKTOP");
        const bool    isMarathonSession = (desktop.compare("marathon", Qt::CaseInsensitive) == 0) ||
            (session.compare("marathon", Qt::CaseInsensitive) == 0);

        if (isMarathonSession) {
            applyProfileSideEffects(profile);
        } else {
            qInfo() << "[AudioPolicyController] Skipping profile side-effects on startup (desktop:"
                    << desktop << "session:" << session << "profile:" << profile << ")";
        }
    }
}

void AudioPolicyController::setMasterVolume(double volume) {
    if (!m_audioManager || !m_settings)
        return;

    volume = qBound(0.0, volume, 1.0);
    m_audioManager->setVolume(volume);
    m_settings->setSystemVolume(volume);
}

void AudioPolicyController::setMuted(bool muted) {
    if (!m_audioManager)
        return;
    m_audioManager->setMuted(muted);
}

void AudioPolicyController::setDoNotDisturb(bool enabled) {
    if (!m_settings)
        return;
    m_settings->setDndEnabled(enabled);
}

void AudioPolicyController::setVibrationEnabled(bool enabled) {
    if (!m_settings)
        return;
    m_settings->setVibrationEnabled(enabled);
    if (m_haptics) {
        m_haptics->setEnabled(enabled);
    }
}

void AudioPolicyController::setAudioProfile(const QString &profile) {
    if (!m_settings)
        return;

    static const QSet<QString> kAllowed = {"silent", "vibrate", "normal", "loud"};
    if (!kAllowed.contains(profile)) {
        qWarning() << "[AudioPolicyController] Invalid audio profile:" << profile;
        return;
    }

    m_settings->setAudioProfile(profile);
    applyProfileSideEffects(profile);
}

void AudioPolicyController::applyProfileSideEffects(const QString &profile) {
    if (!m_settings || !m_audioManager)
        return;

    if (profile == "silent") {
        setMuted(true);
        setVibrationEnabled(false);
    } else if (profile == "vibrate") {
        setMuted(true);
        setVibrationEnabled(true);
    } else if (profile == "normal") {
        setMuted(false);
        setVibrationEnabled(true);
    } else if (profile == "loud") {
        setMuted(false);
        setVibrationEnabled(true);
        // "Loud" implies a high master volume.
        setMasterVolume(0.9);
    }
}

void AudioPolicyController::ensurePlayer(QMediaPlayer *&player, QAudioOutput *&output,
                                         double initialVolume, bool /*loopForever*/) {
    if (!output) {
        output = new QAudioOutput(this);
        output->setMuted(false);
        output->setVolume(qBound(0.0, initialVolume, 1.0));
    }
    if (!player) {
        player = new QMediaPlayer(this);
        player->setAudioOutput(output);
        connect(player, &QMediaPlayer::errorOccurred, this,
                [player](QMediaPlayer::Error error, const QString &errorString) {
                    qWarning() << "[AudioPolicyController] Player error:" << error << errorString
                               << "source:" << player->source();
                });
    }
}

void AudioPolicyController::startPlayback(QMediaPlayer *player, const QUrl &source,
                                          bool loopForever) {
    if (!player)
        return;

    player->stop();
    player->setSource(source);
    player->setLoops(loopForever ? QMediaPlayer::Infinite : 1);
    player->play();
}

void AudioPolicyController::playRingtone() {
    if (!m_settings)
        return;
    if (m_settings->dndEnabled()) {
        qInfo() << "[AudioPolicyController] Ringtone suppressed (DND enabled)";
        return;
    }

    ensurePlayer(m_ringtonePlayer, m_ringtoneOutput, m_settings->ringtoneVolume(), true);
    startPlayback(m_ringtonePlayer, toUrl(m_settings->ringtone()), true);
}

void AudioPolicyController::stopRingtone() {
    if (m_ringtonePlayer) {
        m_ringtonePlayer->stop();
    }
}

void AudioPolicyController::playNotificationSound() {
    if (!m_settings)
        return;
    if (m_settings->dndEnabled()) {
        qInfo() << "[AudioPolicyController] Notification suppressed (DND enabled)";
        return;
    }

    ensurePlayer(m_notificationPlayer, m_notificationOutput, m_settings->notificationVolume(),
                 false);
    startPlayback(m_notificationPlayer, toUrl(m_settings->notificationSound()), false);
}

void AudioPolicyController::playAlarmSound() {
    if (!m_settings)
        return;

    ensurePlayer(m_alarmPlayer, m_alarmOutput, m_settings->alarmVolume(), true);
    startPlayback(m_alarmPlayer, toUrl(m_settings->alarmSound()), true);
}

void AudioPolicyController::stopAlarmSound() {
    if (m_alarmPlayer) {
        m_alarmPlayer->stop();
    }
}

void AudioPolicyController::previewSound(const QString &soundPath) {
    ensurePlayer(m_previewPlayer, m_previewOutput, 0.7, false);
    startPlayback(m_previewPlayer, toUrl(soundPath), false);
}

void AudioPolicyController::vibratePattern(const QVariantList &pattern) {
    if (!m_settings || !m_settings->vibrationEnabled())
        return;
    if (!m_haptics)
        return;

    m_haptics->vibratePatternVariant(pattern);
}

void AudioPolicyController::wirePlayerVolumes() {
    if (!m_settings)
        return;

    connect(m_settings, &SettingsManager::ringtoneVolumeChanged, this, [this]() {
        if (m_ringtoneOutput && m_settings) {
            m_ringtoneOutput->setVolume(qBound(0.0, m_settings->ringtoneVolume(), 1.0));
        }
    });
    connect(m_settings, &SettingsManager::notificationVolumeChanged, this, [this]() {
        if (m_notificationOutput && m_settings) {
            m_notificationOutput->setVolume(qBound(0.0, m_settings->notificationVolume(), 1.0));
        }
    });
    connect(m_settings, &SettingsManager::alarmVolumeChanged, this, [this]() {
        if (m_alarmOutput && m_settings) {
            m_alarmOutput->setVolume(qBound(0.0, m_settings->alarmVolume(), 1.0));
        }
    });
}
