#include <memory>
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
    void initTestCase() {
        // As the shell runs.
        qputenv("QML_NO_TOUCH_COMPRESSION", "1");
    }

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
