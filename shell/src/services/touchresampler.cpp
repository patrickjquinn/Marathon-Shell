#include "touchresampler.h"

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTouchEvent>
#include <QWindow>
#include <QtGui/private/qeventpoint_p.h>

#include <algorithm>
#include <utility>

namespace {
    class Polisher : public QQuickItem {
      public:
        Polisher(QQuickItem *parent, TouchResampler *resampler)
            : QQuickItem(parent)
            , m_resampler(resampler) {}

        bool again = false;

      protected:
        void updatePolish() override {
            again = m_resampler->flush();
        }

      private:
        TouchResampler *m_resampler;
    };
} // namespace

TouchResampler::TouchResampler(QWindow *window, QQuickItem *content)
    : QObject(window)
    , m_window(window) {
    m_clock.start();
    if (content) {
        auto *polisher = new Polisher(content, this);
        m_polisher     = polisher;
        // Still behind the finger: the next frame shows more of the way.
        if (auto *quick = content->window())
            connect(quick, &QQuickWindow::afterAnimating, this, [polisher] {
                if (std::exchange(polisher->again, false))
                    polisher->polish();
            });
    }
    window->installEventFilter(this);
}

bool TouchResampler::flush() {
    if (!m_pending)
        return false;
    const qint64 at = std::max(now() - latency(), m_sentAt);
    m_sentAt        = at;
    m_pending       = false;
    for (const Track &track : std::as_const(m_tracks))
        m_pending = m_pending || track.reports.last().time + horizon(track) > at;
    sendResampled(at);
    return m_pending;
}

qint64 TouchResampler::horizon(const Track &track) {
    const QList<Report> &r = track.reports;
    if (r.size() < 3)
        return 0;
    const qint64 gap = r.last().time - r.at(r.size() - 2).time;
    return gap <= kMaxLatencyMs ? gap / 2 : 0;
}

qint64 TouchResampler::latency() const {
    qint64 spacing = 0;
    for (const Track &track : m_tracks) {
        const QList<Report> &r = track.reports;
        for (qsizetype i = 1; i < r.size(); ++i) {
            // Longer is the finger resting, not the panel's rate.
            const qint64 gap = r.at(i).time - r.at(i - 1).time;
            if (gap <= kMaxLatencyMs)
                spacing = std::max(spacing, gap);
        }
    }
    return std::clamp(spacing / 2 + 2, kMinLatencyMs, kMaxLatencyMs);
}

QPointF TouchResampler::resample(QPointF a, qint64 ta, QPointF b, qint64 tb, qint64 t) {
    if (tb <= ta)
        return b;
    t = std::clamp(t, ta, tb);
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
        QList<Report> &reports = m_tracks[p.id()].reports;
        if (p.state() == QEventPoint::State::Pressed)
            reports.clear();
        else if (!reports.isEmpty() && p.scenePosition() == reports.last().point.scenePosition())
            continue;
        if (reports.size() == kReports)
            reports.removeFirst();
        Report report{p, qint64(event.timestamp())};
        QMutableEventPoint::detach(report.point);
        reports.append(report);
    }
}

void TouchResampler::sendResampled(qint64 at) {
    if (m_tracks.isEmpty() || !m_window)
        return;
    QList<QEventPoint> points;
    qint64             stamp = 0;
    for (auto it = m_tracks.begin(); it != m_tracks.end(); ++it) {
        Track               &track   = it.value();
        const QList<Report> &reports = track.reports;
        const Report        &latest  = reports.last();
        QEventPoint          p       = latest.point;
        QMutableEventPoint::detach(p);
        QMutableEventPoint::setState(p, QEventPoint::State::Updated);
        if (reports.size() > 1 && at >= 0) {
            qsizetype i = 1;
            while (i < reports.size() - 1 && reports.at(i).time < at)
                ++i;
            const Report &a = reports.at(i - 1), &b = reports.at(i);
            QPointF scene = resample(a.point.scenePosition(), a.time, b.point.scenePosition(), b.time, at);
            const qint64 ahead = std::min(at - latest.time, horizon(track));
            if (ahead > 0) {
                const Report &r1 = reports.at(reports.size() - 3), &r2 = reports.at(reports.size() - 2);
                const QPointF v1 = (r2.point.scenePosition() - r1.point.scenePosition()) / qreal(std::max<qint64>(1, r2.time - r1.time));
                const QPointF v2 = (latest.point.scenePosition() - r2.point.scenePosition()) / qreal(std::max<qint64>(1, latest.time - r2.time));
                // The slower of the last two, and none across a turn.
                auto slower = [](qreal a, qreal b) { return a * b > 0 ? (std::abs(a) < std::abs(b) ? a : b) : 0.0; };
                scene += QPointF(slower(v1.x(), v2.x()), slower(v1.y(), v2.y())) * qreal(ahead);
            }
            // Never back the way the finger goes.
            const QPointF dir = latest.point.scenePosition() - reports.at(reports.size() - 2).point.scenePosition();
            if (track.hasSent) {
                if (dir.x() * (scene.x() - track.sent.x()) < 0)
                    scene.setX(track.sent.x());
                if (dir.y() * (scene.y() - track.sent.y()) < 0)
                    scene.setY(track.sent.y());
            }
            track.sent    = scene;
            track.hasSent = true;
            const QPointF delta = scene - p.scenePosition();
            QMutableEventPoint::setScenePosition(p, scene);
            QMutableEventPoint::setPosition(p, p.position() + delta);
            QMutableEventPoint::setGlobalPosition(p, p.globalPosition() + delta);
        }
        stamp = std::max(stamp, latest.time);
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
        m_sentAt  = -1;
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
