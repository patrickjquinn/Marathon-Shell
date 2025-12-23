#pragma once

#include <QObject>
#include <QPointer>
#include <QUrl>

class AudioManagerCpp;
class HapticManager;
class SettingsManager;

class QAudioOutput;
class QMediaPlayer;

class AudioPolicyController : public QObject {
    Q_OBJECT

  public:
    explicit AudioPolicyController(AudioManagerCpp *audioManager, SettingsManager *settings,
                                   HapticManager *haptics, QObject *parent = nullptr);

    Q_INVOKABLE void setMasterVolume(double volume);
    Q_INVOKABLE void setMuted(bool muted);

    Q_INVOKABLE void setDoNotDisturb(bool enabled);
    Q_INVOKABLE void setVibrationEnabled(bool enabled);
    Q_INVOKABLE void setAudioProfile(const QString &profile);

    Q_INVOKABLE void playRingtone();
    Q_INVOKABLE void stopRingtone();

    Q_INVOKABLE void playNotificationSound();

    Q_INVOKABLE void playAlarmSound();
    Q_INVOKABLE void stopAlarmSound();

    Q_INVOKABLE void previewSound(const QString &soundPath);

    Q_INVOKABLE void vibratePattern(const QVariantList &pattern);

  private:
    void applyProfileSideEffects(const QString &profile);
    void wirePlayerVolumes();

    void ensurePlayer(QMediaPlayer *&player, QAudioOutput *&output, double initialVolume,
                      bool loopForever);
    void startPlayback(QMediaPlayer *player, const QUrl &source, bool loopForever);

    QPointer<AudioManagerCpp> m_audioManager;
    QPointer<SettingsManager> m_settings;
    QPointer<HapticManager>   m_haptics;

    QMediaPlayer             *m_ringtonePlayer;
    QAudioOutput             *m_ringtoneOutput;

    QMediaPlayer             *m_notificationPlayer;
    QAudioOutput             *m_notificationOutput;

    QMediaPlayer             *m_alarmPlayer;
    QAudioOutput             *m_alarmOutput;

    QMediaPlayer             *m_previewPlayer;
    QAudioOutput             *m_previewOutput;
};
