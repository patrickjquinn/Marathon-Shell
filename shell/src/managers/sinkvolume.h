#ifndef SINKVOLUME_H
#define SINKVOLUME_H

#include <QObject>
#include <QString>

// The sound server, as seen by SinkVolume. A backend reports the default
// sink whenever it changes and a sink's state whenever that changes; it
// signals once per write when the server has applied it.
class SinkBackend : public QObject {
    Q_OBJECT
  public:
    using QObject::QObject;

    virtual void setSinkVolume(const QString &sink, double volume) = 0;
    virtual void setSinkMuted(const QString &sink, bool muted)     = 0;

  signals:
    void defaultSinkChanged(const QString &sink);
    void sinkChanged(const QString &sink, double volume, bool muted);
    void volumeWritten();
    void muteWritten();
};

// Volume and mute of whichever sink is the default right now.
class SinkVolume : public QObject {
    Q_OBJECT
  public:
    explicit SinkVolume(SinkBackend *backend, QObject *parent = nullptr);

    QString sink() const {
        return m_sink;
    }
    double volume() const {
        return m_volume;
    }
    bool muted() const {
        return m_muted;
    }

    void setVolume(double volume);
    void setMuted(bool muted);

  signals:
    void volumeChanged();
    void mutedChanged();

  private:
    void         onDefaultSinkChanged(const QString &sink);
    void         onSinkChanged(const QString &sink, double volume, bool muted);
    void         writeVolume();
    void         writeMuted();

    SinkBackend *m_backend;
    QString      m_sink;
    double       m_volume        = 0.6;
    bool         m_muted         = false;
    bool         m_volumePending = false;
    bool         m_mutePending   = false;
    int          m_volumeWrites  = 0;
    int          m_muteWrites    = 0;
};

#endif
