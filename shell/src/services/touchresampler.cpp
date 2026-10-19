#include "touchresampler.h"

#include <QCoreApplication>
#include <QQuickItem>
#include <QTouchEvent>
#include <QWindow>
#include <QtGui/private/qeventpoint_p.h>

#include <algorithm>

namespace {
    class Polisher : public QQuickItem {
      public:
        Polisher(QQuickItem *parent, TouchResampler *resampler)
            : QQuickItem(parent)
            , m_resampler(resampler) {}

      protected:
        void updatePolish() override {
            m_resampler->flush();
        }

      private:
        TouchResampler *m_resampler;
    };
} // namespace

TouchResampler::TouchResampler(QWindow *window, QQuickItem *content)
    : QObject(window)
    , m_window(window) {
    m_clock.start();
    if (content)
        m_polisher = new Polisher(content, this);
    window->installEventFilter(this);
}

void TouchResampler::flush() {
    if (!m_pending)
        return;
    m_pending = false;
    sendResampled(now() - kLatencyMs);
}

QPointF TouchResampler::resample(QPointF a, qint64 ta, QPointF b, qint64 tb, qint64 t) {
    if (tb <= ta)
        return b;
    t = std::min(t, tb + kMaxPredictionMs);
    const qreal alpha = qreal(t - ta) / qreal(tb - ta);
    return a + (b - a) * alpha;
}

qint64 TouchResampler::now() const {
    return m_clock.elapsed() + m_offset;
}

void TouchResampler::record(const QTouchEvent &event) {
    // Event times count from the reports' reading; this clock from
    // delivery, which can only be later: the largest gap is the offset.
    const qint64 offset = qint64(event.timestamp()) - m_clock.elapsed();
    if (!m_hasOffset || offset > m_offset) {
        m_offset    = offset;
        m_hasOffset = true;
    }
    m_device    = event.pointingDevice();
    m_modifiers = event.modifiers();
    for (const QEventPoint &p : event.points()) {
        if (p.state() == QEventPoint::State::Released) {
            m_tracks.remove(p.id());
            continue;
        }
        Track &track = m_tracks[p.id()];
        if (p.state() != QEventPoint::State::Pressed && track.latest.time > 0) {
            if (p.scenePosition() == track.latest.point.scenePosition())
                continue;
            track.older    = track.latest;
            track.hasOlder = true;
        } else {
            track.hasOlder = false;
        }
        track.latest.point = p;
        QMutableEventPoint::detach(track.latest.point);
        track.latest.time = qint64(event.timestamp());
    }
}

void TouchResampler::sendResampled(qint64 at) {
    if (m_tracks.isEmpty() || !m_window)
        return;
    QList<QEventPoint> points;
    qint64             stamp = 0;
    for (auto it = m_tracks.cbegin(); it != m_tracks.cend(); ++it) {
        const Track &track = it.value();
        QEventPoint  p     = track.latest.point;
        QMutableEventPoint::detach(p);
        QMutableEventPoint::setState(p, QEventPoint::State::Updated);
        if (track.hasOlder && at >= 0) {
            const QPointF scene = resample(track.older.point.scenePosition(), track.older.time,
                                           track.latest.point.scenePosition(), track.latest.time,
                                           at);
            const QPointF delta = scene - p.scenePosition();
            QMutableEventPoint::setScenePosition(p, scene);
            QMutableEventPoint::setPosition(p, p.position() + delta);
            QMutableEventPoint::setGlobalPosition(p, p.globalPosition() + delta);
        }
        stamp = std::max(stamp, track.latest.time);
        points.append(p);
    }
    // Never later than the newest report: Qt would take a later time as a
    // new report and recompute the points' velocity from it.
    QTouchEvent event(QEvent::TouchUpdate, m_device, m_modifiers, points);
    event.setTimestamp(ulong(at >= 0 ? std::min(at, stamp) : stamp));
    m_sending = true;
    QCoreApplication::sendEvent(m_window, &event);
    m_sending = false;
}

bool TouchResampler::eventFilter(QObject *watched, QEvent *event) {
    if (watched != m_window || m_sending)
        return false;
    // A client's surface took the press: its touch passes as it comes.
    // A new sequence: no finger is down, so nothing earlier can be held,
    // whether or not this filter saw how it ended.
    if (event->type() == QEvent::TouchBegin) {
        m_decided = false;
        m_pending = false;
        m_tracks.clear();
    }
    if (event->type() == QEvent::TouchUpdate && !m_decided) {
        auto *touch   = static_cast<QTouchEvent *>(event);
        const QObject *grabber =
            touch->points().isEmpty() ? nullptr : touch->exclusiveGrabber(touch->points().first());
        m_passthrough = grabber && grabber->inherits("QWaylandQuickItem");
        m_decided     = true;
    }
    if (m_passthrough && event->type() != QEvent::TouchBegin) {
        if (event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel)
            m_tracks.clear();
        return false;
    }
    switch (event->type()) {
        case QEvent::TouchUpdate: {
            auto      *touch   = static_cast<QTouchEvent *>(event);
            const auto states  = touch->touchPointStates();
            const bool onlyMoves = !states.testFlag(QEventPoint::State::Pressed) &&
                !states.testFlag(QEventPoint::State::Released);
            if (onlyMoves) {
                record(*touch);
                m_pending = true;
                if (m_polisher)
                    m_polisher->polish();
                // Accepted, or QGuiApplication makes a mouse move of it.
                touch->accept();
                return true;
            }
            break;
        }
        case QEvent::TouchBegin:
        case QEvent::TouchEnd:
        case QEvent::TouchCancel:
            break;
        default: return false;
    }
    // A press or release: the moves held so far land where the finger was.
    if (m_pending) {
        m_pending = false;
        sendResampled(-1);
    }
    if (event->type() == QEvent::TouchCancel)
        m_tracks.clear();
    else
        record(*static_cast<QTouchEvent *>(event));
    return false;
}
