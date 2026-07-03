#include "fpsmonitor.h"

#include <QQuickWindow>

FpsMonitor::FpsMonitor(QObject *parent) : QObject(parent) {
    m_sampleTimer.setInterval(500);
    connect(&m_sampleTimer, &QTimer::timeout, this, &FpsMonitor::sample);
}

void FpsMonitor::attach(QQuickWindow *window) {
    if (!window)
        return;
    // frameSwapped fires on the GUI thread once per presented frame under
    // both the basic and threaded render loops -- a DirectConnection would
    // land on the render thread, so keep the default AutoConnection.
    connect(window, &QQuickWindow::frameSwapped, this, [this]() { ++m_frames; });
    m_clock.start();
    m_sampleTimer.start();
}

void FpsMonitor::sample() {
    const qint64 elapsed = m_clock.restart();
    const qreal  fps     = elapsed > 0 ? (m_frames * 1000.0) / elapsed : 0.0;
    m_frames             = 0;
    if (qAbs(fps - m_fps) > 0.1) {
        m_fps = fps;
        emit fpsChanged();
    }
}
