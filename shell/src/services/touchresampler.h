#pragma once

#include <QElapsedTimer>
#include <QEventPoint>
#include <QHash>
#include <QObject>
#include <QPointer>

class QPointingDevice;
class QQuickItem;
class QTouchEvent;
class QWindow;

// Android's touch resampling for the shell window: moves wait for the next
// frame, which gets one at its time minus 5 ms, interpolated between the
// reports around it (or up to 8 ms past the last). Presses, releases and
// cancels pass at once. Wayland clients get these moves through the shell.
// Only for the shell's own items: a touch whose press a Wayland client's
// surface took passes untouched, since resampling an app's input slowed it.
// The move is handed over while the frame polishes: the changes it makes
// join that frame's sync, where any earlier they would ask for a frame of
// their own, an empty one that halves the rate. Needs Qt Quick's touch
// compression off (QML_NO_TOUCH_COMPRESSION), which would hold it a frame.
class TouchResampler : public QObject {
  public:
    // Polishes through an item in content; without one, call flush() a frame.
    TouchResampler(QWindow *window, QQuickItem *content);

    void flush();

    static constexpr qint64 kLatencyMs       = 5;
    static constexpr qint64 kMaxPredictionMs = 8;

    // The resampled position at time t from the reports a (older) and b.
    static QPointF resample(QPointF a, qint64 ta, QPointF b, qint64 tb, qint64 t);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct Report {
        QEventPoint point;
        qint64      time = 0;
    };
    struct Track {
        Report older;
        Report latest;
        bool   hasOlder = false;
    };

    void   record(const QTouchEvent &event);
    void   sendResampled(qint64 at);
    qint64 now() const;

    QPointer<QWindow>       m_window;
    QQuickItem             *m_polisher  = nullptr;
    bool                    m_passthrough = false;
    bool                    m_decided     = false;
    QHash<int, Track>       m_tracks;
    const QPointingDevice  *m_device    = nullptr;
    Qt::KeyboardModifiers   m_modifiers = Qt::NoModifier;
    bool                    m_pending   = false;
    bool                    m_sending   = false;
    QElapsedTimer           m_clock;
    qint64                  m_offset    = 0;
    bool                    m_hasOffset = false;
};
