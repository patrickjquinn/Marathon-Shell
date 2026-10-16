#include "services/waketouchfilter.h"

#include <QGuiApplication>
#include <QPointingDevice>
#include <QTest>
#include <QWindow>

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
};

QTEST_MAIN(TestWakeTouchFilter)
#include "test_waketouchfilter.moc"
