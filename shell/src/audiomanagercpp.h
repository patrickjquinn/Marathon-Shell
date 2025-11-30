#ifndef AUDIOMANAGERCPP_H
#define AUDIOMANAGERCPP_H

#include <QObject>
#include <QAbstractListModel>
#include <QTimer>

#include <pulse/pulseaudio.h>

struct AudioStream {
    int     id;
    QString name;
    QString appName;
    double  volume;
    bool    muted;
    QString mediaClass; // "Stream/Output/Audio" etc.
};

class AudioStreamModel : public QAbstractListModel {
    Q_OBJECT

  public:
    enum StreamRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        AppNameRole,
        VolumeRole,
        MutedRole,
        MediaClassRole
    };

    explicit AudioStreamModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void                   updateStreams(const QList<AudioStream> &streams);
    AudioStream           *getStream(int streamId);

  private:
    QList<AudioStream> m_streams;
};

class AudioManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(AudioStreamModel *streams READ streams CONSTANT)
    Q_PROPERTY(bool perAppVolumeSupported READ perAppVolumeSupported CONSTANT)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)

  public:
    explicit AudioManagerCpp(QObject *parent = nullptr);
    ~AudioManagerCpp();

    bool available() const {
        return m_available;
    }
    double volume() const {
        return m_currentVolume;
    }
    bool muted() const {
        return m_muted;
    }
    AudioStreamModel *streams() {
        return m_streamModel;
    }
    bool perAppVolumeSupported() const {
        return m_available && m_isPipeWire;
    }
    bool isPlaying() const {
        return m_isPlaying;
    }

    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void setStreamVolume(int streamId, double volume);
    Q_INVOKABLE void setStreamMuted(int streamId, bool muted);
    Q_INVOKABLE void refreshStreams();

  signals:
    void availableChanged();
    void volumeChanged();
    void mutedChanged();
    void streamsChanged();
    void isPlayingChanged();
    void streamPlaybackStateChanged(int streamId, bool playing);

  private slots:
    void updateFromPulse(double vol, bool isMuted);

  private:
    void        parseWpctlStatus();
    void        startStreamMonitoring();
    void        updatePlaybackState();

    bool        initPulseAudio();
    void        cleanupPulseAudio();
    void        requestDefaultSink();
    static void paContextStateCallback(pa_context *c, void *userdata);
    static void paSinkInfoCallback(pa_context *c, const pa_sink_info *i, int eol, void *userdata);

    bool        m_available;
    bool        m_isPipeWire;
    double      m_currentVolume;
    bool        m_muted;
    bool        m_isPlaying;
    AudioStreamModel     *m_streamModel;
    QTimer               *m_streamRefreshTimer;

    QString               m_defaultSinkName;
    int                   m_sinkChannels;

    pa_threaded_mainloop *m_pa_mainloop;
    pa_context           *m_pa_context;
};

#endif // AUDIOMANAGERCPP_H
