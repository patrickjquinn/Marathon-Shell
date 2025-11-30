#ifndef AUDIOROUTINGMANAGER_H
#define AUDIOROUTINGMANAGER_H

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QDebug>

/**
 * @brief Manages audio routing for phone calls using PipeWire/WirePlumber
 * 
 * This class handles:
 * - Switching between HiFi and VoiceCall ALSA UCM profiles
 * - Earpiece vs speakerphone routing
 * - Microphone mute/unmute
 * - Bluetooth headset routing
 * 
 * Based on KDE Plasma Mobile's approach but using direct PipeWire integration
 * instead of callaudiod dependency.
 */
class AudioRoutingManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isInCall READ isInCall NOTIFY inCallChanged)
    Q_PROPERTY(bool isSpeakerphoneEnabled READ isSpeakerphoneEnabled NOTIFY speakerphoneChanged)
    Q_PROPERTY(bool isMuted READ isMuted NOTIFY mutedChanged)
    Q_PROPERTY(QString currentAudioDevice READ currentAudioDevice NOTIFY audioDeviceChanged)

  public:
    explicit AudioRoutingManager(QObject *parent = nullptr);
    ~AudioRoutingManager();

    bool isInCall() const {
        return m_isInCall;
    }
    bool isSpeakerphoneEnabled() const {
        return m_isSpeakerphoneEnabled;
    }
    bool isMuted() const {
        return m_isMuted;
    }
    QString currentAudioDevice() const {
        return m_currentAudioDevice;
    }

  public slots:
    /**
     * @brief Start call audio routing
     * Switches from HiFi profile to VoiceCall profile
     * Routes audio to earpiece by default
     */
    void startCallAudio();

    /**
     * @brief Stop call audio routing
     * Switches back from VoiceCall to HiFi profile
     * Restores normal audio routing
     */
    void stopCallAudio();

    /**
     * @brief Toggle speakerphone on/off
     * @param enabled - true for speakerphone, false for earpiece
     */
    void setSpeakerphone(bool enabled);

    /**
     * @brief Toggle microphone mute
     * @param muted - true to mute, false to unmute
     */
    void setMuted(bool muted);

    /**
     * @brief Manually select audio output device
     * @param device - "earpiece", "speaker", "bluetooth", "headset"
     */
    void selectAudioDevice(const QString &device);

  signals:
    void inCallChanged(bool isInCall);
    void speakerphoneChanged(bool enabled);
    void mutedChanged(bool muted);
    void audioDeviceChanged(const QString &device);
    void audioRoutingFailed(const QString &error);

  private slots:
    void onWpctlFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void detectAudioDevices();

  private:
    void    switchProfile(const QString &profileName);
    void    setDefaultSink(const QString &sinkName);
    void    runWpctlCommand(const QString &command, const QStringList &args);
    QString findAudioCard();
    QString findSinkByName(const QString &name);
    void    parseWpctlStatus(const QString &output);

    bool    m_isInCall;
    bool    m_isSpeakerphoneEnabled;
    bool    m_isMuted;
    QString m_currentAudioDevice;

    // Audio device IDs discovered from wpctl status
    QString   m_audioCardId;
    QString   m_earpieceSinkId;
    QString   m_speakerSinkId;
    QString   m_bluetoothSinkId;
    QString   m_microphoneSourceId;

    QString   m_previousProfile; // Store HiFi profile to restore

    QProcess *m_wpctlProcess;
    QTimer   *m_deviceDetectionTimer;
};

#endif // AUDIOROUTINGMANAGER_H
