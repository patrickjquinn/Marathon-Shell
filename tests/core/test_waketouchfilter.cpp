#include "services/waketouchfilter.h"

#include <QGuiApplication>
#include <QPointingDevice>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTest>
#include <QWindow>

#include <memory>

namespace {

    class TouchWindow : public QWindow {
      public:
        QList<QEvent::Type> seen;

      protected:
        bool event(QEvent *e) override {
            switch (e->type()) {
                case QEvent::TouchBegin:
                case QEvent::TouchUpdate:
                case QEvent::TouchEnd: seen << e->type(); return true;
                default: return QWindow::event(e);
            }
        }
    };

} // namespace

class TestWakeTouchFilter : public QObject {
    Q_OBJECT

    WakeTouchFilter *m_filter = nullptr;
    TouchWindow     *m_window = nullptr;
    QPointingDevice *m_device = nullptr;

    void             press() {
        QTest::touchEvent(m_window, m_device).press(0, QPoint(10, 10));
    }
    void move() {
        QTest::touchEvent(m_window, m_device).move(0, QPoint(20, 20));
    }
    void release() {
        QTest::touchEvent(m_window, m_device).release(0, QPoint(20, 20));
    }

  private slots:
    void initTestCase() {
        m_device = QTest::createTouchDevice();
    }

    void init() {
        m_filter = new WakeTouchFilter;
        qApp->installEventFilter(m_filter);
        m_window = new TouchWindow;
        m_window->resize(100, 100);
        m_window->show();
        QVERIFY(QTest::qWaitForWindowExposed(m_window));
    }

    void cleanup() {
        delete m_window;
        delete m_filter;
    }

    void touchPassesWhileAwake() {
        press();
        move();
        release();
        QCOMPARE(m_window->seen,
                 (QList<QEvent::Type>{QEvent::TouchBegin, QEvent::TouchUpdate, QEvent::TouchEnd}));
    }

    void touchIsDroppedRightAfterWake() {
        m_filter->setScreenOn(true);
        press();
        release();
        QVERIFY(m_window->seen.isEmpty());
    }

    void aFingerDownAcrossWakeIsDroppedUntilItLifts() {
        m_filter->setScreenOn(false);
        press();
        m_filter->setScreenOn(true);
        QTest::qWait(WakeTouchFilter::BlockMs + 20);
        move();
        release();
        QVERIFY(m_window->seen.isEmpty());
        press();
        release();
        QCOMPARE(m_window->seen, (QList<QEvent::Type>{QEvent::TouchBegin, QEvent::TouchEnd}));
    }

    void aFreshTouchAfterTheBlockPasses() {
        m_filter->setScreenOn(true);
        QTest::qWait(WakeTouchFilter::BlockMs + 20);
        press();
        release();
        QCOMPARE(m_window->seen, (QList<QEvent::Type>{QEvent::TouchBegin, QEvent::TouchEnd}));
    }

    void aTouchUnderWayWhenTheScreenGoesOffEnds() {
        press();
        m_filter->setScreenOn(false);
        move();
        release();
        QCOMPARE(m_window->seen,
                 (QList<QEvent::Type>{QEvent::TouchBegin, QEvent::TouchUpdate, QEvent::TouchEnd}));
    }

    void aTouchUnderWayAcrossAWakeEnds() {
        press();
        m_filter->setScreenOn(true);
        release();
        QCOMPARE(m_window->seen, (QList<QEvent::Type>{QEvent::TouchBegin, QEvent::TouchEnd}));
    }

    void aSceneStillTakesTapsAfterAWakeMidTouch() {
        QQmlEngine    engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\n"
                          "Window { width: 100; height: 100; visible: true\n"
                          "  property int taps: 0\n"
                          "  MouseArea { anchors.fill: parent; onClicked: taps++ } }",
                          QUrl());
        std::unique_ptr<QObject> created(component.create());
        auto                    *scene = qobject_cast<QQuickWindow *>(created.get());
        QVERIFY2(scene, qPrintable(component.errorString()));
        QVERIFY(QTest::qWaitForWindowExposed(scene));

        QTest::touchEvent(scene, m_device).press(0, QPoint(10, 10));
        m_filter->setScreenOn(false);
        QTest::touchEvent(scene, m_device).release(0, QPoint(10, 10));
        m_filter->setScreenOn(true);
        QTest::qWait(WakeTouchFilter::BlockMs + 20);
        const int before = scene->property("taps").toInt();
        for (int i = 0; i < 2; ++i) {
            QTest::touchEvent(scene, m_device).press(0, QPoint(10, 10));
            QTest::touchEvent(scene, m_device).release(0, QPoint(10, 10));
        }
        QCOMPARE(scene->property("taps").toInt(), before + 2);
    }
};

QTEST_MAIN(TestWakeTouchFilter)
#include "test_waketouchfilter.moc"
