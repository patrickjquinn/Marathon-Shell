#include <QPointingDevice>
#include <QTest>
#include <QTouchEvent>
#include <QWindow>
#include <QtGui/private/qeventpoint_p.h>

#include "services/touchresampler.h"

namespace {
    class Recorder : public QWindow {
      public:
        QList<QEvent::Type> types;
        QList<QPointF>      positions;

      protected:
        bool event(QEvent *e) override {
            if (e->type() == QEvent::TouchBegin || e->type() == QEvent::TouchUpdate ||
                e->type() == QEvent::TouchEnd) {
                auto *t = static_cast<QTouchEvent *>(e);
                types.append(e->type());
                positions.append(t->points().first().scenePosition());
                return true;
            }
            return QWindow::event(e);
        }
    };
} // namespace

// A 100 Hz panel's moves reach the scene one a frame, at frame time minus 5 ms.
class TestTouchResampler : public QObject {
    Q_OBJECT

    QPointingDevice m_device{"panel", 1, QInputDevice::DeviceType::TouchScreen,
                             QPointingDevice::PointerType::Finger,
                             QInputDevice::Capability::Position, 1, 0};

    void send(QWindow &w, QEvent::Type type, QEventPoint::State state, qreal y, ulong t) {
        QEventPoint p(1, state, QPointF(100, y), QPointF(100, y));
        QTouchEvent e(type, &m_device, Qt::NoModifier, {p});
        e.setTimestamp(t);
        QCoreApplication::sendEvent(&w, &e);
    }

  private slots:
    void interpolatesBetweenReports() {
        QCOMPARE(TouchResampler::resample({0, 0}, 0, {0, 10}, 10, 5), QPointF(0, 5));
        QCOMPARE(TouchResampler::resample({0, 0}, 0, {0, 10}, 10, 14), QPointF(0, 14));
        // At most 8 ms past the last report.
        QCOMPARE(TouchResampler::resample({0, 0}, 0, {0, 10}, 10, 40), QPointF(0, 18));
    }

    void movesWaitForTheFrameAndPressesDont() {
        Recorder       w;
        TouchResampler resampler(&w, nullptr);
        const ulong    t0 = 1000;
        send(w, QEvent::TouchBegin, QEventPoint::State::Pressed, 100, t0);
        QCOMPARE(w.types, QList<QEvent::Type>{QEvent::TouchBegin});
        send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, 110, t0 + 10);
        send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, 120, t0 + 20);
        QCOMPARE(w.types.size(), 1);

        resampler.flush();
        QCOMPARE(w.types.size(), 2);
        QCOMPARE(w.types.last(), QEvent::TouchUpdate);
        // The frame comes as the last report does: 5 ms back is between the two.
        QCOMPARE(w.positions.last().y(), 115.0);

        send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, 130, t0 + 30);
        send(w, QEvent::TouchEnd, QEventPoint::State::Released, 130, t0 + 31);
        QCOMPARE(w.types.size(), 4);
        QCOMPARE(w.types.at(2), QEvent::TouchUpdate);
        QCOMPARE(w.positions.at(2).y(), 130.0);
        QCOMPARE(w.types.at(3), QEvent::TouchEnd);
    }
};

QTEST_MAIN(TestTouchResampler)
#include "test_touchresampler.moc"
