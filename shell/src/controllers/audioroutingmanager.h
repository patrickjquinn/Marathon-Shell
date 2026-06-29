#ifndef AUDIOROUTINGMANAGER_H
#define AUDIOROUTINGMANAGER_H

#include <QObject>
#include <QProcess>
#include <QDebug>
#include <memory>

class AudioRoutingManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isInCall READ isInCall NOTIFY inCallChanged)
    Q_PROPERTY(bool isSpeakerphoneEnabled READ isSpeakerphoneEnabled NOTIFY speakerphoneChanged)
    Q_PROPERTY(bool isMuted READ isMuted NOTIFY mutedChanged)
    Q_PROPERTY(QString currentAudioDevice READ currentAudioDevice NOTIFY audioDeviceChanged)

  public:
    explicit AudioRoutingManager(QObject *parent = nullptr);
    ~AudioRoutingManager() override;

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

    void startCallAudio();

    void stopCallAudio();

    void setSpeakerphone(bool enabled);

    void setMuted(bool muted);

    void selectAudioDevice(const QString &device);

  signals:
    void inCallChanged(bool isInCall);
    void speakerphoneChanged(bool enabled);
    void mutedChanged(bool muted);
    void audioDeviceChanged(const QString &device);
    void audioRoutingFailed(const QString &error);

  private slots:
    void onWpctlFinished(int exitCode, QProcess::ExitStatus exitStatus);

  private:
    void    switchProfile(const QString &profileName);
    void    setDefaultSink(const QString &sinkName);
    void    runWpctlCommand(const QString &command, const QStringList &args);
    QString findAudioCard();
    QString findSinkByName(const QString &name);

  public:
    // Bridge entry points invoked from the pipewire thread loop via
    // QMetaObject::invokeMethod. Public so the C registry callbacks (defined
    // in the .cpp anonymous namespace) can reach them; not part of the
    // public surface for callers.
    struct PwState;
    void onPwGlobalAdded(quint32 id, const QString &type, const QString &nodeName,
                         const QString &deviceName, const QString &mediaClass);
    void onPwGlobalRemoved(quint32 id);

  private:
    bool      m_isInCall;
    bool      m_isSpeakerphoneEnabled;
    bool      m_isMuted;
    QString   m_currentAudioDevice;

    QString   m_audioCardId;
    QString   m_audioCardName;
    QString   m_earpieceSinkId;
    QString   m_speakerSinkId;
    QString   m_bluetoothSinkId;
    QString   m_microphoneSourceId;

    QString   m_previousProfile;

    QProcess *m_wpctlProcess;

    // PipeWire registry subscription. PwState (forward-declared above) is
    // defined in audioroutingmanager.cpp so the pipewire headers stay out
    // of the public include set.
    std::unique_ptr<PwState> m_pw;
};

#endif
