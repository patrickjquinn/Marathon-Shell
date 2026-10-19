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

// Touch resampling for the shell window: each frame gets the finger where it
// was half the panel's report spacing (learnt across touches) plus 2 ms
// earlier, 5 to 40 ms, interpolated between the reports around that time, or
// past the last by up to half a spacing at the slower of the last two
// reports' speeds (none across a turn), so a panel slower than the display
// still moves every frame. The content never steps back the way the finger
// goes, nor when it lifts. Presses, releases and cancels pass at once.
// Wayland clients get these moves through the shell.
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

    // True while the frame shown is still behind the latest report.
    bool flush();

    static constexpr qint64 kMinLatencyMs = 5;
    static constexpr qint64 kMaxLatencyMs = 40;

    // The resampled position at time t from the reports a (older) and b.
    static QPointF resample(QPointF a, qint64 ta, QPointF b, qint64 tb, qint64 t);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct Report {
        QEventPoint point;
        qint64      time = 0;
    };
    static constexpr qsizetype kReports = 4;
    struct Track {
        QList<Report> reports;
        QPointF       sent;
        bool          hasSent = false;
    };

    void   record(const QTouchEvent &event);
    void   sendResampled(qint64 at);
    qint64 latency() const;
    qint64 horizon(const Track &track) const;
    static QPointF notBack(const Track &track, QPointF scene);
    static void moveTo(QEventPoint &p, QPointF scene);
    qint64 now() const;

    QPointer<QWindow>       m_window;
    QQuickItem             *m_polisher  = nullptr;
    bool                    m_passthrough = false;
    bool                    m_decided     = false;
    QHash<int, Track>       m_tracks;
    const QPointingDevice  *m_device    = nullptr;
    Qt::KeyboardModifiers   m_modifiers = Qt::NoModifier;
    bool                    m_pending   = false;
    qint64                  m_sentAt    = -1;
    qreal                   m_spacing   = 0;
    qreal                   m_frameAt   = -1;
    qint64                  m_flushedAt = 0;
    bool                    m_sending   = false;
    QElapsedTimer           m_clock;
    qint64                  m_offset    = 0;
    bool                    m_hasOffset = false;
};
