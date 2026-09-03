#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>

class QQuickWindow;

// Live FPS counter driven by QQuickWindow::frameSwapped. Counts presented
// frames over a fixed sampling window and exposes the rate to QML so an
// on-screen overlay can show real render throughput during interaction.
// Reads ~0 when idle (Qt only renders on change) and the true rate while
// anything animates. Diagnostic only -- gated by MARATHON_FPS_OVERLAY.
class FpsMonitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(qreal fps READ fps NOTIFY fpsChanged)

public:
    explicit FpsMonitor(QObject *parent = nullptr);

    // Connect to a window's frame-swap signal and start sampling.
    void  attach(QQuickWindow *window);
    qreal fps() const { return m_fps; }

signals:
    void fpsChanged();

private:
    void sample();

    qreal         m_fps    = 0.0;
    int           m_frames = 0;
    QElapsedTimer m_clock;
    QTimer        m_sampleTimer;
};
