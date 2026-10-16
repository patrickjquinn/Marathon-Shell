#include "sinkvolume.h"

#include <QtGlobal>

SinkVolume::SinkVolume(SinkBackend *backend, QObject *parent)
    : QObject(parent)
    , m_backend(backend) {
    connect(m_backend, &SinkBackend::defaultSinkChanged, this, &SinkVolume::onDefaultSinkChanged);
    connect(m_backend, &SinkBackend::sinkChanged, this, &SinkVolume::onSinkChanged);
    connect(m_backend, &SinkBackend::volumeWritten, this, [this] {
        if (m_volumeWrites > 0)
            --m_volumeWrites;
    });
    connect(m_backend, &SinkBackend::muteWritten, this, [this] {
        if (m_muteWrites > 0)
            --m_muteWrites;
    });
}

void SinkVolume::setVolume(double volume) {
    volume = qBound(0.0, volume, 1.0);
    if (!qFuzzyCompare(volume, m_volume)) {
        m_volume = volume;
        emit volumeChanged();
    }
    m_volumePending = true;
    writeVolume();
}

void SinkVolume::setMuted(bool muted) {
    if (muted != m_muted) {
        m_muted = muted;
        emit mutedChanged();
    }
    m_mutePending = true;
    writeMuted();
}

// Set before a default sink exists (at boot): applied to the first one.
void SinkVolume::onDefaultSinkChanged(const QString &sink) {
    m_sink = sink;
    writeVolume();
    writeMuted();
}

// A report that crosses a write of ours in flight is stale for that field.
void SinkVolume::onSinkChanged(const QString &sink, double volume, bool muted) {
    if (sink != m_sink)
        return;
    volume = qBound(0.0, volume, 1.0);
    if (m_volumeWrites == 0 && !qFuzzyCompare(volume, m_volume)) {
        m_volume = volume;
        emit volumeChanged();
    }
    if (m_muteWrites == 0 && muted != m_muted) {
        m_muted = muted;
        emit mutedChanged();
    }
}

void SinkVolume::writeVolume() {
    if (!m_volumePending || m_sink.isEmpty())
        return;
    m_volumePending = false;
    ++m_volumeWrites;
    m_backend->setSinkVolume(m_sink, m_volume);
}

void SinkVolume::writeMuted() {
    if (!m_mutePending || m_sink.isEmpty())
        return;
    m_mutePending = false;
    ++m_muteWrites;
    m_backend->setSinkMuted(m_sink, m_muted);
}
