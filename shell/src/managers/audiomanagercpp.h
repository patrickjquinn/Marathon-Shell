#ifndef AUDIOMANAGERCPP_H
#define AUDIOMANAGERCPP_H

#include <QObject>
#include <QAbstractListModel>

#include <qqml.h>

class AudiodClient;
class SinkVolume;

struct AudioStream {
    int     id;
    QString name;
    QString appName;
    double  volume;
    bool    muted;
    QString mediaClass;
};

class AudioStreamModel : public QAbstractListModel {
    Q_OBJECT

  public:
    enum StreamRoles : quint16 {
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
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static AudioManagerCpp *create(QQmlEngine *, QJSEngine *);
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(AudioStreamModel *streams READ streams CONSTANT)
    Q_PROPERTY(bool perAppVolumeSupported READ perAppVolumeSupported NOTIFY availableChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)

  public:
    explicit AudioManagerCpp(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    double            volume() const;
    bool              muted() const;
    AudioStreamModel *streams() {
        return m_streamModel;
    }
    bool perAppVolumeSupported() const {
        return m_available;
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

  private:
    void              updateStreams();

    bool              m_available;
    bool              m_isPlaying;
    AudioStreamModel *m_streamModel;
    AudiodClient     *m_audiod;
    SinkVolume       *m_sinkVolume;
};

#endif
