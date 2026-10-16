#ifndef PULSESINKBACKEND_H
#define PULSESINKBACKEND_H

#include "sinkvolume.h"

#include <QHash>

#include <pulse/pulseaudio.h>

// libpulse client (PulseAudio or pipewire-pulse). Callbacks run on the
// libpulse thread; signals reach main-thread receivers queued.
class PulseSinkBackend : public SinkBackend {
    Q_OBJECT
  public:
    explicit PulseSinkBackend(QObject *parent = nullptr);
    ~PulseSinkBackend() override;

    bool start();

    void setSinkVolume(const QString &sink, double volume) override;
    void setSinkMuted(const QString &sink, bool muted) override;

  private:
    static void           onState(pa_context *c, void *self);
    static void           onEvent(pa_context *c, pa_subscription_event_type_t t, uint32_t idx,
                                  void *self);
    static void           onServerInfo(pa_context *c, const pa_server_info *info, void *self);
    static void           onSinkInfo(pa_context *c, const pa_sink_info *info, int eol, void *self);
    void                  requestServerInfo();

    pa_threaded_mainloop *m_mainloop = nullptr;
    pa_context           *m_context  = nullptr;
    QHash<QString, int>   m_channels;
};

#endif
