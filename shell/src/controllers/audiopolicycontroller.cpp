#include "audiopolicycontroller.h"

#include "marathon-shell-native/src/audio.cxxqt.h"
#include "marathon-shell-native/src/haptics.cxxqt.h"
#include "mediarole.h"
#include "settingsmanager.h"

#include <QAudioOutput>
#include <QDebug>
#include <QMediaPlayer>
#include <QtGlobal>

namespace {
    QUrl toUrl(const QString &pathOrUrl) {
        QUrl url(pathOrUrl);
        if (url.isValid() && !url.scheme().isEmpty()) {
            return url;
        }
        return QUrl::fromLocalFile(pathOrUrl);
    }
}

AudioPolicyController::AudioPolicyController(marathon::Audio *audioManager,
                                             SettingsManager *settings, Haptics *haptics,
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

    if (m_audioManager && m_settings) {
        connect(m_audioManager, &marathon::Audio::volumeChanged, this, [this]() {
            if (!m_audioManager || !m_settings)
                return;
            const double v = m_audioManager->getVolume();
            if (!qFuzzyCompare(m_settings->systemVolume(), v)) {
                m_settings->setSystemVolume(v);
            }
        });
    }

    wirePlayerVolumes();

    if (m_settings) {
        connect(m_settings, &SettingsManager::audioProfileChanged, this,
                &AudioPolicyController::audioProfileChanged);
        connect(m_settings, &SettingsManager::dndEnabledChanged, this,
                &AudioPolicyController::doNotDisturbChanged);
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

QString AudioPolicyController::audioProfile() const {
    return m_settings ? m_settings->audioProfile() : QString();
}

bool AudioPolicyController::isDoNotDisturb() const {
    return m_settings ? m_settings->dndEnabled() : false;
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

        setMasterVolume(0.9);
    }
}

void AudioPolicyController::ensurePlayer(QMediaPlayer *&player, QAudioOutput *&output,
                                         double initialVolume, bool) {
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

bool AudioPolicyController::ringerAudible(const QString &profile, bool dnd) {
    return !dnd && profile != QLatin1String("silent") && profile != QLatin1String("vibrate");
}

void AudioPolicyController::playRingtone() {
    if (!m_settings)
        return;
    if (!ringerAudible(m_settings->audioProfile(), m_settings->dndEnabled())) {
        qInfo() << "[AudioPolicyController] Ringtone suppressed (profile or DND)";
        return;
    }

    ensurePlayer(m_ringtonePlayer, m_ringtoneOutput, m_settings->ringtoneVolume(), true);
    m_ringtoneOutput->setDevice(MediaRole::output("ringtone"));
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
    if (!ringerAudible(m_settings->audioProfile(), m_settings->dndEnabled())) {
        qInfo() << "[AudioPolicyController] Notification suppressed (profile or DND)";
        return;
    }

    ensurePlayer(m_notificationPlayer, m_notificationOutput, notificationLevel(), false);
    m_notificationOutput->setDevice(MediaRole::output("notification"));
    startPlayback(m_notificationPlayer, toUrl(m_settings->notificationSound()), false);
}

void AudioPolicyController::playAlarmSound() {
    if (!m_settings)
        return;

    ensurePlayer(m_alarmPlayer, m_alarmOutput, m_settings->alarmVolume(), true);
    m_alarmOutput->setDevice(MediaRole::output("alarm"));
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

    m_haptics->vibratePattern(pattern);
}

void AudioPolicyController::wirePlayerVolumes() {
    if (!m_settings)
        return;

    connect(m_settings, &SettingsManager::ringtoneVolumeChanged, this, [this]() {
        if (m_ringtoneOutput && m_settings) {
            m_ringtoneOutput->setVolume(qBound(0.0, m_settings->ringtoneVolume(), 1.0));
        }
    });
    const auto updateNotification = [this]() {
        if (m_notificationOutput)
            m_notificationOutput->setVolume(notificationLevel());
    };
    connect(m_settings, &SettingsManager::notificationVolumeChanged, this, updateNotification);
    if (m_audioManager) {
        connect(m_audioManager, &marathon::Audio::volumeChanged, this, updateNotification);
        connect(m_audioManager, &marathon::Audio::mutedChanged, this, updateNotification);
    }
    connect(m_settings, &SettingsManager::alarmVolumeChanged, this, [this]() {
        if (m_alarmOutput && m_settings) {
            m_alarmOutput->setVolume(qBound(0.0, m_settings->alarmVolume(), 1.0));
        }
    });
}

double AudioPolicyController::notificationLevel() const {
    double level = m_settings ? qBound(0.0, m_settings->notificationVolume(), 1.0) : 1.0;
    if (m_audioManager)
        level *= m_audioManager->getMuted() ? 0.0 : m_audioManager->getVolume();
    return level;
}
