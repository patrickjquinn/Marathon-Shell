#include <memory>
#include <QElapsedTimer>
#include <QPointingDevice>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QTouchEvent>
#include <QWindow>
#include <QtGui/private/qeventpoint_p.h>

#include "services/touchresampler.h"

// Stands in for a Wayland client's surface: the resampler knows it by name.
class QWaylandQuickItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(bool inputEventsEnabled READ inputEventsEnabled CONSTANT)

  public:
    QWaylandQuickItem() {
        setAcceptTouchEvents(true);
    }
    bool inputEventsEnabled() const {
        return true;
    }

  protected:
    void touchEvent(QTouchEvent *e) override {
        e->accept();
    }
};

class ShellItem : public QQuickItem {
  public:
    int mostPoints = 0;
    ShellItem() {
        setAcceptTouchEvents(true);
    }

  protected:
    void touchEvent(QTouchEvent *e) override {
        mostPoints = std::max(mostPoints, int(e->points().size()));
        e->accept();
    }
};

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

// A panel's moves reach the scene once a frame, a report's spacing behind.
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
    void initTestCase() {
        // As the shell runs.
        qputenv("QML_NO_TOUCH_COMPRESSION", "1");
    }

    void interpolatesBetweenReports() {
        QCOMPARE(TouchResampler::resample({0, 0}, 0, {0, 10}, 10, 5), QPointF(0, 5));
        // Never past the last report.
        QCOMPARE(TouchResampler::resample({0, 0}, 0, {0, 10}, 10, 40), QPointF(0, 10));
    }

    // The HackberryPi's panel reports every 23 ms: every 60 Hz frame still
    // moves, and never ahead of where the finger is.
    void aSlowPanelMovesEveryFrame() {
        Recorder       w;
        TouchResampler resampler(&w, nullptr);
        QElapsedTimer  clock;
        clock.start();
        const ulong t0 = 1000;
        send(w, QEvent::TouchBegin, QEventPoint::State::Pressed, 0, t0);
        qint64 nextReport = 23, nextFrame = 17;
        qreal  latest = 0;
        int    frames = 0, still = 0;
        while (clock.elapsed() < 400) {
            QTest::qWait(1);
            const qint64 t = clock.elapsed();
            if (t >= nextReport) {
                latest = t;
                send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, latest, t0 + t);
                nextReport += 23;
            }
            if (t >= nextFrame) {
                const qsizetype before = w.positions.size();
                resampler.flush();
                nextFrame += 17;
                if (t < 60)
                    continue;
                ++frames;
                if (w.positions.size() == before || w.positions.last().y() <= w.positions.at(before - 1).y())
                    ++still;
                else
                    QVERIFY2(w.positions.last().y() <= clock.elapsed(), "ahead of the finger");
            }
        }
        QVERIFY2(still <= frames / 10, qPrintable(QStringLiteral("%1 of %2 frames still").arg(still).arg(frames)));
    }

    // Frames polish early and late by turns; the content still moves evenly,
    // a frame's worth each, not by the polish clock.
    void anUnevenPolishStillStepsEvenly() {
        Recorder       w;
        TouchResampler resampler(&w, nullptr);
        QElapsedTimer  clock;
        clock.start();
        const ulong t0 = 1000;
        send(w, QEvent::TouchBegin, QEventPoint::State::Pressed, 0, t0);
        qint64 nextReport = 10, nextFrame = 17;
        bool   early = true;
        QList<qreal> steps;
        while (clock.elapsed() < 500) {
            QTest::qWait(1);
            const qint64 t = clock.elapsed();
            if (t >= nextReport) {
                send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, t, t0 + t);
                nextReport += 10;
            }
            if (t >= nextFrame) {
                const qsizetype before = w.positions.size();
                resampler.flush();
                nextFrame += early ? 7 : 27;
                early = !early;
                if (t > 100 && before > 0 && w.positions.size() > before)
                    steps.append(w.positions.last().y() - w.positions.at(before - 1).y());
            }
        }
        QVERIFY(steps.size() > 10);
        for (qreal step : std::as_const(steps))
            QVERIFY2(step > 10 && step < 24, qPrintable(QStringLiteral("a %1 px step").arg(step)));
    }

    // A finger that stops goes at most half a report's spacing on, and
    // the content never steps back while it rests or as it lifts.
    void aStoppingFingerBarelyOvershoots() {
        Recorder       w;
        TouchResampler resampler(&w, nullptr);
        QElapsedTimer  clock;
        clock.start();
        const ulong t0 = 1000;
        send(w, QEvent::TouchBegin, QEventPoint::State::Pressed, 0, t0);
        qint64 nextReport = 23;
        qreal  last = 0, shown = 0;
        while (clock.elapsed() < 300) {
            QTest::qWait(1);
            const qint64 t = clock.elapsed();
            if (t >= nextReport && t < 150) {
                last = t;
                send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, last, t0 + t);
                nextReport += 23;
            }
            if (t % 17 == 0) {
                resampler.flush();
                const qreal y = w.positions.last().y();
                QVERIFY2(y >= shown, "stepped back");
                shown = y;
            }
        }
        QVERIFY2(shown <= last + 12, qPrintable(QStringLiteral("%1 past %2").arg(shown).arg(last)));
        // Lifting there doesn't pull the content back.
        send(w, QEvent::TouchEnd, QEventPoint::State::Released, last, t0 + 300);
        QCOMPARE(w.types.last(), QEvent::TouchEnd);
        QCOMPARE(w.positions.last().y(), shown);
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
        // The finger just passed the drag distance: the drag starts where
        // the raw touch would start it.
        QCOMPARE(w.positions.last().y(), 120.0);

        send(w, QEvent::TouchUpdate, QEventPoint::State::Updated, 130, t0 + 30);
        send(w, QEvent::TouchEnd, QEventPoint::State::Released, 130, t0 + 31);
        QCOMPARE(w.types.size(), 4);
        QCOMPARE(w.types.at(2), QEvent::TouchUpdate);
        QCOMPARE(w.positions.at(2).y(), 130.0);
        QCOMPARE(w.types.at(3), QEvent::TouchEnd);
    }

    // An app's touch passes, and leaves nothing behind for the next one.
    void aClientTouchLeavesNoPointBehind() {
        QQuickWindow window;
        window.resize(720, 720);
        auto *client = new QWaylandQuickItem;
        client->setParentItem(window.contentItem());
        client->setSize({360, 720});
        auto *shell = new ShellItem;
        shell->setParentItem(window.contentItem());
        shell->setZ(-1);
        shell->setSize({720, 720});
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        TouchResampler resampler(&window, window.contentItem());
        std::unique_ptr<QPointingDevice> device(QTest::createTouchDevice());

        QTest::touchEvent(&window, device.get()).press(0, QPoint(100, 300), &window);
        QTest::touchEvent(&window, device.get()).move(0, QPoint(120, 300), &window);
        QTest::touchEvent(&window, device.get()).release(0, QPoint(120, 300), &window);
        // The app goes to the background; home takes the screen.
        client->setVisible(false);

        QTest::touchEvent(&window, device.get()).press(1, QPoint(500, 300), &window);
        for (int x = 510; x < 600; x += 10) {
            QTest::qWait(10);
            QTest::touchEvent(&window, device.get()).move(1, QPoint(x, 300), &window);
        }
        QTest::touchEvent(&window, device.get()).release(1, QPoint(600, 300), &window);
        QCOMPARE(shell->mostPoints, 1);
    }

    // A page swipe at an ordinary finger speed, 11 px a 100 Hz report.
    void aSlowSwipeTurnsThePage_data() {
        QTest::addColumn<int>("step");
        QTest::newRow("300 px/s") << 3;
        QTest::newRow("1100 px/s") << 11;
        QTest::newRow("3000 px/s") << 30;
    }

    void aSlowSwipeTurnsThePage() {
        QFETCH(int, step);
        QQmlEngine    engine;
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            Window {
                width: 720; height: 720; visible: true
                property alias pages: list
                ListView {
                    id: list
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    model: 3
                    currentIndex: 1
                    delegate: Item {
                        width: 720; height: 720
                        MouseArea { anchors.fill: parent }
                    }
                }
            })",
                          QUrl());
        std::unique_ptr<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        auto *window = qobject_cast<QQuickWindow *>(root.get());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        TouchResampler resampler(window, window->contentItem());
        auto *list = root->property("pages").value<QQuickItem *>();
        QTRY_COMPARE(list->property("contentX").toReal(), 720.0);

        std::unique_ptr<QPointingDevice> device(QTest::createTouchDevice());
        int x = 100;
        QTest::touchEvent(window, device.get()).press(0, QPoint(x, 360), window);
        while (x < 100 + 450) {
            QTest::qWait(10);
            x += step;
            QTest::touchEvent(window, device.get()).move(0, QPoint(x, 360), window);
        }
        QTest::touchEvent(window, device.get()).release(0, QPoint(x, 360), window);
        QTRY_COMPARE(list->property("currentIndex").toInt(), 0);
    }
};

int main(int argc, char **argv) {
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents);
    QGuiApplication app(argc, argv);
    TestTouchResampler test;
    return QTest::qExec(&test, argc, argv);
}
#include "test_touchresampler.moc"
