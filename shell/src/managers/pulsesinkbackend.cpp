#include "pulsesinkbackend.h"

#include <QDebug>

PulseSinkBackend::PulseSinkBackend(QObject *parent)
    : SinkBackend(parent) {}

PulseSinkBackend::~PulseSinkBackend() {
    if (m_mainloop)
        pa_threaded_mainloop_stop(m_mainloop);
    if (m_context) {
        pa_context_set_state_callback(m_context, nullptr, nullptr);
        pa_context_disconnect(m_context);
        pa_context_unref(m_context);
    }
    if (m_mainloop)
        pa_threaded_mainloop_free(m_mainloop);
}

// NOFAIL: a server that is not up yet (socket-activated pipewire-pulse)
// is waited for rather than given up on.
bool PulseSinkBackend::start() {
    m_mainloop = pa_threaded_mainloop_new();
    if (!m_mainloop)
        return false;
    m_context = pa_context_new(pa_threaded_mainloop_get_api(m_mainloop), "marathon-shell");
    if (!m_context)
        return false;
    pa_context_set_state_callback(m_context, &PulseSinkBackend::onState, this);
    if (pa_context_connect(m_context, nullptr, PA_CONTEXT_NOFAIL, nullptr) < 0) {
        qWarning() << "[PulseSinkBackend] connect failed:" << pa_strerror(pa_context_errno(m_context));
        return false;
    }
    return pa_threaded_mainloop_start(m_mainloop) >= 0;
}

void PulseSinkBackend::onState(pa_context *c, void *self) {
    auto *b = static_cast<PulseSinkBackend *>(self);
    switch (pa_context_get_state(c)) {
        case PA_CONTEXT_READY: {
            pa_context_set_subscribe_callback(c, &PulseSinkBackend::onEvent, b);
            const auto mask =
                static_cast<pa_subscription_mask_t>(PA_SUBSCRIPTION_MASK_SERVER | PA_SUBSCRIPTION_MASK_SINK);
            if (pa_operation *o = pa_context_subscribe(c, mask, nullptr, nullptr))
                pa_operation_unref(o);
            b->requestServerInfo();
            break;
        }
        case PA_CONTEXT_FAILED:
        case PA_CONTEXT_TERMINATED:
            qWarning() << "[PulseSinkBackend] context failed/terminated";
            emit b->defaultSinkChanged(QString());
            break;
        default: break;
    }
}

void PulseSinkBackend::onEvent(pa_context *c, pa_subscription_event_type_t t, uint32_t idx,
                               void *self) {
    auto      *b        = static_cast<PulseSinkBackend *>(self);
    const auto facility = t & PA_SUBSCRIPTION_EVENT_FACILITY_MASK;
    const auto type     = t & PA_SUBSCRIPTION_EVENT_TYPE_MASK;
    if (facility == PA_SUBSCRIPTION_EVENT_SERVER) {
        b->requestServerInfo();
    } else if (facility == PA_SUBSCRIPTION_EVENT_SINK && type != PA_SUBSCRIPTION_EVENT_REMOVE) {
        if (pa_operation *o = pa_context_get_sink_info_by_index(c, idx, &PulseSinkBackend::onSinkInfo, b))
            pa_operation_unref(o);
    }
}

void PulseSinkBackend::requestServerInfo() {
    if (pa_operation *o = pa_context_get_server_info(m_context, &PulseSinkBackend::onServerInfo, this))
        pa_operation_unref(o);
}

void PulseSinkBackend::onServerInfo(pa_context *c, const pa_server_info *info, void *self) {
    auto         *b    = static_cast<PulseSinkBackend *>(self);
    const QString sink = info && info->default_sink_name ? QString::fromUtf8(info->default_sink_name)
                                                         : QString();
    emit b->defaultSinkChanged(sink);
    if (sink.isEmpty())
        return;
    if (pa_operation *o = pa_context_get_sink_info_by_name(c, info->default_sink_name,
                                                           &PulseSinkBackend::onSinkInfo, b))
        pa_operation_unref(o);
}

void PulseSinkBackend::onSinkInfo(pa_context *, const pa_sink_info *info, int eol, void *self) {
    if (eol != 0 || !info)
        return;
    auto         *b    = static_cast<PulseSinkBackend *>(self);
    const QString name = QString::fromUtf8(info->name);
    b->m_channels.insert(name, info->channel_map.channels);
    emit b->sinkChanged(name, static_cast<double>(pa_cvolume_avg(&info->volume)) / PA_VOLUME_NORM,
                        info->mute != 0);
}

// Linear in pa_volume_t, so a value reads the same as in wpctl and
// pavucontrol.
void PulseSinkBackend::setSinkVolume(const QString &sink, double volume) {
    pa_threaded_mainloop_lock(m_mainloop);
    pa_cvolume cv;
    pa_cvolume_set(&cv, m_channels.value(sink, 2),
                   static_cast<pa_volume_t>(qRound(volume * PA_VOLUME_NORM)));
    pa_operation *o = pa_context_set_sink_volume_by_name(
        m_context, sink.toUtf8().constData(), &cv,
        [](pa_context *, int, void *self) { emit static_cast<PulseSinkBackend *>(self)->volumeWritten(); },
        this);
    if (o)
        pa_operation_unref(o);
    pa_threaded_mainloop_unlock(m_mainloop);
    if (!o)
        emit volumeWritten();
}

void PulseSinkBackend::setSinkMuted(const QString &sink, bool muted) {
    pa_threaded_mainloop_lock(m_mainloop);
    pa_operation *o = pa_context_set_sink_mute_by_name(
        m_context, sink.toUtf8().constData(), muted,
        [](pa_context *, int, void *self) { emit static_cast<PulseSinkBackend *>(self)->muteWritten(); },
        this);
    if (o)
        pa_operation_unref(o);
    pa_threaded_mainloop_unlock(m_mainloop);
    if (!o)
        emit muteWritten();
}
