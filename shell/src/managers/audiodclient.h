#ifndef AUDIODCLIENT_H
#define AUDIODCLIENT_H

#include "sinkvolume.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QList>
#include <QVariantMap>
#include <functional>

class QDBusServiceWatcher;

// A playback stream as marathon-audiod lists it.
struct AudiodStream {
    uint    id = 0;
    QString name;
    double  volume = 0.0;
    bool    muted  = false;

    bool    operator==(const AudiodStream &o) const {
        return id == o.id && name == o.name && volume == o.volume && muted == o.muted;
    }
};
Q_DECLARE_METATYPE(AudiodStream)

QDBusArgument       &operator<<(QDBusArgument &arg, const AudiodStream &stream);
const QDBusArgument &operator>>(const QDBusArgument &arg, AudiodStream &stream);

// marathon-audiod's org.marathonos.Audio1: the default sink, playback
// streams and call controls. Writes are answered once PipeWire has them.
class AudiodClient : public SinkBackend {
    Q_OBJECT
  public:
    explicit AudiodClient(const QDBusConnection &bus, QObject *parent = nullptr);

    static const QString &serviceName();

    bool                  available() const {
        return m_available;
    }
    const QList<AudiodStream> &streams() const {
        return m_streams;
    }

    // Reads every property; activates the service if it is not running.
    void refresh();

    void setSinkVolume(const QString &sink, double volume) override;
    void setSinkMuted(const QString &sink, bool muted) override;
    void setStreamVolume(uint id, double volume);
    void setStreamMuted(uint id, bool muted);
    void setInputMuted(bool muted);
    void setSpeakerphone(bool on);

  signals:
    void availableChanged();
    void streamsChanged();

  private slots:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);

  private:
    void                 apply(const QVariantMap &props);
    void                 setAvailable(bool available);
    void                 call(const QString &method, const QVariantList &args,
                              const std::function<void()> &done = {});

    QDBusConnection      m_bus;
    QDBusServiceWatcher *m_watcher;
    bool                 m_available = false;
    QString              m_sink;
    double               m_volume = 0.0;
    bool                 m_muted  = false;
    QList<AudiodStream>  m_streams;
};

#endif
