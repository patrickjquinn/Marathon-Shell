#pragma once

#include <QObject>
#include <QPointer>
#include <QUrl>
#include <qqml.h>

namespace marathon {
    class Audio;
    class Settings;
}
class Haptics;

class QAudioOutput;
class QMediaPlayer;

class AudioPolicyController : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(AudioPolicyControllerCpp)
    QML_SINGLETON

  public:
    explicit AudioPolicyController(marathon::Audio *audioManager, marathon::Settings *settings,
                                   Haptics *haptics, QObject *parent = nullptr);

    Q_INVOKABLE void setMasterVolume(double volume);
    Q_INVOKABLE void setMuted(bool muted);

    Q_INVOKABLE void setDoNotDisturb(bool enabled);
    Q_INVOKABLE bool isDoNotDisturb() const;
    Q_INVOKABLE void setVibrationEnabled(bool enabled);
    Q_INVOKABLE void setAudioProfile(const QString &profile);
    QString          audioProfile() const;

    Q_INVOKABLE void playRingtone();
    Q_INVOKABLE void stopRingtone();

    Q_INVOKABLE void playNotificationSound();

    Q_INVOKABLE void playAlarmSound();
    Q_INVOKABLE void stopAlarmSound();

    Q_INVOKABLE void previewSound(const QString &soundPath);

    Q_INVOKABLE void vibratePattern(const QVariantList &pattern);

    // Ringtones and notifications are silent in the silent and vibrate
    // profiles and under DND; alarms ring regardless, as on Android.
    static bool ringerAudible(const QString &profile, bool dnd);

  signals:
    void audioProfileChanged();
    void doNotDisturbChanged();

  private:
    void applyProfileSideEffects(const QString &profile);
    void   wirePlayerVolumes();
    double notificationLevel() const;

    void ensurePlayer(QMediaPlayer *&player, QAudioOutput *&output, double initialVolume,
                      bool loopForever);
    void startPlayback(QMediaPlayer *player, const QUrl &source, bool loopForever);

    QPointer<marathon::Audio> m_audioManager;
    QPointer<marathon::Settings> m_settings;
    QPointer<Haptics>         m_haptics;

    QMediaPlayer             *m_ringtonePlayer;
    QAudioOutput             *m_ringtoneOutput;

    QMediaPlayer             *m_notificationPlayer;
    QAudioOutput             *m_notificationOutput;

    QMediaPlayer             *m_alarmPlayer;
    QAudioOutput             *m_alarmOutput;

    QMediaPlayer             *m_previewPlayer;
    QAudioOutput             *m_previewOutput;
};
